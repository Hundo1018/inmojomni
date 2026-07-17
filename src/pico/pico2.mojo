"""Raspberry Pi Pico 2 (RP2350) board module — the RP2350 counterpart to
the top-level `pico` package.

It re-exports the SDK bound to the RP2350 chip, so user code never has to
name the chip:

    from pico.pico2 import Pin, pins, init, sleep_ms

The binding is a compile-time partial-parameter alias (`Pin[_, RP2350]`)
plus two one-line wrappers; the chip-specific register facts live in
`pico.chips.RP2350`. The Hazard3 cores are RISC-V, so Mojo targets them
natively — see src/main_rp2350.mojo and tools/build.mojo.
"""

from pico.gpio import Pin as _Pin
from pico.board import init as _init
from pico.multicore import (
    fifo_pop as _fifo_pop,
    fifo_push as _fifo_push,
    halt_core1 as _halt_core1,
    launch as _launch,
)
from pico.pio import StateMachine as _StateMachine
from pico.pwm import Pwm as _Pwm
from pico.time import (
    init as _time_init,
    sleep_ms as _sleep_ms,
    sleep_us as _sleep_us,
    time_us as _time_us,
)
from pico.chips import RP2350
import pico.pins as pins

# Partial parameter binding: on this board `Pin[N]` means `Pin[N, RP2350]`
# and `StateMachine[P, SM]` targets the RP2350 (which adds PIO2).
comptime Pin = _Pin[_, RP2350]
comptime StateMachine = _StateMachine[_, _, RP2350]
comptime Pwm = _Pwm[_, RP2350]


def init_timer():
    """Start the 1 µs hardware timebase (XOSC + TICKS + TIMER0);
    prerequisite for time_us/sleep_us, ADC and UART on this board."""
    _time_init[RP2350]()


def time_us() -> UInt32:
    return _time_us[RP2350]()


def sleep_us(us: UInt32):
    _sleep_us[RP2350](us)


def launch_core1() -> Bool:
    return _launch[RP2350]()


def halt_core1():
    _halt_core1[RP2350]()


def fifo_push(v: UInt32, timeout_us: UInt32) -> Bool:
    return _fifo_push[RP2350](v, timeout_us)


def fifo_pop(timeout_us: UInt32) -> Tuple[Bool, UInt32]:
    return _fifo_pop[RP2350](timeout_us)


def init():
    _init[RP2350]()


def sleep_ms(ms: UInt32):
    _sleep_ms[RP2350](ms)
