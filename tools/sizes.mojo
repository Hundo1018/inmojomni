"""Fair binary-size comparison: the same minimal blink in all four
languages, on the identical rig (crt0.S, link.ld, boot2, clock init).

No hardware needed — this only builds and measures. Results go to the
console and build/blink_sizes.csv.

Usage: pixi run sizes   (needs arm-none-eabi-gcc, clang, rustc)
"""

import build as buildmod


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


def text_size(elf: String) raises -> Int:
    var out = buildmod.sh(
        String("arm-none-eabi-size ") + elf + " | awk 'NR==2{print $1}'"
    )
    return Int(String(out.strip()))


def main() raises:
    print("building blink (Mojo pipeline)...")
    var elf_mojo = buildmod.build("src/main.mojo", "firmware", False)

    print("building blink (gcc -O2)...")
    _ = buildmod.sh(
        "arm-none-eabi-gcc -mcpu=cortex-m0plus -mthumb -O2"
        + " -ffunction-sections -fdata-sections -c bench/blink.c"
        + " -o build/blink_gcc.o"
    )
    _link("build/blink_gcc.o", "build/blink_gcc.elf")

    print("building blink (clang -O2)...")
    _ = buildmod.sh(
        "clang --target=armv6m-none-eabi -mcpu=cortex-m0plus -O2"
        + " -ffreestanding -fshort-enums -ffunction-sections"
        + " -fdata-sections -c bench/blink.c -o build/blink_clang.o"
    )
    _link("build/blink_clang.o", "build/blink_clang.elf")

    print("building blink (Rust opt-level=2)...")
    _ = buildmod.sh(
        "rustc --edition 2021 --target thumbv6m-none-eabi"
        + " --crate-type staticlib -C opt-level=2 -C codegen-units=1"
        + " -C panic=abort -o build/libblink_rust.a bench/blink.rs"
    )
    _link("build/libblink_rust.a", "build/blink_rust.elf")

    var s_mojo = text_size(elf_mojo)
    var s_gcc = text_size("build/blink_gcc.elf")
    var s_clang = text_size("build/blink_clang.elf")
    var s_rust = text_size("build/blink_rust.elf")

    print()
    print("blink .text sizes (identical rig: crt0 + link.ld + boot2):")
    print("  Mojo     ", s_mojo, "B")
    print("  C (gcc)  ", s_gcc, "B")
    print("  C (clang)", s_clang, "B")
    print("  Rust     ", s_rust, "B")

    var csv = String("firmware,text_bytes\n")
    csv += String("blink_mojo,") + String(s_mojo) + "\n"
    csv += String("blink_c_gcc,") + String(s_gcc) + "\n"
    csv += String("blink_c_clang,") + String(s_clang) + "\n"
    csv += String("blink_rust,") + String(s_rust) + "\n"
    var f = open("build/blink_sizes.csv", "w")
    f.write(csv)
    f.close()
    print("wrote build/blink_sizes.csv")
