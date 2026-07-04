"""PIO (Programmable I/O) — write PIO programs like programs.

No inline-assembly strings: a PIO program is built by calling methods
on `Asm`, labels are ordinary values, and loops are explicit jumps.

    var asm = Asm()
    var top = asm.label()
    asm.set_pindirs(1)
    asm.set_pins(1)
    asm.set_x(29)
    var d1 = asm.label()
    asm.jmp_x_dec(d1, delay=2)      # burn (x+1)*(1+delay) cycles
    asm.set_pins(0)
    ...
    asm.jmp(top)

    var sm = StateMachine[0, 0]()   # PIO0, state machine 0
    sm.load(asm)
    sm.set_set_pins(pins.LED, 1)
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


struct Asm(Movable):
    """A PIO program under construction (max 32 instructions)."""

    var code: InlineArray[UInt16, 32]
    var len: Int

    def __init__(out self):
        self.code = InlineArray[UInt16, 32](fill=0)
        self.len = 0

    def label(self) -> Int:
        """Current address — use as a jump target."""
        return self.len

    def _emit(mut self, instr: UInt16, delay: Int):
        # delay/side-set field is bits 12:8 (5 bits, no side-set here)
        self.code[self.len] = instr | (UInt16(delay & 0x1F) << 8)
        self.len += 1

    # --- SET (§3.4.10): drive pins / load registers with a constant ---

    def set_pins(mut self, value: Int, delay: Int = 0):
        self._emit(0xE000 | UInt16(value & 0x1F), delay)

    def set_pindirs(mut self, value: Int, delay: Int = 0):
        self._emit(0xE080 | UInt16(value & 0x1F), delay)

    def set_x(mut self, value: Int, delay: Int = 0):
        self._emit(0xE020 | UInt16(value & 0x1F), delay)

    def set_y(mut self, value: Int, delay: Int = 0):
        self._emit(0xE040 | UInt16(value & 0x1F), delay)

    # --- JMP (§3.4.2): conditions are separate, readable methods ------

    def jmp(mut self, target: Int, delay: Int = 0):
        self._emit(0x0000 | UInt16(target & 0x1F), delay)

    def jmp_not_x(mut self, target: Int, delay: Int = 0):
        self._emit(0x0020 | UInt16(target & 0x1F), delay)

    def jmp_x_dec(mut self, target: Int, delay: Int = 0):
        """Jump while X non-zero, post-decrement — the PIO loop idiom."""
        self._emit(0x0040 | UInt16(target & 0x1F), delay)

    def jmp_not_y(mut self, target: Int, delay: Int = 0):
        self._emit(0x0060 | UInt16(target & 0x1F), delay)

    def jmp_y_dec(mut self, target: Int, delay: Int = 0):
        self._emit(0x0080 | UInt16(target & 0x1F), delay)

    def jmp_pin(mut self, target: Int, delay: Int = 0):
        self._emit(0x00C0 | UInt16(target & 0x1F), delay)

    # --- WAIT (§3.4.3) --------------------------------------------------

    def wait_gpio(mut self, polarity: Int, gpio: Int, delay: Int = 0):
        self._emit(
            0x2000 | (UInt16(polarity & 1) << 7) | UInt16(gpio & 0x1F), delay
        )

    # --- OUT / PULL (§3.4.5, §3.4.7): FIFO -> shift register -> pins ---

    def out_pins(mut self, count: Int, delay: Int = 0):
        self._emit(0x6000 | UInt16(count & 0x1F), delay)

    def out_x(mut self, count: Int, delay: Int = 0):
        self._emit(0x6020 | UInt16(count & 0x1F), delay)

    def pull_block(mut self, delay: Int = 0):
        self._emit(0x80A0, delay)

    def pull_noblock(mut self, delay: Int = 0):
        self._emit(0x8080, delay)

    # --- MOV / NOP (§3.4.8) ----------------------------------------------

    def mov_pins_x(mut self, delay: Int = 0):
        self._emit(0xA001, delay)

    def mov_x_pins(mut self, delay: Int = 0):
        self._emit(0xA020, delay)

    def nop(mut self, delay: Int = 0):
        self._emit(0xA042, delay)  # mov y, y


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
        """Copy the program into instruction memory and wrap around it."""
        for i in range(program.len):
            write32(
                self._base() + _INSTR_MEM0 + UInt32(i * 4),
                UInt32(program.code[i]),
            )
        # EXECCTRL: WRAP_TOP = last instruction, WRAP_BOTTOM = 0
        var top = UInt32(program.len - 1) & 0x1F
        write32(self._sm_reg(_EXECCTRL), top << 12)

    def set_clkdiv(self, int_part: UInt32, frac: UInt32 = 0):
        """SM clock = clk_sys / (int_part + frac/256)."""
        write32(self._sm_reg(_CLKDIV), (int_part << 16) | ((frac & 0xFF) << 8))

    def set_set_pins(self, base: Int, count: Int):
        """Which pins SET instructions drive (base pin + count)."""
        var v = (UInt32(count & 0x7) << 26) | (UInt32(base & 0x1F) << 5)
        write32(self._sm_reg(_PINCTRL), v)

    def set_out_pins(self, base: Int, count: Int):
        var cur = read32(self._sm_reg(_PINCTRL))
        var v = (cur & ~UInt32(0x3F0001F)) | (UInt32(count & 0x3F) << 20) | UInt32(base & 0x1F)
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
