"""Microsecond timing on the TIMER peripheral — chip-generic.

RP2040: `pico.board.init()` starts the 1 µs tick (unchanged API).
RP2350: call `time.init[RP2350]()` first (or `pico.pico2.init_timer()`).
It starts the 12 MHz crystal, switches clk_ref and clk_sys to it, points
the TICKS block at the TIMER (1 µs) and releases TIMER0 from reset.
This is deliberately NOT part of the minimal board `init()`: blink-size
firmwares don't pay for it, and the benchmark suite must keep running
from the boot ROSC so all four languages share one clock setup.

Wrap-around-safe: `now - start` is modular UInt32 arithmetic.
"""

from pico.chips import Chip, RP2040
from pico.mmio import read32, write32, write32_clr, write32_set
from pico.rp2040 import (
    CLK_REF_SRC_XOSC,
    CLK_SYS_SRC_CLK_REF,
    XOSC_CTRL_ENABLE,
    XOSC_CTRL_RANGE_1_15MHZ,
    XOSC_STARTUP_DELAY,
    XOSC_STATUS_STABLE,
)

# Scratch word for the RP2350 busy-wait fallback: each iteration does a
# volatile store here so the loop survives -O2. ~8000 iters/ms is tuned
# for the RP2350 ROSC (~11 MHz, imprecise) — used only before init().
comptime SPIN_SCRATCH: UInt32 = 0x2004_0000
comptime SPIN_ITERS_PER_MS: UInt32 = 8000


def init[C: Chip = RP2040]():
    """Bring up the 1 µs hardware timebase.

    No-op on the RP2040 (board init already did it). On chips with a
    TICKS block (RP2350): XOSC on and stable (same magic values as the
    RP2040 — 12 MHz crystal either way), glitchless clk_ref/clk_sys
    switch to it, TIMER0 out of reset, ticks at clk_ref/12 = 1 MHz."""
    comptime if C.HAS_TICKS_BLOCK:
        write32(C.XOSC_BASE + 0x0C, XOSC_STARTUP_DELAY)
        write32(C.XOSC_BASE + 0x00, XOSC_CTRL_ENABLE | XOSC_CTRL_RANGE_1_15MHZ)
        while (read32(C.XOSC_BASE + 0x04) & XOSC_STATUS_STABLE) == 0:
            pass
        write32(C.CLOCKS_BASE + 0x30, CLK_REF_SRC_XOSC)
        while read32(C.CLOCKS_BASE + 0x38) != (UInt32(1) << CLK_REF_SRC_XOSC):
            pass
        write32(C.CLOCKS_BASE + 0x3C, CLK_SYS_SRC_CLK_REF)
        while read32(C.CLOCKS_BASE + 0x44) != 1:
            pass
        write32_clr(C.RESETS_RESET, C.RESET_TIMER)
        while (read32(C.RESETS_RESET_DONE) & C.RESET_TIMER) == 0:
            pass
        write32(C.TICKS_BASE + 0x1C, 12)  # TIMER0 CYCLES: 12 MHz / 12
        write32(C.TICKS_BASE + 0x18, 1)  # TIMER0 CTRL.ENABLE


@always_inline
def time_us[C: Chip = RP2040]() -> UInt32:
    """Microseconds since boot (wraps every ~71.6 minutes)."""
    return read32(C.TIMER_BASE + 0x28)  # TIMERAWL


def alarm0_arm[C: Chip = RP2040](us_from_now: UInt32):
    """One-shot: fire TIMER IRQ 0 in `us_from_now` µs.

    Enable the interrupt line first (NVIC on the RP2040, Xh3irq on the
    RP2350) and provide a handler that calls `alarm0_ack()`."""
    write32_set(C.TIMER_BASE + C.TIMER_INTE_OFF, 1)
    write32(C.TIMER_BASE + 0x10, time_us[C]() + us_from_now)  # ALARM0


@always_inline
def alarm0_ack[C: Chip = RP2040]():
    """Clear the latched ALARM0 interrupt (write-1-clear)."""
    write32(C.TIMER_BASE + C.TIMER_INTR_OFF, 1)


def sleep_us[C: Chip = RP2040](us: UInt32):
    var start = time_us[C]()
    while time_us[C]() - start < us:
        pass


def sleep_ms[C: Chip = RP2040](ms: UInt32):
    """Block for approximately `ms` milliseconds.

    On the RP2040 the 1 µs TIMER runs from board init, so this is
    exact. On the RP2350 the timer needs an explicit `time.init` first;
    since minimal firmwares (blink) skip that, this keeps the
    calibrated busy-wait — approximate by design. Post-init RP2350 code
    that wants exact delays calls `sleep_us[RP2350]` directly."""
    comptime if C.USES_HW_TIMER:
        sleep_us[C](ms * 1000)
    else:
        var total = ms * SPIN_ITERS_PER_MS
        var i: UInt32 = 0
        while i < total:
            write32(SPIN_SCRATCH, i)
            i += 1
