"""Blink for the Raspberry Pi Pico 2 (RP2350), native RISC-V — Mojo 直出.

Same source shape as src/main.mojo (the RP2040 blink); only the import
line differs (`pico.pico2` instead of `pico`). The chip-specific register
facts — the moved peripheral map, the RP2350 pad-ISOlation step, the
interleaved SIO offsets — all live in the SDK (src/pico/chips.mojo),
selected by the RP2350 chip parameter. No inlined addresses here.

This is the native-RISC-V milestone: unlike the RP2040 firmware (riscv32
IR *retargeted* to thumbv6m), Mojo compiles straight for the Hazard3
cores — no retarget, no external llc. See tools/build.mojo (rp2350 branch).
"""

from pico.pico2 import Pin, pins, init, sleep_ms


@export("mojo_main")
def start() abi("C"):
    init()

    var led = Pin[pins.LED]()

    led.make_output()

    while True:
        led.toggle()
        sleep_ms(250)
