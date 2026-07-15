# EXPECT-ERROR: GPIO number out of range
#
# Pin numbers are compile-time parameters; an out-of-range pin must be
# rejected by `comptime assert`, not discovered on the board. Pin[30] is
# invalid on the default chip (RP2040, GPIO0..GPIO29).

from pico.gpio import Pin


@export("mojo_main")
def start() abi("C"):
    var p = Pin[30]()  # RP2040 has no GPIO30
    p.make_output()
