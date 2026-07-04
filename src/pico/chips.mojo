"""Chip/board descriptors — the road to multi-MCU inmojomni.

A chip is a *compile-time value*: a struct conforming to `Chip`, whose
associated constants describe what the silicon has. SDK types take the
chip as a parameter and enforce constraints with `comptime assert`, so
"this pin doesn't exist on that package" is a compile error, not a
field bug. See docs/MULTICHIP.md for the full design.

Status: prototype. The RP2040 SDK modules don't consume these yet.
"""


trait Chip:
    comptime NAME: StaticString
    comptime NUM_GPIOS: Int
    comptime NUM_CORES: Int
    comptime NUM_PIO_BLOCKS: Int
    comptime SRAM_BYTES: Int
    comptime SIO_BASE: UInt32


struct RP2040(Chip):
    comptime NAME: StaticString = "RP2040"
    comptime NUM_GPIOS: Int = 30
    comptime NUM_CORES: Int = 2
    comptime NUM_PIO_BLOCKS: Int = 2
    comptime SRAM_BYTES: Int = 264 * 1024
    comptime SIO_BASE: UInt32 = 0xD000_0000


struct RP2350(Chip):
    """Pico 2. Hazard3 RISC-V cores: Mojo can target these natively
    (riscv32 backend built in — no IR retargeting needed at all)."""

    comptime NAME: StaticString = "RP2350"
    comptime NUM_GPIOS: Int = 30  # QFN-60; RP2350B has 48
    comptime NUM_CORES: Int = 2
    comptime NUM_PIO_BLOCKS: Int = 3
    comptime SRAM_BYTES: Int = 520 * 1024
    comptime SIO_BASE: UInt32 = 0xD000_0000


struct PicoBoard:
    """Board = chip + wiring facts."""

    comptime CHIP = RP2040  # the chip is a type, not a value
    comptime LED: Int = 25
    comptime XOSC_HZ: Int = 12_000_000


def gpio_budget[C: Chip]() -> Int:
    """Example of chip-generic code: constraints resolve at compile time."""
    return C.NUM_GPIOS
