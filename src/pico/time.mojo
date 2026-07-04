"""Microsecond timing built on the RP2040 TIMER peripheral.

Requires `pico.board.init()` first (it starts the 1 MHz tick).
Wrap-around-safe: `now - start` is modular UInt32 arithmetic.
"""

from pico.mmio import read32, write32, write32_set
from pico.rp2040 import TIMER_ALARM0, TIMER_INTE, TIMER_INTR, TIMER_TIMERAWL


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


def sleep_ms(ms: UInt32):
    sleep_us(ms * 1000)
