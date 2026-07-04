"""PIO (Programmable I/O) — write PIO programs like programs.

No inline-assembly strings: a PIO program is built by calling methods
on `Asm`, labels are ordinary values, and loops are explicit jumps.

    var asm = Asm()
    var top = asm.label()
    asm.set_pins(1)
    asm.set_x(29)
    var d1 = asm.label()
    asm.jmp_x_dec(d1, delay=2)      # burn (x+1)*(1+delay) cycles
    asm.set_pins(0)
    asm.jmp(top)

Side-set drives extra pins in parallel with every instruction; forward
labels jump to code that is not written yet:

    var asm = Asm()
    asm.side_set(1)                 # every instr also drives 1 pin
    var body = asm.future()         # declared now ...
    asm.jmp(body, side=0)           # ... jumpable now ...
    asm.set_pins(1, side=1)
    asm.bind(body)                  # ... placed here
    asm.nop(side=1, delay=2)

    var sm = StateMachine[0, 0]()   # PIO0, state machine 0
    sm.load(asm)                    # configures wrap + side-set mode
    sm.set_sideset_pins(pins.LED)
    sm.set_clkdiv(65535)
    sm.enable()

Encodings follow the RP2040 datasheet §3.4.
"""

from pico.mmio import read32, write32, write32_clr
from pico.rp2040 import (
    RESET_PIO0,
    RESET_PIO1,
    RESETS_RESET,
    RESETS_RESET_DONE,
)

comptime PIO0_BASE: UInt32 = 0x5020_0000
comptime PIO1_BASE: UInt32 = 0x5030_0000

# Register offsets within a PIO block.
comptime _CTRL: UInt32 = 0x000
comptime _FSTAT: UInt32 = 0x004
comptime _TXF0: UInt32 = 0x010
comptime _RXF0: UInt32 = 0x020
comptime _INSTR_MEM0: UInt32 = 0x048
comptime _SM0_CLKDIV: UInt32 = 0x0C8
comptime _SM_STRIDE: UInt32 = 0x18
comptime _CLKDIV: UInt32 = 0x0  # offsets within one SM's register group
comptime _EXECCTRL: UInt32 = 0x4
comptime _SHIFTCTRL: UInt32 = 0x8
comptime _ADDR: UInt32 = 0xC
comptime _INSTR: UInt32 = 0x10
comptime _PINCTRL: UInt32 = 0x14

comptime _MAX_FUTURES = 8


