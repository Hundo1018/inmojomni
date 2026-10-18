"""IRQ -> GPIO latency gate: build, flash, measure, verify, report.

Six firmwares take the same measurement (bench/irq_latency.mojo and
bench/irq_latency.c): a GPIO edge raises IO_IRQ_BANK0, the handler's
first instruction drives a second GPIO, and a PIO state machine at
125 MHz counts the pad-to-pad delay in 2-cycle (16 ns) steps, 10,000
times per run, 3 runs per firmware.

  Mojo     handler in XIP flash | handler in SRAM (build --ramfunc)
  C gcc    handler in XIP flash | handler in SRAM (section attribute)
  C clang  handler in XIP flash | handler in SRAM

Gates (any failure raises):
  - clk_sys measured on-chip (frequency counter) within 124-126 MHz
  - the PIO program words every firmware reports equal the reference
    program assembled here with pico.pio.Asm
  - handler address in SRAM (0x2000_xxxx) / flash (0x1000_xxxx) per variant
  - exactly N interrupts per run were taken (no missed or spurious IRQ)
  - run-to-run spread of the mean < 2% (as in bench.mojo)
  - min/avg/max the host recomputes from the 10,000 raw samples of the
    last run equal the firmware's running statistics

Results go to the console and build/irq_latency_results.csv.
Usage: pixi run irq-latency   (one Pico + CMSIS-DAP probe; no wiring)
"""

from std.time import sleep

import build as buildmod
from hil import _sh as quiet_sh, flash, read_words
from pico.pio import Asm

comptime MB: UInt32 = 0x2003_0000
comptime MAGIC: UInt32 = 0x4952_514C
comptime SAMPLES: UInt32 = 0x2001_0000
comptime N = 10_000
comptime RUNS = 3
comptime HIST = 4096  # histogram bins over the raw count (count < 4096)
comptime NS_PER_CYCLE = 8  # 125 MHz


def reference_program() -> Asm:
    """The measurement program; firmware must report exactly these words."""
    var a = Asm()
    a.wait_gpio(0, 15)
    a.wait_gpio(1, 15)
    a.mov_x_not_null()
    var loop = a.label()
    var done = a.future()
    a.jmp_pin(done)
    a.jmp_x_dec(loop)
    a.bind(done)
    a.in_x(32)
    a.push_block()
    return a^


struct Variant(Copyable, Movable):
    var name: String
    var lang: String
    var lang_id: UInt32
    var in_ram: Bool
    var elf: String

    def __init__(
        out self, name: String, lang: String, lang_id: UInt32, in_ram: Bool
    ):
        self.name = name
        self.lang = lang
        self.lang_id = lang_id
        self.in_ram = in_ram
        self.elf = String()


struct Result(Copyable, Movable):
    var khz: UInt32
    var first: UInt32  # count, run 0 iteration 0
    var mn: UInt32  # count, over all runs
    var mx: UInt32
    var mx_warm: UInt32  # count, runs 1.. (run 0 holds the cold first IRQ)
    var sum_all: UInt64  # over all runs
    var p50: UInt32  # counts, last run
    var p99: UInt32
    var p999: UInt32
    var isr_addr: UInt32

    def __init__(out self):
        self.khz = 0
        self.first = 0
        self.mn = 0
        self.mx = 0
        self.mx_warm = 0
        self.sum_all = 0
        self.p50 = 0
        self.p99 = 0
        self.p999 = 0
        self.isr_addr = 0


def _rj(s: String, w: Int) -> String:
    var out = s
    while out.byte_length() < w:
        out = String(" ") + out
    return out


def _lj(s: String, w: Int) -> String:
    var out = s
    while out.byte_length() < w:
        out += " "
    return out


def cycles(count: UInt32) -> UInt32:
    """PIO count -> clk_sys cycles between the two pad edges."""
    return 2 * count + 2


def ns(count: UInt32) -> UInt32:
    return cycles(count) * NS_PER_CYCLE


def avg_ns_x10(sum: UInt64, n: UInt64) -> UInt64:
    # mean cycles = 2*sum/n + 2 ; x 8 ns x 10
    return ((2 * sum + 2 * n) * NS_PER_CYCLE * 10 + n / 2) / n


def _fixed1(x10: UInt64) -> String:
    return String(x10 / 10) + "." + String(x10 % 10)


def build_c(cc: String, in_ram: Bool, name: String) raises -> String:
    var obj = String("build/") + name + ".o"
    var elf = String("build/") + name + ".elf"
    var defs = String(" -DISR_IN_RAM") if in_ram else String()
    if cc == "gcc":
        _ = buildmod.sh(
            "arm-none-eabi-gcc -mcpu=cortex-m0plus -mthumb -O2"
            + " -ffunction-sections -fdata-sections" + defs
            + " -c bench/irq_latency.c -o " + obj
        )
    else:
        _ = buildmod.sh(
            buildmod.CLANG + " --target=armv6m-none-eabi -mcpu=cortex-m0plus -O2"
            + " -ffreestanding -fshort-enums -ffunction-sections"
            + " -fdata-sections -DLANG_ID=3" + defs
            + " -c bench/irq_latency.c -o " + obj
        )
    _ = buildmod.sh(
        "arm-none-eabi-gcc -mcpu=cortex-m0plus -mthumb -c runtime/crt0.S"
        + " -o build/crt0.o"
    )
    _ = buildmod.sh(
        "arm-none-eabi-gcc -mcpu=cortex-m0plus -mthumb -nostdlib"
        + " -nostartfiles -T runtime/link.ld -Wl,--gc-sections"
        + " build/crt0.o " + obj + " -lgcc -o " + elf
    )
    return elf^


