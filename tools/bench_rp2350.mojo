"""Build, flash and time the four RP2350 benchmark firmwares (Pico 2).

Same shape as tools/bench.mojo (RP2040) with the Pico 2 realities:

  - every language targets rv32imac (Hazard3's ISA: hardware mul/div);
    Mojo emits riscv32 natively (--target-features=+m,+a,+c), C builds
    via riscv gcc -O2 and clang -O2, Rust via riscv32imac target. All
    share crt0_rv32.S, rp2350_image_def.S, link_rv32.ld, ld.lld and the
    rv32imac libgcc.
  - timing is the Hazard3 mcycle CSR (shared read_mcycle symbol), so
    results are CPU cycles — immune to ROSC frequency drift and
    comparable across languages to the cycle.
  - no probe and no button: firmware commits results to the flash
    mailbox (sector 0x3FF000) and reboots to BOOTSEL; the host flashes
    by UF2 copy and reads results over PICOBOOT (tools/picoboot_read.py).
    Each firmware stamps a language id so a stale page can never
    masquerade as a fresh result.

Host verification (same gates as RP2040): checksums identical across
runs and across all four languages; per-workload run spread < 2%.

Usage: pixi run bench-rp2350   (Pico 2 in BOOTSEL, clang + rustc)
"""

from std.subprocess import run
from std.time import sleep

import build as buildmod

comptime COUNT = 9
comptime RUNS = 3
comptime MAGIC: UInt32 = 0x42454E43  # "BENC"
comptime MB_XIP = "0x103ff000"  # flash mailbox, XIP address
comptime MOUNT = "/media/hundo/RP2350"
comptime HDR = 5  # magic, state, count, runs, lang


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
    d.append(String("50k u32 divisions (hardware M)"))
    d.append(String("20k float32 mul-adds (soft-float)"))
    d.append(String("100k noinline function calls"))
    # keep these comma-free: they go into the csv unquoted
    d.append(String("CRC-32 over 4 KB x4 (bitwise)"))
    d.append(String("quicksort 512 u32 x20"))
    d.append(String("16x16 u32 matmul x50 (hardware M)"))
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


comptime MARCH = "-march=rv32imac -mabi=ilp32"


def _libgcc() raises -> String:
    var p = buildmod.sh(
        String("riscv64-unknown-elf-gcc ") + MARCH
        + " -print-libgcc-file-name"
    )
    return String(p.strip())


def _shared_objs() raises:
    # -mno-relax: linker relaxation breaks hand-alignment in crt0_rv32.S
    # (mtvec target must stay 4-aligned — low bits are the MODE field)
    var cc = (
        String("clang --target=riscv32-unknown-none-elf ")
        + MARCH + " -mno-relax -c "
    )
    _ = buildmod.sh(cc + "runtime/crt0_rv32.S -o build/crt0_rv32.o")
    _ = buildmod.sh(cc + "runtime/rp2350_image_def.S -o build/rp2350_image_def.o")


def _link(obj: String, elf: String) raises:
    _ = buildmod.sh(
        String("ld.lld -m elf32lriscv -T runtime/link_rv32.ld")
        + " build/rp2350_image_def.o build/crt0_rv32.o "
        + obj + " " + _libgcc() + " -o " + elf
    )


def build_mojo() raises -> String:
    var elf = String("build/bench2_mojo.elf")
    var prefix = buildmod.toolchain_prefix()
    _ = buildmod.shx(
        prefix + "/bin/mojo build --emit=object"
        + " --target-triple=riscv32-unknown-none-elf"
        + " --target-features=+m,+a,+c"
        + " -I " + prefix + "/lib/mojo -I src"
        + " -o build/bench2_mojo.o bench/bench_rp2350.mojo"
    )
    _link(String("build/bench2_mojo.o"), elf)
    return elf^


def build_c(cc: String) raises -> String:
    var obj = String("build/bench2_") + cc + ".o"
    var elf = String("build/bench2_") + cc + ".elf"
    if cc == "gcc":
        _ = buildmod.shx(
            String("riscv64-unknown-elf-gcc ") + MARCH
            + " -O2 -ffreestanding -c bench/bench_rp2350.c -o " + obj
        )
    else:
        _ = buildmod.shx(
            String("clang --target=riscv32-unknown-none-elf ") + MARCH
            + " -O2 -ffreestanding -c bench/bench_rp2350.c -o " + obj
        )
    _link(obj, elf)
    return elf^


def build_rust() raises -> String:
    var lib = String("build/libbench2_rust.a")
    var elf = String("build/bench2_rust.elf")
    _ = buildmod.shx(
        "rustc --edition 2021 --target riscv32imac-unknown-none-elf"
        + " --crate-type staticlib -C opt-level=2 -C codegen-units=1"
        + " -C panic=abort -o " + lib + " bench/bench_rp2350.rs"
    )
    _link(lib, elf)
    return elf^


