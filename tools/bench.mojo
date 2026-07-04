"""Build, flash and time the Mojo, C and Rust benchmark firmwares.

Four firmwares run the same nine workloads: Mojo (this project's
pipeline), C via arm-none-eabi-gcc -O2, C via clang -O2 (the same LLVM
backend the Mojo pipeline uses, isolating language overhead from backend
differences) and Rust -C opt-level=2 (also LLVM). All share crt0.S,
link.ld, libgcc, the clock setup and the 1 MHz hardware timer.

Each firmware executes the whole suite RUNS times. The host verifies:
  - checksums are identical across runs (in-firmware determinism),
  - timing spread across runs is < 2%,
  - checksums are identical across all four languages.
Median times go to the console table and build/bench_results.csv.

Usage: pixi run bench   (requires a CMSIS-DAP probe, clang and rustc)
"""

from std.time import sleep

import build as buildmod
from hil import flash, read_words

comptime MB: UInt32 = 0x2003_0000
comptime MAGIC: UInt32 = 0x42454E43
comptime COUNT = 9
comptime RUNS = 3


def _names() -> List[String]:
    var n = List[String]()
    n.append(String("gpio_toggle"))
    n.append(String("xorshift"))
    n.append(String("div"))
    n.append(String("f32"))
    n.append(String("call"))
    n.append(String("crc32"))
    n.append(String("sort"))
    n.append(String("mat16"))
    n.append(String("fib"))
    return n^


def _descs() -> List[String]:
    var d = List[String]()
    d.append(String("100k GPIO toggles (SIO XOR)"))
    d.append(String("200k xorshift32 rounds"))
    d.append(String("50k u32 divisions (software)"))
    d.append(String("20k float32 mul-adds (soft-float)"))
    d.append(String("100k noinline function calls"))
    # keep these comma-free: they go into bench_results.csv unquoted
    d.append(String("CRC-32 over 4 KB x4 (bitwise)"))
    d.append(String("quicksort 512 u32 x20"))
    d.append(String("16x16 u32 matmul x50"))
    d.append(String("recursive fib(24)"))
    return d^


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


def _ratio2(num: UInt32, den: UInt32) -> String:
    if den == 0:
        return String("inf")
    var centi = (UInt64(num) * 100 + UInt64(den) / 2) / UInt64(den)
    var whole = centi / 100
    var frac = Int(centi % 100)
    var fs = String(frac)
    if frac < 10:
        fs = String("0") + fs
    return String(whole) + "." + fs


def build_c(cc: String) raises -> String:
    var obj = String("build/bench_") + cc + ".o"
    var elf = String("build/bench_") + cc + ".elf"
    if cc == "gcc":
        _ = buildmod.sh(
            "arm-none-eabi-gcc -mcpu=cortex-m0plus -mthumb -O2"
            + " -ffunction-sections -fdata-sections -c bench/bench.c -o "
            + obj
        )
    else:
        # -fshort-enums matches the AAPCS variable-size-enum ABI that
        # arm-none-eabi libgcc.a is built with (no enums cross the
        # boundary; this only silences linker ABI-tag warnings).
        _ = buildmod.sh(
            "clang --target=armv6m-none-eabi -mcpu=cortex-m0plus -O2"
            + " -ffreestanding -fshort-enums"
            + " -ffunction-sections -fdata-sections -c bench/bench.c -o "
            + obj
        )
    _link(obj, elf)
    return elf^


def build_rust() raises -> String:
    var lib = String("build/libbench_rust.a")
    var elf = String("build/bench_rust.elf")
    _ = buildmod.sh(
        "rustc --edition 2021 --target thumbv6m-none-eabi"
        + " --crate-type staticlib -C opt-level=2 -C codegen-units=1"
        + " -C panic=abort -o " + lib + " bench/bench.rs"
    )
    _link(lib, elf)
    return elf^


def _link(obj: String, elf: String) raises:
    _ = buildmod.sh(
        "arm-none-eabi-gcc -mcpu=cortex-m0plus -mthumb -c runtime/crt0.S"
        + " -o build/crt0.o"
    )
    _ = buildmod.sh(
        "arm-none-eabi-gcc -mcpu=cortex-m0plus -mthumb -nostdlib"
        + " -nostartfiles -T runtime/link.ld -Wl,--gc-sections"
        + " build/crt0.o " + obj + " -lgcc -o " + elf
    )


def run_bench(elf: String) raises -> List[UInt32]:
    """Flash and return the raw runs*workloads*(µs, ck) word list."""
    flash(elf)
    # Do NOT poll while the suite runs: every probe-rs attach steals
    # ~6 ms of AHB bus time from the core at 12 MHz, which measurably
    # inflates whichever workload it lands in (the 3-run spread check
    # is what catches this). Sleep past the expected duration first.
    sleep(15.0)
    var done = False
    for _ in range(30):
        var head = read_words(MB, 4)
        if head[0] == MAGIC and head[1] == 2:
            if head[2] != COUNT or head[3] != RUNS:
                raise Error(
                    "mailbox reports count=" + String(Int(head[2]))
                    + " runs=" + String(Int(head[3]))
                    + " — stale firmware?"
                )
            done = True
            break
        sleep(2.0)
    if not done:
        raise Error("benchmark on " + elf + " never finished")
    return read_words(MB + 0x10, RUNS * COUNT * 2)


