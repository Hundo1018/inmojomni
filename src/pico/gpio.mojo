"""GPIO driven through SIO (single-cycle I/O) — full pin control.

The pin number is a *compile-time parameter*: `Pin[25]` is its own type,
an invalid pin number is a compile error, and every operation folds to
one or two instructions with the mask baked in as an immediate.

Pad-electrical settings (pulls, drive strength, slew, Schmitt) use the
RP2040 atomic SET/CLR register aliases, so they are race-free without
read-modify-write.
"""

from pico.chips import Chip, RP2040
from pico.mmio import read32, write32, write32_clr, write32_set
from pico.rp2040 import (
    FUNCSEL_SIO,
    PADS_DRIVE_LSB,
    PADS_DRIVE_MASK,
    PADS_IE,
    PADS_OD,
    PADS_PDE,
    PADS_PUE,
    PADS_SCHMITT,
    PADS_SLEWFAST,
)


struct Function:
    """IO_BANK0 FUNCSEL values (datasheet §2.19.2). Which peripheral
    instance a value selects depends on the pin — see pins.mojo."""

    comptime SPI: UInt32 = 1
    comptime UART: UInt32 = 2
    comptime I2C: UInt32 = 3
    comptime PWM: UInt32 = 4
    comptime SIO: UInt32 = 5
    comptime PIO0: UInt32 = 6
    comptime PIO1: UInt32 = 7
    comptime PIO2: UInt32 = 8  # RP2350 only (RP2040 has no funcsel 8)
    comptime GPCK: UInt32 = 8  # clock in/out (GPIO20-25 only)
    comptime USB: UInt32 = 9   # VBUS det / VBUS en / overcurrent det
    comptime NONE: UInt32 = 0x1F


struct Drive:
    """Pad output drive strength."""

    comptime MA_2: UInt32 = 0
    comptime MA_4: UInt32 = 1  # reset default
    comptime MA_8: UInt32 = 2
    comptime MA_12: UInt32 = 3


struct Event:
    """GPIO interrupt/event bits, 4 per pin (datasheet §2.19.6.1).
    Edge bits are latched and must be acknowledged; level bits are raw."""

    comptime LEVEL_LOW: UInt32 = 1
    comptime LEVEL_HIGH: UInt32 = 2
    comptime EDGE_LOW: UInt32 = 4
    comptime EDGE_HIGH: UInt32 = 8
    comptime ALL: UInt32 = 0xF