def _mounted() raises -> Bool:
    var out = buildmod.sh(
        String("test -d ") + MOUNT + " && echo Y || echo N"
    )
    return String(out.strip()) == "Y"


def run_bench(elf: String, lang_id: UInt32, lang: String) raises -> List[UInt32]:
    """UF2-flash, wait for the self-reboot, read the flash mailbox."""
    _ = buildmod.sh(
        String("picotool uf2 convert ") + elf
        + " /tmp/bench2.uf2 --family rp2350-riscv"
    )
    var waited = 0
    while not _mounted():  # BOOTSEL drive appears (automount)
        waited += 1
        if waited > 30:
            raise Error("no BOOTSEL drive at " + MOUNT + " after 60 s")
        sleep(2.0)
    _ = buildmod.sh(String("cp /tmp/bench2.uf2 ") + MOUNT + "/")
    _ = buildmod.sh("sync 2>/dev/null || true")
    # the device drops off USB to run the suite, then reboots to BOOTSEL
    var gone = False
    for _ in range(30):
        sleep(2.0)
        if not _mounted():
            gone = True
            break
    if not gone:
        raise Error(lang + ": device never left BOOTSEL (UF2 not consumed?)")
    for _ in range(60):
        if _mounted():
            break
        sleep(2.0)
    if not _mounted():
        raise Error(lang + ": device never returned to BOOTSEL (firmware hung?)")
    sleep(1.0)
    var words = HDR + RUNS * COUNT * 2
    var out = buildmod.sh(
        String("python3 tools/picoboot_read.py ") + MB_XIP + " "
        + String(words) + " --dec"
    )
    var flat = List[UInt32]()
    for piece in String(out.strip()).split(" "):
        flat.append(UInt32(Int(String(piece))))
    if flat[0] != MAGIC:
        raise Error(lang + ": bad mailbox magic")
    if flat[1] != 2:
        raise Error(lang + ": firmware did not reach done state")
    if flat[2] != COUNT or flat[3] != RUNS:
        raise Error(lang + ": count/runs mismatch — stale firmware?")
    if flat[4] != lang_id:
        raise Error(lang + ": mailbox written by lang " + String(Int(flat[4])))
    var body = List[UInt32]()
    for i in range(RUNS * COUNT * 2):
        body.append(flat[HDR + i])
    return body^


def reduce_runs(
    lang: String, flat: List[UInt32]
) raises -> Tuple[List[UInt32], List[UInt32]]:
    """Median cycles and checksum per workload; assert determinism."""
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
                + String(Int(lo)) + ".." + String(Int(hi)) + " cycles)"
            )
        med.append(t[len(t) // 2])
        cks.append(c[0])
    return (med^, cks^)


def text_size(elf: String) raises -> Int:
    var out = buildmod.sh(
        String("llvm-size ") + elf + " | awk 'NR==2{print $1}'"
    )
    return Int(String(out.strip()))


def main() raises:
    print("assembling shared startup (rv32imac)...")
    _shared_objs()
    print("building Mojo benchmark...")
    var elf_mojo = build_mojo()
    print("building C benchmark (riscv gcc -O2)...")
    var elf_gcc = build_c(String("gcc"))
    print("building C benchmark (clang -O2)...")
    var elf_clang = build_c(String("clang"))
    print("building Rust benchmark (opt-level=2)...")
    var elf_rust = build_rust()

    print("running Mojo benchmark on target (3 runs)...")
    var m = reduce_runs(String("mojo"), run_bench(elf_mojo, 1, String("mojo")))
    print("running C (gcc) benchmark on target (3 runs)...")
    var g = reduce_runs(String("c_gcc"), run_bench(elf_gcc, 2, String("c_gcc")))
    print("running C (clang) benchmark on target (3 runs)...")
    var cl = reduce_runs(
        String("c_clang"), run_bench(elf_clang, 3, String("c_clang"))
    )
    print("running Rust benchmark on target (3 runs)...")
    var ru = reduce_runs(String("rust"), run_bench(elf_rust, 4, String("rust")))

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
        _lj(String("benchmark (cycles, rv32imac)"), 38)
        + _rj(String("Mojo"), 10)
        + _rj(String("gcc"), 10) + _rj(String("clang"), 10)
        + _rj(String("Rust"), 10) + _rj(String("Mojo/clang"), 12)
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

    var csv = String(
        "workload,description,mojo_cycles,c_gcc_cycles,c_clang_cycles,rust_cycles\n"
    )
    for i in range(COUNT):
        csv += (
            names[i] + "," + descs[i] + ","
            + String(Int(m[0][i])) + "," + String(Int(g[0][i])) + ","
            + String(Int(cl[0][i])) + "," + String(Int(ru[0][i])) + "\n"
        )
    var f = open("build/bench_rp2350_results.csv", "w")
    f.write(csv)
    f.close()
    print("wrote build/bench_rp2350_results.csv")
