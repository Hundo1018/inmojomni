"""Automated RP2350 RISC-V debug gate — the Pico 2 counterpart of the
RP2040 hw-dap-debug stage.

Exercises the real debug stack end to end, exactly as VS Code F5 uses it
(raspberrypi/openocd fork -> Hazard3 Debug Module at AP 0xa000 -> gdb):

  1. flash the current blink over SWD (program + verify + reset; the
     firmware keeps running — no BOOTSEL button anywhere)
  2. attach, reset-halt, set a HARDWARE breakpoint on mojo_main
  3. continue -> the breakpoint must hit inside mojo_main
  4. single-step -> the PC must advance
  5. read memory (flash word 0 == the PICOBIN block marker 0xffffded3)
  6. read registers/CSRs (sp inside core 0's 4 KiB stack below
     _stack_top 0x20082000; misa == 0x40901105, i.e. rv32imac)
  7. SOURCE-level: a hardware breakpoint on the .mojo line of
     `led.toggle()` must hit twice in a row (two blink iterations)

Requires: the raspberrypi/openocd fork (see README), gdb-multiarch, a
CMSIS-DAP probe wired to the Pico 2, board free to reset.

Usage: pixi run debug-test-rp2350
"""

import build as buildmod

comptime STACK_TOP: UInt32 = 0x2008_2000
comptime MISA: UInt32 = 0x4090_1105
comptime IMAGE_DEF_W0 = "0xffffded3"


def _gdb_batch(elf: String, src_line: String) raises -> String:
    var cmd = String("timeout 60 gdb-multiarch ") + elf + " -batch"
    cmd += " -ex 'set confirm off'"
    cmd += " -ex 'target extended-remote :3333'"
    cmd += " -ex 'monitor reset halt'"
    cmd += " -ex 'hbreak mojo_main'"
    cmd += " -ex 'continue'"
    cmd += ' -ex \'printf "GATE_BP: 0x%08x\\n", $pc\''
    cmd += " -ex 'stepi'"
    cmd += ' -ex \'printf "GATE_STEP: 0x%08x\\n", $pc\''
    cmd += ' -ex \'printf "GATE_SP: 0x%08x\\n", $sp\''
    cmd += ' -ex \'printf "GATE_MISA: 0x%08x\\n", $misa\''
    cmd += ' -ex \'printf "GATE_MEM: 0x%08x\\n", *(unsigned int*)0x10000000\''
    cmd += " -ex 'delete'"
    cmd += " -ex 'hbreak src/main_rp2350.mojo:" + src_line + "'"
    cmd += " -ex 'continue'"
    cmd += ' -ex \'printf "GATE_SRC: 0x%08x\\n", $pc\''
    cmd += " -ex 'continue'"
    cmd += ' -ex \'printf "GATE_SRC2: 0x%08x\\n", $pc\''
    cmd += " -ex 'delete' -ex 'detach' 2>&1"
    return buildmod.sh(cmd)


def _hex(h: String) raises -> UInt32:
    """Parse a lowercase hex string (with or without 0x)."""
    var v: UInt32 = 0
    var body = h
    if body.startswith("0x"):
        body = String(body[byte=2:])
    for b in body.codepoints():
        var d = Int(b.to_u32())
        if 48 <= d and d <= 57:
            v = v * 16 + UInt32(d - 48)
        elif 97 <= d and d <= 102:
            v = v * 16 + UInt32(d - 87)
        else:
            raise Error("bad hex digit in: " + h)
    return v


def _field(out_text: String, tag: String) raises -> UInt32:
    for line_s in out_text.split("\n"):
        var line = String(line_s)
        if line.startswith(tag):
            return _hex(String(line.split(" ")[1].strip()))
    raise Error("gdb output missing " + tag)


def main() raises:
    print("[0/3] build debug blink (mojo -g, no optimization)...")
    var elf = buildmod.build_rv32(
        String("src/main_rp2350.mojo"), String("main_rp2350_debug"), True
    )
    var oocd = buildmod.openocd_rp2350()

    print("[1/3] flash over SWD (program + verify + reset)...")
    _ = buildmod.shx(
        oocd + " -f interface/cmsis-dap.cfg"
        + ' -c "adapter speed 1000" -f target/rp2350-riscv.cfg'
        + ' -c "program ' + elf + ' verify reset exit" 2>&1 | tail -1'
    )

    print("[2/3] start gdb server...")
    _ = buildmod.sh(
        oocd + " -f interface/cmsis-dap.cfg"
        + ' -c "adapter speed 1000" -f target/rp2350-riscv.cfg'
        + " > /tmp/oocd_gate.log 2>&1 & echo $! > /tmp/oocd_gate.pid"
    )
    _ = buildmod.sh("sleep 3")
    var ready = buildmod.sh("grep -c 'Listening on port 3333' /tmp/oocd_gate.log || true")

    print("[3/3] gdb: reset, hw breakpoint, step, memory, CSRs...")
    var out = String("")
    var fail = String("")
    if String(ready.strip()) == "0":
        fail = "openocd never opened port 3333"
    else:
        var mm = buildmod.sh(
            String("llvm-nm ") + elf + " | awk '/ mojo_main$/{print $1}'"
        )
        var tl = buildmod.sh(
            "grep -n 'led.toggle()' src/main_rp2350.mojo | cut -d: -f1"
        )
        out = _gdb_batch(elf, String(tl.strip()))
        var bp = _field(out, String("GATE_BP:"))
        var st = _field(out, String("GATE_STEP:"))
        var sp = _field(out, String("GATE_SP:"))
        var misa = _field(out, String("GATE_MISA:"))
        var mem = _field(out, String("GATE_MEM:"))
        var mm_addr = _hex(String(mm.strip()))
        if bp < mm_addr or bp > mm_addr + 0x20:
            fail = "hw breakpoint did not hit inside mojo_main"
        elif st == bp:
            fail = "single-step did not advance the PC"
        elif sp > STACK_TOP or sp <= STACK_TOP - 0x1000:
            # gdb lands after the prologue, so the frame is already
            # allocated; sp must simply be inside core 0's 4 KiB stack.
            fail = "sp at mojo_main not within core 0 stack"
        elif misa != MISA:
            fail = "misa mismatch (not rv32imac?)"
        elif mem != _hex(String(IMAGE_DEF_W0)):
            fail = "flash word 0 != PICOBIN marker"
        elif _field(out, String("GATE_SRC:")) != _field(
            out, String("GATE_SRC2:")
        ):
            fail = "source-line hw breakpoint did not hit twice at one line"
        else:
            print("  bp hit @", String(Int(bp)), " step ->", String(Int(st)))

    _ = buildmod.sh("kill $(cat /tmp/oocd_gate.pid) 2>/dev/null || true")
    print("=== summary ===")
    if fail != "":
        print("  FAIL  rp2350-debug:", fail)
        raise Error(fail)
    print("  PASS  rp2350-debug (flash/verify, reset, hbreak, step, mem, CSR, .mojo source line)")
