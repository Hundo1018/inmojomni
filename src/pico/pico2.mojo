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
from pico.time import sleep_ms as _sleep_ms
from pico.chips import RP2350
import pico.pins as pins

# Partial parameter binding: on this board `Pin[N]` means `Pin[N, RP2350]`.
comptime Pin = _Pin[_, RP2350]


def init():
    _init[RP2350]()


def sleep_ms(ms: UInt32):
    _sleep_ms[RP2350](ms)
