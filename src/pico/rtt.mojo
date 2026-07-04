"""RTT (Real-Time Transfer) logging over the debug probe.

Implements the SEGGER RTT control-block layout with one up (target ->
host) channel, so any RTT-aware host tool can stream logs over SWD with
no UART wiring:

    probe-rs attach --chip RP2040 build/firmware.elf   # prints RTT output

The control block lives at a fixed RAM address (RTT_BASE) so the HIL
test can also read it back directly. The "SEGGER RTT" magic is written
last and composed from integers, so the only valid-looking block a host
scan can find is a fully initialized one.

Overflow policy: drop (never block) — logging must not change timing.

    import pico.rtt as rtt

    rtt.init()
    rtt.write("boot\\n")
    rtt.write_u32(42)
    rtt.write("\\n")
"""

from pico.mmio import read32, write32, write8

comptime RTT_BASE: UInt32 = 0x2003_8000
# control block: id[16] | MaxNumUpBuffers | MaxNumDownBuffers | up[0]{6}
comptime _MAX_UP: UInt32 = RTT_BASE + 16
comptime _MAX_DOWN: UInt32 = RTT_BASE + 20
comptime _UP_NAME: UInt32 = RTT_BASE + 24
comptime _UP_BUF: UInt32 = RTT_BASE + 28
comptime _UP_SIZE: UInt32 = RTT_BASE + 32
comptime _UP_WROFF: UInt32 = RTT_BASE + 36
comptime _UP_RDOFF: UInt32 = RTT_BASE + 40
comptime _UP_FLAGS: UInt32 = RTT_BASE + 44

comptime BUF: UInt32 = RTT_BASE + 64
comptime BUF_SIZE: UInt32 = 1024


def init():
    """Set up the control block (call once, after pico.init())."""
    write32(_MAX_UP, 1)
    write32(_MAX_DOWN, 0)
    write32(_UP_NAME, 0)
    write32(_UP_BUF, BUF)
    write32(_UP_SIZE, BUF_SIZE)
    write32(_UP_WROFF, 0)
    write32(_UP_RDOFF, 0)
    write32(_UP_FLAGS, 0)  # 0 = skip when full: logging never blocks
    # magic last, so a host scan never sees a half-built block:
    # "SEGGER RTT\0\0\0\0\0\0" as little-endian words
    write32(RTT_BASE + 12, 0)
    write32(RTT_BASE + 8, 0x0000_5454)  # "TT\0\0"
    write32(RTT_BASE + 4, 0x5220_4552)  # "ER R"
    write32(RTT_BASE + 0, 0x4747_4553)  # "SEGG"


def _put(wr: UInt32, byte: UInt8) -> UInt32:
    """Store one byte at the ring position; returns the next position.
    The caller publishes WrOff once per message (RTT ordering rule:
    data first, then WrOff)."""
    write8(BUF + wr, byte)
    var next = wr + 1
    if next == BUF_SIZE:
        next = 0
    return next


def _room(wr: UInt32) -> UInt32:
    var rd = read32(_UP_RDOFF)
    if rd > wr:
        return rd - wr - 1
    return BUF_SIZE - 1 - wr + rd


def write(s: StaticString):
    """Append a string to the up channel (dropped whole if no room)."""
    var bytes = s.as_bytes()
    var wr = read32(_UP_WROFF)
    if UInt32(len(bytes)) > _room(wr):
        return
    for i in range(len(bytes)):
        wr = _put(wr, bytes[i])
    write32(_UP_WROFF, wr)


def write_u32(v: UInt32):
    """Append a decimal number."""
    var digits = InlineArray[UInt8, 10](fill=0)
    var n = v
    var count = 0
    while True:
        digits[count] = UInt8(48 + Int(n % 10))
        count += 1
        n //= 10
        if n == 0:
            break
    var wr = read32(_UP_WROFF)
    if UInt32(count) > _room(wr):
        return
    for i in range(count):
        wr = _put(wr, digits[count - 1 - i])
    write32(_UP_WROFF, wr)


def write_hex(v: UInt32):
    """Append `0x` + 8 hex digits."""
    var wr = read32(_UP_WROFF)
    if UInt32(10) > _room(wr):
        return
    wr = _put(wr, 48)  # '0'
    wr = _put(wr, 120)  # 'x'
    for i in range(8):
        var nib = Int((v >> UInt32((7 - i) * 4)) & 0xF)
        if nib < 10:
            wr = _put(wr, UInt8(48 + nib))
        else:
            wr = _put(wr, UInt8(87 + nib))  # 'a' - 10
    write32(_UP_WROFF, wr)
