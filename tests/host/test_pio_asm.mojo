"""Unit/regression tests for the PIO assembler (src/pico/pio.mojo).

The assembler is pure logic, so it runs on the host as-is; these tests
pin the instruction encodings (datasheet §3.4) so a refactor cannot
silently change emitted programs. Hardware behavior is covered by the
on-target suite; this file is about bit-exact encoding.

Run: mojo run -I tools -I src tests/host/test_pio_asm.mojo
"""

from pico.pio import Asm


def _ok(name: String):
    print("  ✓", name)


def _assert_eq(got: UInt16, want: UInt16, msg: String) raises:
    if got != want:
        raise Error(
            "assertion failed: " + msg + " (got 0x" + String(hex(Int(got)))
            + ", want 0x" + String(hex(Int(want))) + ")"
        )


def test_basic_encodings() raises:
    var a = Asm()
    a.set_pins(1)            # 0xE001
    a.set_pindirs(1)         # 0xE081
    a.set_x(29)              # 0xE03D
    a.set_y(7)               # 0xE047
    a.jmp(0)                 # 0x0000
    a.jmp_not_x(3)           # 0x0023
    a.jmp_x_dec(4, delay=2)  # 0x0244
    a.wait_gpio(1, 17)       # 0x2091
    a.out_pins(8)            # 0x6008
    a.pull_block()           # 0x80A0
    a.pull_noblock()         # 0x8080
    a.mov_pins_x()           # 0xA001
    a.nop()                  # 0xA042 (mov y, y)
    _assert_eq(a.code[0], 0xE001, "set_pins 1")
    _assert_eq(a.code[1], 0xE081, "set_pindirs 1")
    _assert_eq(a.code[2], 0xE03D, "set_x 29")
    _assert_eq(a.code[3], 0xE047, "set_y 7")
    _assert_eq(a.code[4], 0x0000, "jmp 0")
    _assert_eq(a.code[5], 0x0023, "jmp_not_x 3")
    _assert_eq(a.code[6], 0x0244, "jmp_x_dec 4 delay 2")
    _assert_eq(a.code[7], 0x2091, "wait_gpio 1,17")
    _assert_eq(a.code[8], 0x6008, "out_pins 8")
    _assert_eq(a.code[9], 0x80A0, "pull_block")
    _assert_eq(a.code[10], 0x8080, "pull_noblock")
    _assert_eq(a.code[11], 0xA001, "mov_pins_x")
    _assert_eq(a.code[12], 0xA042, "nop")
    if a.len != 13:
        raise Error("length tracking broken")
    _ok("base instruction encodings")


def test_delay_field() raises:
    var a = Asm()
    a.nop(delay=31)          # full 5-bit delay, no side-set
    a.nop(delay=32)          # must mask to 0
    _assert_eq(a.code[0], 0xBF42, "delay 31 -> bits 12:8")
    _assert_eq(a.code[1], 0xA042, "delay 32 masks to 0")
    _ok("delay field masking (no side-set)")


def test_sideset_required() raises:
    # .side_set 1 (not optional): 1 side bit + 4 delay bits
    var a = Asm()
    a.side_set(1)
    a.nop(side=1)            # side=1 -> bit 12
    a.nop(side=0, delay=2)   # delay in bits 11:8
    a.nop(delay=15)          # no side given -> side bits 0
    a.nop(delay=31)          # delay masked to 4 bits now
    _assert_eq(a.code[0], 0xB042, "side=1")
    _assert_eq(a.code[1], 0xA242, "side=0 delay=2")
    _assert_eq(a.code[2], 0xAF42, "delay 15, side omitted")
    _assert_eq(a.code[3], 0xAF42, "delay 31 masks to 15")
    _ok("required side-set encoding")


def test_sideset_two_bits() raises:
    var a = Asm()
    a.side_set(2)            # 2 side bits + 3 delay bits
    a.nop(side=3, delay=7)   # side in bits 12:11, delay bits 10:8
    _assert_eq(a.code[0], 0xBF42, "side=3 delay=7")
    var b = Asm()
    b.side_set(2)
    b.nop(side=2, delay=1)
    _assert_eq(b.code[0], 0xB142, "side=2 delay=1")
    _ok("2-bit side-set encoding")


def test_sideset_optional() raises:
    # .side_set 1 opt: enable bit 12, side bit 11, delay bits 10:8
    var a = Asm()
    a.side_set(1, optional=True)
    a.nop()                  # no side -> enable bit clear
    a.nop(side=1)            # enable + side
    a.nop(side=0, delay=3)   # enable, side 0, delay 3
    _assert_eq(a.code[0], 0xA042, "opt: no side, no enable")
    _assert_eq(a.code[1], 0xB842, "opt: enable+side=1")
    _assert_eq(a.code[2], 0xB342, "opt: enable+side=0+delay=3")
    _ok("optional side-set (enable bit) encoding")


def test_forward_labels() raises:
    var a = Asm()
    var skip = a.future()
    a.jmp(skip)              # forward: emitted with target 0, fixed later
    a.set_pins(1)
    if a.unresolved() != 1:
        raise Error("pending fixup not counted")
    a.bind(skip)
    if a.unresolved() != 0:
        raise Error("bind did not resolve the fixup")
    a.nop()
    a.jmp(skip)              # backward use of the same handle
    _assert_eq(a.code[0], 0x0002, "forward jmp patched to bind address")
    _assert_eq(a.code[3], 0x0002, "post-bind jmp resolves directly")
    _ok("forward label declare/bind/fixup")


def test_forward_labels_multi() raises:
    var a = Asm()
    var l1 = a.future()
    var l2 = a.future()
    a.jmp(l1)
    a.jmp(l2)
    a.jmp(l1)
    a.bind(l1)               # address 3: patches instr 0 and 2 only
    a.nop()
    a.bind(l2)               # address 4: patches instr 1
    _assert_eq(a.code[0], 0x0003, "l1 fixup at 0")
    _assert_eq(a.code[1], 0x0004, "l2 fixup at 1")
    _assert_eq(a.code[2], 0x0003, "l1 fixup at 2")
    if a.unresolved() != 0:
        raise Error("all fixups must be resolved")
    _ok("multiple interleaved forward labels")


def test_label_backward() raises:
    var a = Asm()
    var top = a.label()
    a.nop()
    a.jmp(top)
    _assert_eq(a.code[1], 0x0000, "backward label address")
    _ok("backward label() unchanged")


def _sideset_prog() -> Asm:
    var a = Asm()
    a.side_set(1)
    var skip = a.future()
    a.jmp(skip, side=0)
    a.set_pins(1, side=1)
    a.bind(skip)
    a.nop(side=1, delay=2)
    a.jmp(0, side=0, delay=2)
    return a^


def test_comptime_assembly() raises:
    # The assembler runs at compile time: the program below is a flash
    # constant, and its encodings must match a runtime assembly of the
    # identical source exactly.
    comptime CT = _sideset_prog()
    comptime assert CT.len == 4, "comptime length"
    comptime assert CT.unresolved() == 0, "comptime fixups resolved"
    var rt = _sideset_prog()
    for i in range(32):
        _assert_eq(CT.code[i], rt.code[i], "comptime == runtime encoding")
    _ok("comptime assembly matches runtime, comptime-assertable")


def main() raises:
    test_basic_encodings()
    test_delay_field()
    test_sideset_required()
    test_sideset_two_bits()
    test_sideset_optional()
    test_forward_labels()
    test_forward_labels_multi()
    test_label_backward()
    test_comptime_assembly()
    print("pio-asm: all assertions passed")
