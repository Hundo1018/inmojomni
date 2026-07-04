#!/usr/bin/env python3
"""pico-mojo test orchestrator: `pixi run test`.

Stages (later stages assume earlier ones passed):
  1. host-unit       IR downgrade pass + boot2 CRC (tests/host, Mojo)
  2. compile-fail    invalid Mojo (e.g. Pin[30]) must NOT compile
  3. build+static    build blink & on-target suite (tools/build.mojo),
                     verify ELFs (tools/check_elf.mojo), volatile ops
                     preserved through the IR pipeline
  4. hardware (HIL)  on-target Mojo suite via mailbox, timer rate,
                     LED blink observation  [skipped without a probe]

The product tooling under test (build/retarget/check_elf/bench) is Mojo;
this orchestrator and the DAP/SWD test rig (hil.py, dap_client.py)
deliberately stay Python — they are the measurement instrument, not the
product.

The board is always left running the blink demo.
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import hil  # noqa: E402

PREFIX = Path(os.environ.get("CONDA_PREFIX") or ROOT / ".pixi/envs/default")
MOJO = PREFIX / "bin" / "mojo"
MOJO_STDLIB = PREFIX / "lib" / "mojo"
TRIPLE_IR = "riscv32-unknown-none-elf"
BUILD = ROOT / "build"

RESULTS: list[tuple[str, list[str]]] = []


def stage(name: str, fails: list[str]):
    RESULTS.append((name, fails))
    mark = "PASS" if not fails else "FAIL"
    print(f"[{mark}] {name}")
    for f in fails:
        print(f"       ✗ {f}")


def mojo_tool(*args: str, capture: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(
        [str(MOJO), "run", "-I", "tools", "-I", "src", *args],
        cwd=ROOT, capture_output=capture, text=True,
    )


def run_host_unit() -> list[str]:
    fails = []
    for test in sorted((ROOT / "tests/host").glob("*.mojo")):
        res = mojo_tool(str(test.relative_to(ROOT)))
        if res.stdout.strip():
            print(res.stdout.rstrip())
        if res.returncode != 0:
            fails.append(f"{test.name}:\n" + res.stderr.strip()[-2000:])
    return fails


def run_compile_fail() -> list[str]:
    fails = []
    for src in sorted((ROOT / "tests/compile_fail").glob("*.mojo")):
        expect = ""
        for line in src.read_text().splitlines():
            if "EXPECT-ERROR:" in line:
                expect = line.split("EXPECT-ERROR:", 1)[1].strip()
        res = subprocess.run(
            [str(MOJO), "build", "--emit=llvm",
             f"--target-triple={TRIPLE_IR}",
             "-I", str(MOJO_STDLIB), "-I", str(ROOT / "src"),
             "-o", "/dev/null", str(src)],
            capture_output=True, text=True,
        )
        if res.returncode == 0:
            fails.append(f"{src.name}: compiled, but must be rejected")
        elif expect and expect not in res.stderr:
            fails.append(f"{src.name}: failed, but without expected message {expect!r}")
        else:
            print(f"  ✓ {src.name} correctly rejected ({expect!r})")
    return fails


def build_firmware(main: str, name: str, debug: bool = False) -> list[str]:
    args = ["tools/build.mojo", main, "--name", name]
    if debug:
        args.append("--debug")
    res = mojo_tool(*args, capture=False)
    if res.returncode != 0:
        return [f"{name}: build failed (exit {res.returncode})"]
    return []


def check_elf(name: str) -> list[str]:
    res = mojo_tool("tools/check_elf.mojo", f"build/{name}.elf")
    if res.stdout.strip():
        print(res.stdout.rstrip())
    if res.returncode != 0:
        tail = (res.stderr or res.stdout).strip()[-500:]
        return [f"{name}: ELF verification failed: {tail}"]
    return []


def volatile_preserved(name: str) -> list[str]:
    rv32 = (BUILD / f"{name}.rv32.ll").read_text().count("volatile")
    arm = (BUILD / f"{name}.ll").read_text().count("volatile")
    if rv32 != arm:
        return [f"{name}: volatile ops {rv32} -> {arm} through retarget (must be equal)"]
    print(f"  ✓ {name}: {arm} volatile ops preserved through retarget")
    return []


def run_build_static() -> list[str]:
    fails = []
    targets = [
        ("src/main.mojo", "firmware", False),
        ("tests/on_target/main.mojo", "test_on_target", False),
        ("src/main.mojo", "firmware-debug", True),
    ]
    for main, name, debug in targets:
        fails += build_firmware(main, name, debug)
        if fails:
            return fails  # later checks need the ELFs
        fails += check_elf(name)
        fails += volatile_preserved(name)
    fails += check_debug_lines(BUILD / "firmware-debug.elf")
    return fails


def check_debug_lines(dbg_elf: Path) -> list[str]:
    """The debug ELF must carry DWARF line tables for the Mojo sources."""
    res = subprocess.run(
        ["arm-none-eabi-objdump", "--dwarf=decodedline", str(dbg_elf)],
        capture_output=True, text=True,
    )
    if "main.mojo" not in res.stdout:
        return ["firmware-debug.elf has no DWARF line info for main.mojo"]
    print("  ✓ firmware-debug.elf: DWARF line tables map back to .mojo sources")
    return []


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-hw", action="store_true", help="skip hardware-in-the-loop stages")
    args = ap.parse_args()

    print("=== 1. host unit tests ===")
    stage("host-unit", run_host_unit())

    print("=== 2. compile-fail tests ===")
    stage("compile-fail", run_compile_fail())

    print("=== 3. build + static verification ===")
    build_fails = run_build_static()
    stage("build+static", build_fails)

    if args.no_hw:
        print("=== 4. hardware: skipped (--no-hw) ===")
    elif not hil.probe_present():
        print("=== 4. hardware: skipped (no debug probe found) ===")
    elif build_fails:
        print("=== 4. hardware: skipped (build stage failed) ===")
    else:
        print("=== 4. hardware-in-the-loop ===")
        stage("hw-mailbox-suite", hil.run_mailbox_suite(BUILD / "test_on_target.elf"))
        stage("hw-rtt", hil.check_rtt())
        stage("hw-timer-rate", hil.check_timer_rate())
        stage("hw-dap-debug", hil.check_debug_experience(BUILD / "firmware-debug.elf"))
        stage("hw-blink", hil.observe_blink(BUILD / "firmware.elf"))
        print("(board left running the blink demo)")

    print("\n=== summary ===")
    bad = 0
    for name, fails in RESULTS:
        print(f"  {'PASS' if not fails else 'FAIL'}  {name}")
        bad += bool(fails)
    if bad:
        sys.exit(f"{bad} stage(s) failed")
    print("all green ✓")


if __name__ == "__main__":
    main()
