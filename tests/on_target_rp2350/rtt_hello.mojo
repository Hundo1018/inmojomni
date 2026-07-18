"""RTT on the RP2350: stream a known message while running.

The host side (tools/rtt_rp2350.mojo) attaches openocd to the RUNNING
RISC-V cores, points its RTT engine at the control block and asserts
the banner arrives. Works because the Hazard3 DM allows memory access
while the harts run (verified: `mdw` with state `running`).
"""

from pico.pico2 import init, init_timer, sleep_us
import pico.rtt as rtt


@export("mojo_main")
def start() abi("C"):
    init()
    init_timer()
    rtt.init()
    rtt.write("RTT-RV32 hello from the Pico 2\n")
    var n: UInt32 = 0
    while True:
        rtt.write("tick ")
        rtt.write_u32(n)
        rtt.write("\n")
        n += 1
        sleep_us(100_000)
