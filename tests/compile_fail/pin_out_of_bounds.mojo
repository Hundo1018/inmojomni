# EXPECT-ERROR: GPIO0..GPIO29
#
# Pin numbers are compile-time parameters; an out-of-range pin must be
# rejected by `comptime assert`, not discovered on the board.

from pico.gpio import Pin


@export("mojo_main")
def start() abi("C"):
    var p = Pin[30]()  # RP2040 has no GPIO30
    p.make_output()
