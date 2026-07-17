"""Build pipeline: Mojo source -> RP2040 firmware.

Mojo's bundled LLVM has no 32-bit ARM backend, so the pipeline is:

  1. mojo build --emit=llvm  targeting riscv32 (same ILP32, little-endian
     data model as ARMv6-M, so the generated IR is layout-compatible)
  2. retarget the IR module to thumbv6m-none-eabi (see retarget.mojo)
  3. opt -O2 + llc compile the IR for cortex-m0plus
  4. arm-none-eabi-gcc links it with crt0.S + link.ld (+ boot2)

The driver itself is a Mojo program; run it from the repo root:

  pixi run build                                # build/firmware.elf
  pixi run flash                                # build + flash (SWD)
  pixi run uf2                                  # build + firmware.uf2
  mojo run -I tools tools/build.mojo --debug    # debug firmware
"""

from std.os import getenv
from std.pathlib import Path
from std.subprocess import run
from std.sys import argv

from retarget import CPU, DATALAYOUT_MCU, TRIPLE_IR, TRIPLE_MCU, retarget_text
from boot2 import build_boot2


def sh(cmd: String) raises -> String:
    """Run `cmd` through the shell; raise on nonzero exit.

    Child stderr streams straight to the terminal; stdout is captured
    and returned (also printed when non-empty, so tool output such as
    `arm-none-eabi-size` stays visible)."""
    var out = run(cmd + "; echo __RC$?")
    var idx = -1
    var searched = 0
    while True:
        var next = out.find("__RC", searched)
        if next == -1:
            break
        idx = next
        searched = next + 1
    if idx == -1:
        raise Error("shell produced no status marker: " + cmd)
    var rc = String(out[byte = idx + 4 : out.byte_length()])
    var body = String(out[byte=0:idx])
    if body.endswith("\n"):
        body = String(body[byte = 0 : body.byte_length() - 1])
    if len(body.as_bytes()) > 0:
        print(body)
    if rc != "0":
        raise Error("command failed (exit " + rc + "): " + cmd)
    return body


def shx(cmd: String) raises -> String:
    """Like sh(), with the command echoed first (pipeline style)."""
    print("  $", cmd)
    return sh(cmd)


def toolchain_prefix() -> String:
    # Under `pixi run` CONDA_PREFIX already points at the repo's pixi
    # env; the fallback lets the tools work outside a pixi shell too.
    var p = getenv("CONDA_PREFIX")
    if p.byte_length() == 0:
        return ".pixi/envs/default"
    return p


def emit_ir(main_mojo: String, out_ll: String, debug: Bool) raises:
    var prefix = toolchain_prefix()
    var cmd = String(prefix) + "/bin/mojo build"
    if debug:
        # Full debug info. The newer-LLVM #dbg_ records this produces
        # are translated back to intrinsics by retarget_text(). Elaborator
        # optimization is off so call sites keep real call instructions:
        # that is what lets a debugger resolve `break main.mojo:20` on a
        # line whose callee would otherwise be fully inlined.
        cmd += " -g --no-optimization"
    cmd += (
        " --emit=llvm --target-triple="
        + TRIPLE_IR
        + " -I "
        + prefix
        + "/lib/mojo -I src -o "
        + out_ll
        + " "
        + main_mojo
    )
    _ = shx(cmd)


def retarget_file(src_ll: String, dst_ll: String) raises:
    var src = open(src_ll, "r").read()
    var f = open(dst_ll, "w")
    f.write(retarget_text(src))
    f.close()
    print(
        "  retargeted "
        + src_ll
        + " -> "
        + dst_ll
        + " ("
        + TRIPLE_MCU
        + ")"
    )


def build(main_mojo: String, name: String, debug: Bool) raises -> String:
    if not Path("runtime/link.ld").exists():
        raise Error("run from the repo root (runtime/link.ld not found)")
    _ = sh("mkdir -p build")
    var ir_rv32 = String("build/") + name + ".rv32.ll"
    var ir_arm = String("build/") + name + ".ll"
    var ir_opt = String("build/") + name + ".opt.bc"
    var fw_obj = String("build/") + name + ".o"
    var crt0_obj = String("build/crt0.o")
    var elf = String("build/") + name + ".elf"

    print("[1/4] Mojo -> LLVM IR" + (" (debug)" if debug else ""))
    emit_ir(main_mojo, ir_rv32, debug)

    print("[2/4] retarget IR to ARMv6-M")
    retarget_file(ir_rv32, ir_arm)

    print("[3/4] codegen for", CPU)
    var mcu_flags = (
        String(" -mtriple=") + TRIPLE_MCU + " -mcpu=" + CPU
        + " -function-sections -data-sections -filetype=obj "
    )
    if debug:
        # No IR-level optimization: keep source lines <-> code honest.
        _ = shx(
            String("llc -O1") + mcu_flags.replace(
                " -function", " -frame-pointer=all -function"
            ) + ir_arm + " -o " + fw_obj
        )
    else:
        _ = shx(String("opt -O2 ") + ir_arm + " -o " + ir_opt)
        _ = shx(String("llc -O2") + mcu_flags + ir_opt + " -o " + fw_obj)

    print("[4/4] boot2 from source + assemble crt0 + link")
    _ = build_boot2()
    var gcc = String("arm-none-eabi-gcc -mcpu=") + CPU + " -mthumb"
    _ = shx(gcc + " -c runtime/crt0.S -o " + crt0_obj)
    _ = shx(
        gcc
        + " -nostdlib -nostartfiles -T runtime/link.ld -Wl,--gc-sections"
        + " -Wl,-Map=build/"
        + name
        + ".map "
        + crt0_obj
        + " "
        + fw_obj
        + " -lgcc -o "
        + elf
    )
    _ = shx(String("arm-none-eabi-size ") + elf)
    return elf


