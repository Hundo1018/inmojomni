"""Microsecond timing built on the RP2040 TIMER peripheral.

Requires `pico.board.init()` first (it starts the 1 MHz tick).
Wrap-around-safe: `now - start` is modular UInt32 arithmetic.
"""

from pico.chips import Chip, RP2040
from pico.mmio import read32, write32, write32_set
from pico.rp2040 import TIMER_ALARM0, TIMER_INTE, TIMER_INTR, TIMER_TIMERAWL

# Scratch word for the RP2350 busy-wait: each iteration does a volatile
# store here so the loop survives -O2 (a pure arithmetic loop is dead-code
# eliminated). ~8000 iters/ms is tuned for the RP2350 ROSC (~11 MHz, and
# imprecise), matching the original hand-tuned native-RISC-V blink.
comptime SPIN_SCRATCH: UInt32 = 0x2004_0000
comptime SPIN_ITERS_PER_MS: UInt32 = 8000


@always_inline
def time_us() -> UInt32:
    """Microseconds since boot (wraps every ~71.6 minutes)."""
    return read32(TIMER_TIMERAWL)


def alarm0_arm(us_from_now: UInt32):
    """One-shot: fire TIMER_IRQ_0 in `us_from_now` µs.

    Enable the NVIC line first (`irq.enable(irq.TIMER_IRQ_0)`) and
    export an `isr_irq0` handler that calls `alarm0_ack()`."""
    write32_set(TIMER_INTE, 1)
    write32(TIMER_ALARM0, time_us() + us_from_now)


@always_inline
def alarm0_ack():
    """Clear the latched ALARM0 interrupt (write-1-clear)."""
    write32(TIMER_INTR, 1)


def sleep_us(us: UInt32):
    var start = time_us()
    while time_us() - start < us:
        pass


def sleep_ms[C: Chip = RP2040](ms: UInt32):
    """Block for approximately `ms` milliseconds.

    `C` defaults to RP2040, whose implementation (the 1 µs TIMER) is
    unchanged. On chips without a configured hardware timebase (RP2350)
    this falls back to a calibrated busy-wait — approximate by design."""
    comptime if C.USES_HW_TIMER:
        sleep_us(ms * 1000)
    else:
        var total = ms * SPIN_ITERS_PER_MS
        var i: UInt32 = 0
        while i < total:
            write32(SPIN_SCRATCH, i)
            i += 1