def isr_address(elf: String) raises -> UInt32:
    var out = quiet_sh(
        String("arm-none-eabi-nm ") + elf + " | awk '$3==\"isr_irq13\"{print $1}'"
    )
    var tok = String(out.strip())
    if tok.byte_length() != 8:
        raise Error("isr_irq13 not found in " + elf)
    var v: UInt32 = 0
    var b = tok.as_bytes()
    for i in range(len(b)):
        var c = b[i]
        if c >= UInt8(ord("0")) and c <= UInt8(ord("9")):
            v = (v << 4) | UInt32(c - UInt8(ord("0")))
        elif c >= UInt8(ord("a")) and c <= UInt8(ord("f")):
            v = (v << 4) | (UInt32(c - UInt8(ord("a"))) + 10)
        else:
            raise Error("bad nm address: " + tok)
    return v


def run_target(v: Variant) raises -> Result:
    flash(v.elf)
    # 30,000 interrupts at ~6 µs each finish in well under a second; do
    # not poll before then (each probe-rs attach steals AHB cycles).
    sleep(2.0)
    var head = List[UInt32]()
    var done = False
    for _ in range(20):
        head = read_words(MB, 0x20)
        if head[0] == MAGIC and (head[1] == 2 or head[1] == 3):
            done = True
            break
        sleep(0.5)
    if not done:
        raise Error(v.name + ": firmware never finished (status "
                    + String(Int(head[1])) + ")")
    if head[1] == 3:
        raise Error(v.name + ": firmware error code " + String(Int(head[8])))
    if head[2] != N or head[3] != RUNS:
        raise Error(v.name + ": N/runs mismatch -- stale firmware?")
    if head[4] != v.lang_id:
        raise Error(v.name + ": language id " + String(Int(head[4])))
    var r = Result()
    r.khz = head[5]
    if r.khz < 124_000 or r.khz > 126_000:
        raise Error(v.name + ": clk_sys measured " + String(Int(r.khz))
                    + " kHz, expected 125,000 +-1%")
    r.first = head[6]
    if head[7] != UInt32(N * RUNS):
        raise Error(v.name + ": " + String(Int(head[7])) + " interrupts taken,"
                    + " expected " + String(N * RUNS))
    # PIO program identity
    var want = reference_program()
    var plen = Int(head[0x18])
    if plen != want.len:
        raise Error(v.name + ": PIO program length " + String(plen))
    for i in range(plen):
        if head[0x19 + i] != UInt32(want.code[i]):
            raise Error(v.name + ": PIO program word " + String(i)
                        + " differs from the reference")
    # per-run statistics + spread gate on the mean
    var sums = List[UInt32]()
    r.mn = 0xFFFF_FFFF
    r.mx = 0
    for run in range(RUNS):
        var mn = head[0x0C + run * 3]
        var mx = head[0x0D + run * 3]
        var sm = head[0x0E + run * 3]
        if mn < r.mn:
            r.mn = mn
        if mx > r.mx:
            r.mx = mx
        if run > 0 and mx > r.mx_warm:
            r.mx_warm = mx
        r.sum_all += UInt64(sm)
        sums.append(sm)
    var lo = sums[0]
    var hi = sums[0]
    for run in range(1, RUNS):
        if sums[run] < lo:
            lo = sums[run]
        if sums[run] > hi:
            hi = sums[run]
    if (UInt64(hi - lo) * 100) / UInt64(lo) >= 2:
        raise Error(v.name + ": run spread of the mean exceeds 2% ("
                    + String(Int(lo)) + ".." + String(Int(hi)) + " summed counts)")
    # raw samples of the last run: recompute, then percentiles
    var samples = read_words(SAMPLES, N)
    var hist = List[UInt32](length=HIST, fill=0)
    var smn: UInt32 = 0xFFFF_FFFF
    var smx: UInt32 = 0
    var ssum: UInt32 = 0
    for i in range(N):
        var s = samples[i]
        if s < smn:
            smn = s
        if s > smx:
            smx = s
        ssum += s
        var b = Int(s) if s < UInt32(HIST) else HIST - 1
        hist[b] += 1
    var last = RUNS - 1
    if smn != head[0x0C + last * 3] or smx != head[0x0D + last * 3] or ssum != head[0x0E + last * 3]:
        raise Error(v.name + ": host-recomputed min/max/sum of the last run"
                    + " differ from the firmware's")
    var acc = 0
    var got50 = False
    var got99 = False
    for b in range(HIST):
        acc += Int(hist[b])
        if not got50 and acc * 100 >= N * 50:
            r.p50 = UInt32(b)
            got50 = True
        if not got99 and acc * 100 >= N * 99:
            r.p99 = UInt32(b)
            got99 = True
        if acc * 1000 >= N * 999:
            r.p999 = UInt32(b)
            break
    return r^