def reduce_runs(
    lang: String, flat: List[UInt32]
) raises -> Tuple[List[UInt32], List[UInt32]]:
    """Median µs and checksum per workload; assert determinism."""
    var names = _names()
    var med = List[UInt32]()
    var cks = List[UInt32]()
    for i in range(COUNT):
        var t = List[UInt32]()
        var c = List[UInt32]()
        for r in range(RUNS):
            var k = (r * COUNT + i) * 2
            t.append(flat[k])
            c.append(flat[k + 1])
        for r in range(1, RUNS):
            if c[r] != c[0]:
                raise Error(
                    lang + "/" + names[i] + ": checksum varies across runs"
                )
        # sort the three times
        for a in range(1, len(t)):
            var j = a
            while j > 0 and t[j - 1] > t[j]:
                var tmp = t[j - 1]
                t[j - 1] = t[j]
                t[j] = tmp
                j -= 1
        var lo = t[0]
        var hi = t[len(t) - 1]
        if lo > 0 and (UInt64(hi - lo) * 100) / UInt64(lo) >= 2:
            raise Error(
                lang + "/" + names[i] + ": run spread exceeds 2% ("
                + String(Int(lo)) + ".." + String(Int(hi)) + " µs)"
            )
        med.append(t[len(t) // 2])
        cks.append(c[0])
    return (med^, cks^)


def text_size(elf: String) raises -> Int:
    var out = buildmod.sh(
        String("arm-none-eabi-size ") + elf + " | awk 'NR==2{print $1}'"
    )
    return Int(String(out.strip()))


def main() raises:
    print("building Mojo benchmark...")
    var elf_mojo = buildmod.build("bench/bench.mojo", "bench_mojo", False)
    print("building C benchmark (gcc -O2)...")
    var elf_gcc = build_c("gcc")
    print("building C benchmark (clang -O2)...")
    var elf_clang = build_c("clang")
    print("building Rust benchmark (opt-level=2)...")
    var elf_rust = build_rust()

    print("running Mojo benchmark on target (3 runs)...")
    var m = reduce_runs(String("mojo"), run_bench(elf_mojo))
    print("running C (gcc) benchmark on target (3 runs)...")
    var g = reduce_runs(String("c_gcc"), run_bench(elf_gcc))
    print("running C (clang) benchmark on target (3 runs)...")
    var cl = reduce_runs(String("c_clang"), run_bench(elf_clang))
    print("running Rust benchmark on target (3 runs)...")
    var ru = reduce_runs(String("rust"), run_bench(elf_rust))

    var descs = _descs()
    var names = _names()

    # cross-language checksum agreement
    for i in range(COUNT):
        if (
            m[1][i] != cl[1][i]
            or g[1][i] != cl[1][i]
            or ru[1][i] != cl[1][i]
        ):
            raise Error(names[i] + ": checksum mismatch across languages")

    print()
    print(
        _lj(String("benchmark"), 38) + _rj(String("Mojo µs"), 10)
        + _rj(String("gcc µs"), 10) + _rj(String("clang µs"), 10)
        + _rj(String("Rust µs"), 10) + _rj(String("Mojo/clang"), 12)
    )
    for i in range(COUNT):
        print(
            _lj(descs[i], 38)
            + _rj(String(Int(m[0][i])), 10)
            + _rj(String(Int(g[0][i])), 10)
            + _rj(String(Int(cl[0][i])), 10)
            + _rj(String(Int(ru[0][i])), 10)
            + _rj(_ratio2(m[0][i], cl[0][i]), 12)
        )
    print("checksums: all runs and all languages agree")

    var s_mojo = text_size(elf_mojo)
    var s_gcc = text_size(elf_gcc)
    var s_clang = text_size(elf_clang)
    var s_rust = text_size(elf_rust)
    print()
    print(
        ".text sizes: Mojo " + String(s_mojo) + " B, gcc " + String(s_gcc)
        + " B, clang " + String(s_clang) + " B, Rust " + String(s_rust)
        + " B"
    )

    var csv = String("workload,description,mojo_us,c_gcc_us,c_clang_us,rust_us\n")
    for i in range(COUNT):
        csv += (
            names[i] + "," + descs[i] + ","
            + String(Int(m[0][i])) + "," + String(Int(g[0][i])) + ","
            + String(Int(cl[0][i])) + "," + String(Int(ru[0][i])) + "\n"
        )
    var f = open("build/bench_results.csv", "w")
    f.write(csv)
    f.close()
    var sizes = String("firmware,text_bytes\n")
    sizes += String("bench_mojo,") + String(s_mojo) + "\n"
    sizes += String("bench_c_gcc,") + String(s_gcc) + "\n"
    sizes += String("bench_c_clang,") + String(s_clang) + "\n"
    sizes += String("bench_rust,") + String(s_rust) + "\n"
    var f2 = open("build/bench_sizes.csv", "w")
    f2.write(sizes)
    f2.close()
    print("wrote build/bench_results.csv and build/bench_sizes.csv")
