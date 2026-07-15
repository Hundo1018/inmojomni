"""Boot-time bring-up for the Raspberry Pi Pico.

After boot2 hands control to us the chip runs from the ring oscillator
(~6 MHz, imprecise). `init()` switches to the board's 12 MHz crystal,
releases the peripherals we need from reset, and starts the 1 µs timer
tick, giving `pico.time` a real timebase.
"""

from pico.chips import Chip, RP2040
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


def init[C: Chip = RP2040]():
    """Bring the board to a known state, then leave the GPIO block ready.

    `C` defaults to RP2040 (so `pico.init()` is unchanged). On chips with
    a hardware timebase (`USES_HW_TIMER`) this starts XOSC and the 1 µs
    TIMER tick; on the RP2350 the ROSC already clocks clk_sys at boot, so
    all that is needed is to bring IO_BANK0/PADS_BANK0 out of reset.
    """
    comptime if C.USES_HW_TIMER:
        # ---- RP2040 path (unchanged) --------------------------------
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
    else:
        # ---- RP2350 path (ROSC already clocks clk_sys; no timer) -----
        # Just bring the GPIO peripherals out of reset and wait for the ack.
        comptime gpio_mask = C.RESET_IO_BANK0 | C.RESET_PADS_BANK0
        write32_clr(C.RESETS_RESET, gpio_mask)
        while (read32(C.RESETS_RESET_DONE) & gpio_mask) != gpio_mask:
            pass