def main() raises:
    var variants = List[Variant]()
    variants.append(Variant(String("Mojo, ISR in flash"), String("mojo"), 1, False))
    variants.append(Variant(String("Mojo, ISR in RAM"), String("mojo"), 1, True))
    variants.append(Variant(String("C gcc, ISR in flash"), String("c_gcc"), 2, False))
    variants.append(Variant(String("C gcc, ISR in RAM"), String("c_gcc"), 2, True))
    variants.append(Variant(String("C clang, ISR in flash"), String("c_clang"), 3, False))
    variants.append(Variant(String("C clang, ISR in RAM"), String("c_clang"), 3, True))

    print("building 6 firmwares...")
    for i in range(len(variants)):
        var v = variants[i].copy()
        var suffix = String("_ram") if v.in_ram else String()
        var name = String("irq_latency_") + v.lang + suffix
        if v.lang == "mojo":
            v.elf = buildmod.build(
                "bench/irq_latency.mojo", name, False,
                String("isr_irq13") if v.in_ram else String(),
            )
        elif v.lang == "c_gcc":
            v.elf = build_c("gcc", v.in_ram, name)
        else:
            v.elf = build_c("clang", v.in_ram, name)
        variants[i] = v^

    var results = List[Result]()
    for i in range(len(variants)):
        var v = variants[i].copy()
        var addr = isr_address(v.elf)
        var region = addr >> 24
        if v.in_ram and region != 0x20:
            raise Error(v.name + ": isr_irq13 at " + hex(Int(addr)) + ", not in SRAM")
        if not v.in_ram and region != 0x10:
            raise Error(v.name + ": isr_irq13 at " + hex(Int(addr)) + ", not in flash")
        print("running " + v.name + " (" + String(RUNS) + " x " + String(N)
              + " interrupts)...")
        var r = run_target(v)
        r.isr_addr = addr
        results.append(r^)

    print()
    print("IRQ -> GPIO latency, RP2040 @ 125 MHz, pad to pad, "
          + String(RUNS) + " x " + String(N) + " interrupts per firmware (ns):")
    print(_lj(String("firmware"), 24) + _rj(String("first"), 7)
          + _rj(String("min"), 7) + _rj(String("p50"), 7) + _rj(String("p99"), 7)
          + _rj(String("p99.9"), 7) + _rj(String("max warm"), 9)
          + _rj(String("max all"), 8) + _rj(String("mean"), 8)
          + _rj(String("clk kHz"), 9))
    var csv = String("firmware,language,isr_location,isr_addr,clk_khz,first_ns,")
    csv += "min_ns,p50_ns,p99_ns,p999_ns,max_warm_ns,max_ns,mean_ns_x10,min_cycles,max_cycles\n"
    for i in range(len(results)):
        var r = results[i].copy()
        var v = variants[i].copy()
        var total = UInt64(N * RUNS)
        var mean = avg_ns_x10(r.sum_all, total)
        print(_lj(v.name, 24) + _rj(String(Int(ns(r.first))), 7)
              + _rj(String(Int(ns(r.mn))), 7) + _rj(String(Int(ns(r.p50))), 7)
              + _rj(String(Int(ns(r.p99))), 7) + _rj(String(Int(ns(r.p999))), 7)
              + _rj(String(Int(ns(r.mx_warm))), 9) + _rj(String(Int(ns(r.mx))), 8)
              + _rj(_fixed1(mean), 8) + _rj(String(Int(r.khz)), 9))
        csv += (v.name + "," + v.lang + ","
                + (String("ram") if v.in_ram else String("flash")) + ","
                + hex(Int(r.isr_addr)) + "," + String(Int(r.khz)) + ","
                + String(Int(ns(r.first))) + "," + String(Int(ns(r.mn))) + ","
                + String(Int(ns(r.p50))) + "," + String(Int(ns(r.p99))) + ","
                + String(Int(ns(r.p999))) + "," + String(Int(ns(r.mx_warm))) + ","
                + String(Int(ns(r.mx))) + "," + String(mean) + "," + String(Int(cycles(r.mn))) + ","
                + String(Int(cycles(r.mx))) + "\n")
    print("(first = run 0 iteration 0, cold caches; max warm = runs 2.."
          + String(RUNS) + "; p50/p99/p99.9 over the last run; resolution"
          + " 16 ns = 2 PIO cycles)")
    print("gates passed: clk_sys 125 MHz +-1%, PIO program identical,"
          + " ISR placement, N interrupts per run, run spread < 2%,"
          + " host-recomputed statistics")
    var f = open("build/irq_latency_results.csv", "w")
    f.write(csv)
    f.close()
    print("wrote build/irq_latency_results.csv")