struct Asm(Movable):
    """A PIO program under construction (max 32 instructions)."""

    var code: InlineArray[UInt16, 32]
    var len: Int
    # side-set configuration (applies to the whole program)
    var side_count: Int
    var side_opt: Bool
    var side_pindirs: Bool
    # forward labels: handle -> bound address (-1 = unbound), and the
    # per-instruction fixup table (value = handle index + 1)
    var _fw_addr: InlineArray[Int, _MAX_FUTURES]
    var _fw_used: Int
    var _fixup: InlineArray[Int, 32]
    var _pending: Int

    def __init__(out self):
        self.code = InlineArray[UInt16, 32](fill=0)
        self.len = 0
        self.side_count = 0
        self.side_opt = False
        self.side_pindirs = False
        self._fw_addr = InlineArray[Int, _MAX_FUTURES](fill=-1)
        self._fw_used = 0
        self._fixup = InlineArray[Int, 32](fill=0)
        self._pending = 0

    def side_set(mut self, count: Int, optional: Bool = False,
                 pindirs: Bool = False):
        """Reserve `count` of the 5 delay bits for side-set (call before
        emitting). `optional`: instructions without `side=` leave the
        pins alone (costs one more bit). `pindirs`: side-set drives pin
        directions instead of values."""
        self.side_count = count & 0x7
        self.side_opt = optional
        self.side_pindirs = pindirs

    def label(self) -> Int:
        """Current address — use as a (backward) jump target."""
        return self.len

    def future(mut self) -> Int:
        """Declare a label to `bind()` later; usable in jumps already.
        Returns a handle (negative, so it cannot collide with label())."""
        var id = self._fw_used
        self._fw_used += 1
        return -(id + 1)

    def bind(mut self, handle: Int):
        """Place a `future()` label here and patch earlier jumps to it."""
        var id = -handle - 1
        self._fw_addr[id] = self.len
        for i in range(self.len):
            if self._fixup[i] == id + 1:
                self.code[i] = (self.code[i] & ~UInt16(0x1F)) | UInt16(
                    self.len & 0x1F
                )
                self._fixup[i] = 0
                self._pending -= 1

    def unresolved(self) -> Int:
        """Number of forward jumps still waiting for a bind()."""
        return self._pending

    def _emit(mut self, instr: UInt16, delay: Int, side: Int):
        # bits 12:8 hold [enable?][side-set bits][delay bits]; side-set
        # width is side_count, plus one enable bit when optional
        var s_bits = self.side_count + (1 if self.side_opt else 0)
        var field = delay & ((1 << (5 - s_bits)) - 1)
        if self.side_count > 0 and side >= 0:
            var sv = side & ((1 << self.side_count) - 1)
            if self.side_opt:
                field |= 0x10 | (sv << (4 - self.side_count))
            else:
                field |= sv << (5 - self.side_count)
        self.code[self.len] = instr | (UInt16(field & 0x1F) << 8)
        self.len += 1

    def _jmp_target(mut self, target: Int) -> UInt16:
        var t = target
        if t < 0:
            var id = -t - 1
            if self._fw_addr[id] >= 0:
                t = self._fw_addr[id]
            else:
                self._fixup[self.len] = id + 1
                self._pending += 1
                t = 0
        return UInt16(t & 0x1F)

    # --- SET (§3.4.10): drive pins / load registers with a constant ---

    def set_pins(mut self, value: Int, delay: Int = 0, side: Int = -1):
        self._emit(0xE000 | UInt16(value & 0x1F), delay, side)

    def set_pindirs(mut self, value: Int, delay: Int = 0, side: Int = -1):
        self._emit(0xE080 | UInt16(value & 0x1F), delay, side)

    def set_x(mut self, value: Int, delay: Int = 0, side: Int = -1):
        self._emit(0xE020 | UInt16(value & 0x1F), delay, side)

    def set_y(mut self, value: Int, delay: Int = 0, side: Int = -1):
        self._emit(0xE040 | UInt16(value & 0x1F), delay, side)

    # --- JMP (§3.4.2): conditions are separate, readable methods.
    # Targets accept label() addresses and future() handles alike. ----

    def jmp(mut self, target: Int, delay: Int = 0, side: Int = -1):
        var t = self._jmp_target(target)
        self._emit(0x0000 | t, delay, side)

    def jmp_not_x(mut self, target: Int, delay: Int = 0, side: Int = -1):
        var t = self._jmp_target(target)
        self._emit(0x0020 | t, delay, side)

    def jmp_x_dec(mut self, target: Int, delay: Int = 0, side: Int = -1):
        """Jump while X non-zero, post-decrement — the PIO loop idiom."""
        var t = self._jmp_target(target)
        self._emit(0x0040 | t, delay, side)

    def jmp_not_y(mut self, target: Int, delay: Int = 0, side: Int = -1):
        var t = self._jmp_target(target)
        self._emit(0x0060 | t, delay, side)

    def jmp_y_dec(mut self, target: Int, delay: Int = 0, side: Int = -1):
        var t = self._jmp_target(target)
        self._emit(0x0080 | t, delay, side)

    def jmp_pin(mut self, target: Int, delay: Int = 0, side: Int = -1):
        var t = self._jmp_target(target)
        self._emit(0x00C0 | t, delay, side)

    # --- WAIT (§3.4.3) --------------------------------------------------

    def wait_gpio(mut self, polarity: Int, gpio: Int, delay: Int = 0,
                  side: Int = -1):
        self._emit(
            0x2000 | (UInt16(polarity & 1) << 7) | UInt16(gpio & 0x1F),
            delay, side,
        )

    # --- OUT / PULL (§3.4.5, §3.4.7): FIFO -> shift register -> pins ---

    def out_pins(mut self, count: Int, delay: Int = 0, side: Int = -1):
        self._emit(0x6000 | UInt16(count & 0x1F), delay, side)

    def out_x(mut self, count: Int, delay: Int = 0, side: Int = -1):
        self._emit(0x6020 | UInt16(count & 0x1F), delay, side)

    def pull_block(mut self, delay: Int = 0, side: Int = -1):
        self._emit(0x80A0, delay, side)

    def pull_noblock(mut self, delay: Int = 0, side: Int = -1):
        self._emit(0x8080, delay, side)

    # --- MOV / NOP (§3.4.8) ----------------------------------------------

    def mov_pins_x(mut self, delay: Int = 0, side: Int = -1):
        self._emit(0xA001, delay, side)

    def mov_x_pins(mut self, delay: Int = 0, side: Int = -1):
        self._emit(0xA020, delay, side)

    def nop(mut self, delay: Int = 0, side: Int = -1):
        self._emit(0xA042, delay, side)  # mov y, y


