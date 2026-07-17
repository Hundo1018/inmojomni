"""PWM driver. 8 slices x 2 channels; the slice/channel for a GPIO is
fixed by hardware, so `Pwm[PIN]` derives both at compile time — asking
for a pin is all it takes, and an out-of-range pin is a compile error.

    from pico.pwm import Pwm

    var pwm = Pwm[15]()      # slice 7 channel B, funcsel switched
    pwm.set_top(999)         # wrap: 12 MHz / 1000 = 12 kHz
    pwm.set_level(500)       # 50% duty
    pwm.enable()
"""

from pico.chips import Chip, RP2040
from pico.gpio import Function, Pin
from pico.mmio import read32, write32, write32_clr, write32_set


struct Pwm[PIN: Int, C: Chip = RP2040](TrivialRegisterPassable):
    """One PWM output, bound to a GPIO at compile time.
    slice = (PIN >> 1) % NUM_PWM_SLICES; channel B when PIN is odd.
    Chip-generic: base address, slice count and RESETS bit from `C`."""

    comptime SLICE: Int = (Self.PIN >> 1) % Self.C.NUM_PWM_SLICES
    comptime IS_B: Bool = (Self.PIN & 1) == 1
    comptime CSR: UInt32 = Self.C.PWM_BASE + UInt32(0x14 * Self.SLICE)
    comptime DIV: UInt32 = Self.CSR + 0x04
    comptime CTR: UInt32 = Self.CSR + 0x08
    comptime CC: UInt32 = Self.CSR + 0x0C
    comptime TOP: UInt32 = Self.CSR + 0x10

    def __init__(out self):
        comptime assert (
            Self.PIN >= 0 and Self.PIN < Self.C.NUM_GPIOS
        ), "GPIO number out of range for this chip"
        comptime assert Self.C.NUM_PWM_SLICES == 8 or Self.PIN < 24, (
            "PWM slice mapping above GPIO23 is unverified on this chip"
        )
        write32_clr(Self.C.RESETS_RESET, Self.C.RESET_PWM)
        while (read32(Self.C.RESETS_RESET_DONE) & Self.C.RESET_PWM) == 0:
            pass
        var pin = Pin[Self.PIN, Self.C]()
        pin.set_function(Function.PWM)

    def set_top(self, top: UInt32):
        """Wrap value: frequency = clk_sys / (div * (top + 1))."""
        write32(Self.TOP, top & 0xFFFF)

    def set_div_int(self, div: UInt32):
        """Integer clock divider 1..255 (8.4 fixed point, frac = 0)."""
        write32(Self.DIV, (div & 0xFF) << 4)

    def set_level(self, level: UInt32):
        """Compare level for this pin's channel (duty = level/(top+1))."""
        var cc = read32(Self.CC)
        comptime if Self.IS_B:
            write32(Self.CC, (cc & 0x0000_FFFF) | ((level & 0xFFFF) << 16))
        else:
            write32(Self.CC, (cc & 0xFFFF_0000) | (level & 0xFFFF))

    def enable(self):
        write32_set(Self.CSR, 1)

    def disable(self):
        write32_clr(Self.CSR, 1)

    def counter(self) -> UInt32:
        return read32(Self.CTR) & 0xFFFF
