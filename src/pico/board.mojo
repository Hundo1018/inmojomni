"""Boot-time bring-up for the Raspberry Pi Pico.

After boot2 hands control to us the chip runs from the ring oscillator
(~6 MHz, imprecise). `init()` switches to the board's 12 MHz crystal,
releases the peripherals we need from reset, and starts the 1 µs timer
tick, giving `pico.time` a real timebase.
"""

from pico.mmio import read32, write32, write32_clr
from pico.rp2040 import (
    CLK_REF_CTRL,
    CLK_REF_SELECTED,
    CLK_REF_SRC_XOSC,
    CLK_SYS_CTRL,
    CLK_SYS_SELECTED,
    CLK_SYS_SRC_CLK_REF,
    RESET_IO_BANK0,
    RESET_PADS_BANK0,
    RESET_TIMER,
    RESETS_RESET,
    RESETS_RESET_DONE,
    WATCHDOG_TICK,
    WATCHDOG_TICK_ENABLE,
    XOSC_CTRL,
    XOSC_CTRL_ENABLE,
    XOSC_CTRL_RANGE_1_15MHZ,
    XOSC_STARTUP,
    XOSC_STARTUP_DELAY,
    XOSC_STATUS,
    XOSC_STATUS_STABLE,
)


def init():
    """Bring the board to a known state: XOSC clocks, 1 µs timer, GPIO ready."""
    # 1. Start the 12 MHz crystal oscillator and wait until it is stable.
    write32(XOSC_STARTUP, XOSC_STARTUP_DELAY)
    write32(XOSC_CTRL, XOSC_CTRL_ENABLE | XOSC_CTRL_RANGE_1_15MHZ)
    while (read32(XOSC_STATUS) & XOSC_STATUS_STABLE) == 0:
        pass

    # 2. Glitchless clock switch: clk_ref <- XOSC, clk_sys <- clk_ref.
    write32(CLK_REF_CTRL, CLK_REF_SRC_XOSC)
    while read32(CLK_REF_SELECTED) != (UInt32(1) << CLK_REF_SRC_XOSC):
        pass
    write32(CLK_SYS_CTRL, CLK_SYS_SRC_CLK_REF)
    while read32(CLK_SYS_SELECTED) != (UInt32(1) << CLK_SYS_SRC_CLK_REF):
        pass

    # 3. Release IO_BANK0, PADS_BANK0 and TIMER from reset.
    comptime mask = RESET_IO_BANK0 | RESET_PADS_BANK0 | RESET_TIMER
    write32_clr(RESETS_RESET, mask)
    while (read32(RESETS_RESET_DONE) & mask) != mask:
        pass

    # 4. TIMER counts the watchdog tick: 12 MHz / 12 = 1 MHz -> 1 µs.
    write32(WATCHDOG_TICK, WATCHDOG_TICK_ENABLE | 12)