def openocd_rp2350() raises -> String:
    """The RP2350-capable openocd binary. Ubuntu's openocd 0.12 has no
    rp2350 target files; the raspberrypi/openocd fork installed to
    ~/.local/bin is preferred, falling back to whatever is on PATH."""
    var probe = sh("test -x $HOME/.local/bin/openocd && echo yes || true")
    if String(probe.strip()) == "yes":
        return sh("echo -n $HOME/.local/bin/openocd")
    return String("openocd")


def build_rv32(main_mojo: String, name: String, debug: Bool) raises -> String:
    """RP2350 (Pico 2) native path.

    The Hazard3 cores are RISC-V, so Mojo emits riscv32 objects *directly*
    (its bundled LLVM has the RISC-V backend) — no `retarget.mojo`, no
    external `llc`, no IR rewriting. Contrast build() above, where the same
    riscv32 IR is textually retargeted to thumbv6m because Mojo has no ARM
    backend. See runtime/crt0_rv32.S, runtime/rp2350_image_def.S,
    runtime/link_rv32.ld.
    """
    if not Path("runtime/link_rv32.ld").exists():
        raise Error("run from the repo root (runtime/link_rv32.ld not found)")
    _ = sh("mkdir -p build")
    var prefix = toolchain_prefix()
    var obj = String("build/") + name + ".o"
    var crt0 = String("build/crt0_rv32.o")
    var imgdef = String("build/rp2350_image_def.o")
    var elf = String("build/") + name + ".elf"

    print("[1/3] Mojo -> riscv32 object (native, no retarget)")
    var mojo = String(prefix) + "/bin/mojo build --emit=object"
    if debug:
        mojo += " -g --no-optimization"
    mojo += (
        " --target-triple=riscv32-unknown-none-elf -I "
        + prefix
        + "/lib/mojo -I src -o "
        + obj
        + " "
        + main_mojo
    )
    _ = shx(mojo)

    print("[2/3] assemble RISC-V startup + RP2350 boot block")
    var cc = String("clang --target=riscv32-unknown-none-elf -march=rv32i -c ")
    _ = shx(cc + "runtime/crt0_rv32.S -o " + crt0)
    _ = shx(cc + "runtime/rp2350_image_def.S -o " + imgdef)

    print("[3/3] link (ld.lld -> riscv32 ELF)")
    _ = shx(
        String("ld.lld -m elf32lriscv -T runtime/link_rv32.ld ")
        + imgdef
        + " "
        + crt0
        + " "
        + obj
        + " --Map=build/"
        + name
        + ".map -o "
        + elf
    )
    _ = shx(String("llvm-size ") + elf)
    return elf


def main() raises:
    var flash = False
    var uf2 = False
    var debug = False
    var name = String()
    var chip = String("rp2040")
    var main_mojo = String()
    var args = argv()
    var i = 1
    while i < len(args):
        var a = String(args[i])
        if a == "--flash":
            flash = True
        elif a == "--uf2":
            uf2 = True
        elif a == "--debug":
            debug = True
        elif a == "--name":
            i += 1
            name = String(args[i])
        elif a == "--chip":
            i += 1
            chip = String(args[i])
        elif a.startswith("--"):
            raise Error("unknown option: " + a)
        else:
            main_mojo = a
        i += 1
    if main_mojo.byte_length() == 0:
        main_mojo = String(
            "src/main_rp2350.mojo"
        ) if chip == "rp2350" else String("src/main.mojo")
    if name.byte_length() == 0:
        name = String("firmware-debug") if debug else String("firmware")

    var elf: String
    if chip == "rp2350":
        elf = build_rv32(main_mojo, name, debug)
    elif chip == "rp2040":
        elf = build(main_mojo, name, debug)
    else:
        raise Error("unknown --chip: " + chip + " (want rp2040 or rp2350)")

    if uf2:
        var uf2_path = String("build/") + name + ".uf2"
        _ = shx(String("picotool uf2 convert ") + elf + " " + uf2_path)
        print("UF2 ready:", uf2_path)

    if flash:
        if chip == "rp2350":
            # probe-rs has no RISC-V RP2350 target (its RP235x target
            # drives the M33 APs, which fault while the cores run
            # RISC-V). The raspberrypi/openocd fork reaches the Hazard3
            # Debug Module at AP 0xa000 instead: flash + verify + reset
            # over SWD with the firmware running — no BOOTSEL button.
            # Hardware-verified 2026-07-17. Build the fork with
            # --enable-cmsis-dap-v2 and install to ~/.local (README).
            print("[flash] openocd (rp2350-riscv) -> program+verify+reset")
            _ = shx(
                openocd_rp2350()
                + " -f interface/cmsis-dap.cfg"
                + ' -c "adapter speed 1000"'
                + " -f target/rp2350-riscv.cfg"
                + ' -c "program ' + elf + ' verify reset exit"'
            )
        else:
            print("[flash] probe-rs -> RP2040")
            _ = shx(
                String("probe-rs download --chip RP2040 --verify ") + elf
            )
            _ = shx("probe-rs reset --chip RP2040")
        print("flashed + reset OK")