struct Pin[N: Int, C: Chip = RP2040](TrivialRegisterPassable):
    """GPIO pin `N` on chip `C`, checked at compile time.

    `C` defaults to RP2040, so `Pin[25]()` is unchanged; a board module
    binds it (e.g. `pico.pico2` aliases `Pin = Pin[_, RP2350]`). All the
    register bases come from `C`, so the same driver drives either chip.
    """

    def __init__(out self):
        comptime assert 0 <= Self.N and Self.N < Self.C.NUM_GPIOS, (
            "GPIO number out of range for this chip"
        )
        self.set_function(FUNCSEL_SIO)

    # --- addressing helpers (all fold to constants) -----------------

    @always_inline
    def _mask(self) -> UInt32:
        return UInt32(1) << UInt32(Self.N)

    @always_inline
    def _ctrl(self) -> UInt32:
        return Self.C.IO_BANK0_BASE + UInt32(8 * Self.N + 4)

    @always_inline
    def _pad(self) -> UInt32:
        return Self.C.PADS_BANK0_BASE + UInt32(4 + 4 * Self.N)

    @always_inline
    def _intr(self) -> UInt32:
        # +0xF0 (INTR0) is RP2040-verified; RP2350 IRQ layout is out of scope.
        return Self.C.IO_BANK0_BASE + UInt32(0xF0) + UInt32(4 * (Self.N // 8))

    @always_inline
    def _event_shift(self) -> UInt32:
        return UInt32(4 * (Self.N % 8))

    # --- function select ---------------------------------------------

    def set_function(self, f: UInt32):
        write32(self._ctrl(), f)

    def get_function(self) -> UInt32:
        return read32(self._ctrl()) & 0x1F

    # --- direction ----------------------------------------------------

    def make_output(self):
        write32(Self.C.SIO_GPIO_OE_SET, self._mask())
        comptime if Self.C.HAS_PAD_ISO:
            # RP2350 only: every pad powers up ISOlated (PADS bit 8) and
            # de-resetting PADS does NOT clear it (datasheet §9.7). Clear it
            # LAST, so the pad connects only once the output is configured.
            write32_clr(self._pad(), UInt32(1) << 8)

    def make_input(self):
        write32(Self.C.SIO_GPIO_OE_CLR, self._mask())
        self.input_enable(True)

    def is_output(self) -> Bool:
        return (read32(Self.C.SIO_GPIO_OE) & self._mask()) != 0

    # --- output level ---------------------------------------------------

    def high(self):
        write32(Self.C.SIO_GPIO_OUT_SET, self._mask())

    def low(self):
        write32(Self.C.SIO_GPIO_OUT_CLR, self._mask())

    def toggle(self):
        write32(Self.C.SIO_GPIO_OUT_XOR, self._mask())

    def write(self, level: Bool):
        if level:
            self.high()
        else:
            self.low()

    def read_output(self) -> Bool:
        """What we are driving (SIO.GPIO_OUT), not what the pad sees."""
        return (read32(Self.C.SIO_GPIO_OUT) & self._mask()) != 0

    # --- input ----------------------------------------------------------

    def read(self) -> Bool:
        """Read the actual pad state (input enable is on by default, so
        this also reads back what an output pin is driving)."""
        return (read32(Self.C.SIO_GPIO_IN) & self._mask()) != 0

    # --- pad electrical control (atomic set/clr, race-free) -------------

    def pull_up(self):
        write32_set(self._pad(), PADS_PUE)
        write32_clr(self._pad(), PADS_PDE)

    def pull_down(self):
        write32_set(self._pad(), PADS_PDE)
        write32_clr(self._pad(), PADS_PUE)

    def pull_none(self):
        write32_clr(self._pad(), PADS_PUE | PADS_PDE)

    def bus_keep(self):
        """Weakly hold the last driven level (PUE+PDE together)."""
        write32_set(self._pad(), PADS_PUE | PADS_PDE)

    def set_drive(self, strength: UInt32):
        """Drive.MA_2 / MA_4 / MA_8 / MA_12. Two atomic ops: the pad
        passes through the weaker setting for a few ns in between."""
        write32_clr(self._pad(), PADS_DRIVE_MASK)
        write32_set(self._pad(), (strength << PADS_DRIVE_LSB) & PADS_DRIVE_MASK)

    def schmitt(self, enable: Bool):
        if enable:
            write32_set(self._pad(), PADS_SCHMITT)
        else:
            write32_clr(self._pad(), PADS_SCHMITT)

    def slew_fast(self, enable: Bool):
        if enable:
            write32_set(self._pad(), PADS_SLEWFAST)
        else:
            write32_clr(self._pad(), PADS_SLEWFAST)

    def input_enable(self, enable: Bool):
        if enable:
            write32_set(self._pad(), PADS_IE)
        else:
            write32_clr(self._pad(), PADS_IE)

    def output_disable(self, disable: Bool):
        """Hard-disable the pad driver (overrides SIO output enable)."""
        if disable:
            write32_set(self._pad(), PADS_OD)
        else:
            write32_clr(self._pad(), PADS_OD)

    def pad_config(self) -> UInt32:
        """Raw pad register — for tests and debugging."""
        return read32(self._pad())

    # --- events: polled via INTR, or routed to IO_IRQ_BANK0 (NVIC) -----

    def events(self) -> UInt32:
        """Current Event bits for this pin (raw INTR register)."""
        return (read32(self._intr()) >> self._event_shift()) & Event.ALL

    def ack_events(self, mask: UInt32):
        """Clear latched edge events (level bits clear by themselves)."""
        write32(self._intr(), (mask & Event.ALL) << self._event_shift())

    def _inte(self) -> UInt32:
        # +0x100/+0x120 (PROC0_INTE0/INTS0) are RP2040-verified offsets.
        return Self.C.IO_BANK0_BASE + UInt32(0x100) + UInt32(4 * (Self.N // 8))

    def _ints(self) -> UInt32:
        return Self.C.IO_BANK0_BASE + UInt32(0x120) + UInt32(4 * (Self.N // 8))

    def irq_enable(self, mask: UInt32):
        """Route Event bits to IO_IRQ_BANK0 (processor 0). Also enable
        the NVIC line and export a handler:

            @export("isr_irq13")            # irq.IO_IRQ_BANK0
            def on_gpio() abi("C"):
                var pin = Pin[15]()
                ... pin.irq_status() ...
                pin.ack_events(Event.EDGE_HIGH)

            irq.enable(irq.IO_IRQ_BANK0)
        """
        write32_set(self._inte(), (mask & Event.ALL) << self._event_shift())

    def irq_disable(self, mask: UInt32):
        write32_clr(self._inte(), (mask & Event.ALL) << self._event_shift())

    def irq_status(self) -> UInt32:
        """Event bits currently asserting IO_IRQ_BANK0 for this pin
        (masked status: raw events AND-ed with irq_enable mask)."""
        return (read32(self._ints()) >> self._event_shift()) & Event.ALL