struct StateMachine[P: Int, SM: Int](TrivialRegisterPassable):
    """State machine `SM` of PIO block `P` — both compile-time checked."""

    def __init__(out self):
        comptime assert Self.P == 0 or Self.P == 1, "RP2040 has PIO0 and PIO1"
        comptime assert 0 <= Self.SM and Self.SM < 4, (
            "each PIO block has state machines 0..3"
        )
        # Release the PIO block from reset (idempotent).
        comptime reset_mask = RESET_PIO0 if Self.P == 0 else RESET_PIO1
        write32_clr(RESETS_RESET, reset_mask)
        while (read32(RESETS_RESET_DONE) & reset_mask) == 0:
            pass

    @always_inline
    def _base(self) -> UInt32:
        return PIO0_BASE if Self.P == 0 else PIO1_BASE

    @always_inline
    def _sm_reg(self, offset: UInt32) -> UInt32:
        return self._base() + _SM0_CLKDIV + UInt32(Self.SM) * _SM_STRIDE + offset

    def load(self, program: Asm):
        """Copy the program into instruction memory, wrap around it, and
        configure the side-set mode the program was written for."""
        for i in range(program.len):
            write32(
                self._base() + _INSTR_MEM0 + UInt32(i * 4),
                UInt32(program.code[i]),
            )
        # EXECCTRL: WRAP_TOP = last instruction, WRAP_BOTTOM = 0,
        # SIDE_EN (bit 30) when side-set is optional, SIDE_PINDIR (29)
        var top = UInt32(program.len - 1) & 0x1F
        var exec = top << 12
        if program.side_opt:
            exec |= UInt32(1) << 30
        if program.side_pindirs:
            exec |= UInt32(1) << 29
        write32(self._sm_reg(_EXECCTRL), exec)
        # PINCTRL.SIDESET_COUNT includes the enable bit when optional.
        var s_bits = UInt32(
            program.side_count + (1 if program.side_opt else 0)
        )
        var cur = read32(self._sm_reg(_PINCTRL))
        write32(
            self._sm_reg(_PINCTRL),
            (cur & ~(UInt32(7) << 29)) | (s_bits << 29),
        )

    def set_clkdiv(self, int_part: UInt32, frac: UInt32 = 0):
        """SM clock = clk_sys / (int_part + frac/256)."""
        write32(self._sm_reg(_CLKDIV), (int_part << 16) | ((frac & 0xFF) << 8))

    def set_set_pins(self, base: Int, count: Int):
        """Which pins SET instructions drive (base pin + count)."""
        var cur = read32(self._sm_reg(_PINCTRL))
        var mask = (UInt32(7) << 26) | (UInt32(0x1F) << 5)
        var v = (cur & ~mask) | (UInt32(count & 0x7) << 26) | (
            UInt32(base & 0x1F) << 5
        )
        write32(self._sm_reg(_PINCTRL), v)

    def set_out_pins(self, base: Int, count: Int):
        var cur = read32(self._sm_reg(_PINCTRL))
        var v = (cur & ~UInt32(0x3F0001F)) | (UInt32(count & 0x3F) << 20) | UInt32(base & 0x1F)
        write32(self._sm_reg(_PINCTRL), v)

    def set_sideset_pins(self, base: Int):
        """Base pin for side-set (width comes from the program's
        side_set() declaration via load())."""
        var cur = read32(self._sm_reg(_PINCTRL))
        var v = (cur & ~(UInt32(0x1F) << 10)) | (UInt32(base & 0x1F) << 10)
        write32(self._sm_reg(_PINCTRL), v)

    def exec(self, instr: UInt16):
        """Execute one instruction immediately (e.g. initial pindirs)."""
        write32(self._sm_reg(_INSTR), UInt32(instr))

    def enable(self):
        var ctrl = self._base() + _CTRL
        write32(ctrl, read32(ctrl) | (UInt32(1) << UInt32(Self.SM)))

    def disable(self):
        var ctrl = self._base() + _CTRL
        write32(ctrl, read32(ctrl) & ~(UInt32(1) << UInt32(Self.SM)))

    def restart(self):
        var ctrl = self._base() + _CTRL
        write32(ctrl, read32(ctrl) | (UInt32(1) << UInt32(Self.SM + 4)))

    def tx_push(self, value: UInt32):
        write32(self._base() + _TXF0 + UInt32(Self.SM * 4), value)

    def pc(self) -> UInt32:
        """Current program counter of the state machine."""
        return read32(self._sm_reg(_ADDR)) & 0x1F
