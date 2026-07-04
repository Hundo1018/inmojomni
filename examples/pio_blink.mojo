"""Blink, but the CPU doesn't do the blinking.

The PIO coprocessor runs a 7-instruction program that toggles the LED
forever; after setup the CPU has literally nothing left to do.

Build + flash:  pixi run python tools/build.py --flash examples/pio_blink.mojo
"""

import pico
from pico import Function, Pin, pins
from pico.pio import Asm, StateMachine


@export("mojo_main")
def start() abi("C"):
    pico.init()

    # Hand the LED pad to PIO0.
    Pin[pins.LED]().set_function(Function.PIO0)

    # PIO program: on, burn cycles, off, burn cycles, repeat.
    # At clkdiv 65535 one instruction ≈ 5.5 ms; each phase is
    # 2 + 30 * 3 = 92 instructions ≈ 0.5 s.
    var asm = Asm()
    var top = asm.label()
    asm.set_pindirs(1)
    asm.set_pins(1)
    asm.set_x(29)
    var on_wait = asm.label()
    asm.jmp_x_dec(on_wait, delay=2)
    asm.set_pins(0)
    asm.set_x(29)
    var off_wait = asm.label()
    asm.jmp_x_dec(off_wait, delay=2)
    asm.jmp(top)

    var sm = StateMachine[0, 0]()
    sm.load(asm)
    sm.set_set_pins(pins.LED, 1)
    sm.set_clkdiv(65535)
    sm.enable()

    while True:
        pass  # PIO owns the LED now
