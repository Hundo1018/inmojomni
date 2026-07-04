"""Hardware helpers for Mojo host tools: drive the RP2040 over SWD via
the probe-rs CLI (download / reset / memory read).

The Python test rig (tools/hil.py) keeps its own copy of these two
primitives for the DAP-based test stages; this module is what the
product tooling (build --flash, bench) uses.
"""

from std.subprocess import run

comptime CHIP = "RP2040"


def _sh(cmd: String) raises -> String:
    """Quiet shell helper: capture stdout, discard stderr (probe-rs
    writes progress/udev warnings there), raise on nonzero exit."""
    var out = run(cmd + " 2>/dev/null; echo __RC$?")
    var idx = -1
    var searched = 0
    while True:
        var next = out.find("__RC", searched)
        if next == -1:
            break
        idx = next
        searched = next + 1
    var rc = String(out[byte = idx + 4 : out.byte_length()])
    if rc != "0":
        raise Error("command failed (exit " + rc + "): " + cmd)
    return String(out[byte=0:idx])


def probe_present() -> Bool:
    try:
        var out = _sh("probe-rs list")
        return out.find("debug probes were found") != -1
    except:
        return False


def flash(elf: String) raises:
    # 1 MHz SWD + one retry: the default speed proved marginal on this
    # wiring during sustained flash writes.
    var cmd = String("probe-rs download --chip ") + CHIP
    cmd += " --speed 1000 --verify " + elf
    try:
        _ = _sh(cmd)
    except:
        _ = _sh(cmd)
    _ = _sh(String("probe-rs reset --chip ") + CHIP)


def read_words(addr: UInt32, count: Int) raises -> List[UInt32]:
    var out = _sh(
        String("probe-rs read --chip ") + CHIP + " b32 "
        + hex(Int(addr)) + " " + String(count)
    )
    var words = List[UInt32]()
    for tok_s in out.split():
        var tok = String(tok_s)
        if tok.byte_length() == 0 or tok.byte_length() > 8:
            continue
        var v: UInt32 = 0
        var ok = True
        var b = tok.as_bytes()
        for i in range(len(b)):
            var c = b[i]
            var d: UInt32
            if c >= UInt8(ord("0")) and c <= UInt8(ord("9")):
                d = UInt32(c - UInt8(ord("0")))
            elif c >= UInt8(ord("a")) and c <= UInt8(ord("f")):
                d = UInt32(c - UInt8(ord("a"))) + 10
            elif c >= UInt8(ord("A")) and c <= UInt8(ord("F")):
                d = UInt32(c - UInt8(ord("A"))) + 10
            else:
                ok = False
                break
            v = (v << 4) | d
        if ok:
            words.append(v)
    if len(words) != count:
        raise Error(
            "probe-rs read returned " + String(len(words))
            + " words, expected " + String(count)
        )
    return words^
