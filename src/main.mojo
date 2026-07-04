"""Blink — the embedded hello world, in pure Mojo.

Toggles the Pico's on-board LED (GPIO25) twice a second.
`mojo_main` is what the startup code (runtime/crt0.S) jumps to after
initializing RAM.
"""

import pico
from pico import Pin, pins, sleep_ms


@export("mojo_main")
def start() abi("C"):
    pico.init()

    var led = Pin[pins.LED]()
    
    led.make_output()

    while True:
        led.toggle()
        sleep_ms(250)
