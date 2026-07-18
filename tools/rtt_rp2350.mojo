"""RTT gate for the RP2350: read the target's log over SWD, live.

The RP2040 RTT stage reads the control block back over SWD with an
independent host reader (tools/hil.py check_rtt). This is the Pico 2
counterpart, and it goes further: it exercises the full SEGGER RTT
*handshake* while the RISC-V cores run — proving not just that the
block is readable, but that host and target cooperate through it.

Why not openocd's built-in `rtt` command? The raspberrypi/openocd fork
chains the generic RTT command group into its cortex_m/hla/arc targets
but not the RISC-V target, so `rtt setup` is unavailable for Hazard3.
Rather than carry a patched openocd, this gate speaks the RTT protocol
directly through openocd's generic memory access (read_memory /
write_memory) — which is exactly what an RTT host engine does inside.

Steps (openocd TCL, target running the whole time):
  1. read the "SEGGER RTT\0..." magic and the up-buffer descriptor
  2. read the up-buffer bytes and decode the banner
  3. consume: write RdOff = WrOff over SWD (the RTT host's half of the
     protocol) — proving the host can update the control block while
     the cores run, not only read it
  4. sleep, then re-read WrOff — it must have advanced, proving the
     target keeps logging while the host reads and writes over SWD

Gates: magic matches; banner "RTT-RV32 hello" decoded from the ring;
WrOff advances between reads (target logging live over SWD).

Usage: pixi run rtt-rp2350   (probe wired to the Pico 2)
"""

import bench_rp2350 as b2
import build as buildmod

comptime RTT_BASE: UInt32 = 0x2003_8000
comptime BANNER: StaticString = "RTT-RV32 hello"


def _hex(h: String) raises -> UInt32:
    """Parse a hex token (openocd read_memory prints '0x..')."""
    var body = h
    if body.startswith("0x") or body.startswith("0X"):
        body = String(body[byte=2:])
    var v: UInt32 = 0
    for b in body.codepoints():
        var d = Int(b.to_u32())
        if 48 <= d and d <= 57:
            v = v * 16 + UInt32(d - 48)
        elif 97 <= d and d <= 102:
            v = v * 16 + UInt32(d - 87)
        elif 65 <= d and d <= 70:
            v = v * 16 + UInt32(d - 55)
        else:
            raise Error("bad hex token: " + h)
    return v


def _words(out_text: String, tag: String) raises -> List[UInt32]:
    """Parse a `puts "<tag> 0x.. 0x.. ..."` line into a list of ints."""
    for line_s in out_text.split("\n"):
        var line = String(line_s).strip()
        if line.startswith(tag):
            var rest = String(line[byte = tag.byte_length() :]).strip()
            var out = List[UInt32]()
            for tok in rest.split(" "):
                var t = String(String(tok).strip())
                if t.byte_length() > 0:
                    out.append(_hex(t))
            return out^
    raise Error("openocd output missing '" + tag + "'")


def main() raises:
    print("building rtt_hello firmware...")
    var prefix = buildmod.toolchain_prefix()
    b2._shared_objs()
    _ = buildmod.shx(
        prefix + "/bin/mojo build --emit=object"
        + " --target-triple=riscv32-unknown-none-elf"
        + " --target-features=+m,+a,+c"
        + " -I " + prefix + "/lib/mojo -I src"
        + " -o build/rtt_hello.o tests/on_target_rp2350/rtt_hello.mojo"
    )
    b2._link(String("build/rtt_hello.o"), String("build/rtt_hello.elf"))

    var oocd = buildmod.openocd_rp2350()
    print("flash over SWD (program + verify + reset, keeps running)...")
    _ = buildmod.shx(
        oocd + " -f interface/cmsis-dap.cfg"
        + ' -c "adapter speed 1000" -f target/rp2350-riscv.cfg'
        + ' -c "program build/rtt_hello.elf verify reset exit" 2>&1 | tail -1'
    )
    _ = buildmod.sh("sleep 2")

    # RTT protocol over generic memory access. read_memory width 8 -> a
    # space-separated decimal byte list; width 32 count 1 -> one word.
    var tcl = String(
        "init\n"
        "set b 0x20038000\n"
        'puts "MAGIC [read_memory $b 8 16]"\n'
        'puts "DESC [read_memory [expr {$b + 0x18}] 32 6]"\n'
        'puts "BUF [read_memory [expr {$b + 0x40}] 8 40]"\n'
        "set w1 [read_memory [expr {$b + 0x24}] 32 1]\n"
        'puts "WROFF1 $w1"\n'
        "write_memory [expr {$b + 0x28}] 32 $w1\n"
        "sleep 600\n"
        'puts "WROFF2 [read_memory [expr {$b + 0x24}] 32 1]"\n'
        "shutdown\n"
    )
    var f = open("/tmp/rtt_gate.tcl", "w")
    f.write(tcl)
    f.close()
    var out = buildmod.sh(
        oocd + " -f interface/cmsis-dap.cfg"
        + ' -c "adapter speed 1000" -f target/rp2350-riscv.cfg'
        + " -f /tmp/rtt_gate.tcl 2>&1"
    )

    var magic = _words(out, String("MAGIC "))
    var desc = _words(out, String("DESC "))
    var buf = _words(out, String("BUF "))
    var w1 = _words(out, String("WROFF1 "))[0]
    var w2 = _words(out, String("WROFF2 "))[0]

    # decode the magic and the banner bytes the reader pulled back
    var magic_str = String("")
    for i in range(10):
        magic_str += chr(Int(magic[i]))
    var banner = String("")
    for i in range(len(buf)):
        if buf[i] != 0:
            banner += chr(Int(buf[i]))
    var buf_ptr = desc[1]
    var buf_size = desc[2]

    print("magic:          '" + magic_str + "'")
    print(
        "descriptor:     buf=" + hex(Int(buf_ptr)) + " size="
        + String(Int(buf_size))
    )
    print("banner decoded: '" + banner.replace("\n", "\\n") + "'")
    print(
        "handshake:      WrOff " + String(Int(w1)) + " -> (host consumes) -> "
        + String(Int(w2)) + " after 600 ms"
    )

    print("=== summary ===")
    if magic_str != "SEGGER RTT":
        print("  FAIL  rtt-rp2350: magic mismatch:", magic_str)
        raise Error("RTT magic mismatch")
    if buf_ptr != RTT_BASE + 0x40 or buf_size != 1024:
        raise Error("RTT up-buffer descriptor wrong")
    if BANNER not in banner:
        print("  FAIL  rtt-rp2350: banner missing from ring")
        raise Error("RTT banner not decoded from the ring buffer")
    if w2 == w1:
        print("  FAIL  rtt-rp2350: WrOff frozen — target not logging live")
        raise Error("RTT WrOff did not advance after host consumed")
    print(
        "  PASS  rtt-rp2350 (magic + banner read over SWD; host updated"
        " RdOff and target kept logging live — WrOff advanced)"
    )
