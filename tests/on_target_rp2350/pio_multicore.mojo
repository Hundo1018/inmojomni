"""PIO + dual-core proof on RP2350 silicon, over the flash-mailbox loop.

Dual-core: core 0 wakes core 1 through the bootrom SIO-FIFO handshake
(RISC-V flavour: mtvec + h3.unblock, see crt0_rv32.S / pico.multicore).
Core 1 computes 1000 xorshift32 rounds, parks the result in volatile
RAM and pushes it over the FIFO; core 0 reports both paths. The host
recomputes the expected value — a wrong word from either path fails.

PIO: state machine 0 of PIO0 and of PIO2 (the RP2350-only third block)
runs a 4-instruction square-wave program on GPIO15 while the CPU counts
edges through the pad's input path (SIO GPIO_IN) — an electrical
read-back, not a register echo. clkdiv 1200 at ROSC (~11 MHz) gives a
wave period of ~0.4 ms; ~18 ms of sampling must see many edges.

Mailbox ("PMC1", 4 pairs):
  0 (launch ok, fifo ok)   1 (fifo value, RAM value)  == host xorshift
  2 (PIO0 edges, pass)     3 (PIO2 edges, pass)       pass = edges >= 6
"""

from std.ffi import external_call

from pico.gpio import Function
from pico.mmio import read32, write32
from pico.pico2 import (
    Pin,
    StateMachine,
    fifo_pop,
    fifo_push,
    halt_core1,
    init,
    launch_core1,
)
from pico.pio import Asm

comptime MB: UInt32 = 0x2003_0000
comptime MAGIC: UInt32 = 0x31434D50  # "PMC1"
comptime COUNT: UInt32 = 4
comptime C1_RESULT: UInt32 = 0x2002_4000  # scratch word, outside mailbox
comptime C1_SEED: UInt32 = 0x1357_2468
comptime MB_FLASH_OFF: UInt32 = 0x003F_F000


@always_inline
def _cyc() -> UInt32:
    return external_call["read_mcycle", UInt32]()


@export("mojo_core1_main")
def core1() abi("C"):
    var x: UInt32 = C1_SEED
    for _ in range(1000):
        x ^= x << 13
        x ^= x >> 17
        x ^= x << 5
    write32(C1_RESULT, x)
    _ = fifo_push(x, 100_000)
    while True:
        pass


def pio_edges[P: Int]() -> Tuple[UInt32, UInt32]:
    var pin = Pin[15]()
    pin.make_output()  # SIO OE + un-ISOlate the pad (RP2350)
    pin.input_enable(True)
    pin.set_function(UInt32(6 + P))  # FUNCSEL: PIO0=6, PIO1=7, PIO2=8

    var asm = Asm()
    var top = asm.label()
    asm.set_pindirs(1)
    asm.set_pins(1)
    asm.set_pins(0)
    asm.jmp(top)

    var sm = StateMachine[P, 0]()
    sm.load(asm)
    sm.set_set_pins(15, 1)
    sm.set_clkdiv(1200)  # ~11 MHz / 1200 -> ~9k instr/s, ~0.4 ms period
    sm.enable()

    var last = pin.read()
    var edges: UInt32 = 0
    var t0 = _cyc()
    while _cyc() - t0 < 200_000:  # ~18 ms of sampling at ROSC speed
        var now = pin.read()
        if now != last:
            edges += 1
            last = now
    sm.disable()
    pin.set_function(Function.SIO)
    return (edges, UInt32(1) if edges >= 6 else UInt32(0))


def _report(idx: UInt32, r: Tuple[UInt32, UInt32]):
    var base = MB + 0x14 + idx * 8
    write32(base, r[0])
    write32(base + 4, r[1])


@export("mojo_main")
def start() abi("C"):
    init()
    write32(MB + 0x00, MAGIC)
    write32(MB + 0x04, 1)
    write32(MB + 0x08, COUNT)
    write32(MB + 0x0C, 1)
    write32(MB + 0x10, 0)
    write32(C1_RESULT, 0)  # RAM survives soft resets: clear before use

    # LED breadcrumbs: at a hang the steady LED state names the stage
    # (ON = launch/PIO2, OFF = PIO0/commit).
    var led = Pin[25]()
    led.make_output()

    led.high()  # stage: core 1 launch
    var ok = launch_core1()
    var r = fifo_pop(100_000)
    _report(0, (UInt32(1) if ok else UInt32(0), UInt32(1) if r[0] else UInt32(0)))
    _report(1, (r[1], read32(C1_RESULT)))
    led.low()  # stage: PIO0
    _report(2, pio_edges[0]())
    led.high()  # stage: PIO2
    _report(3, pio_edges[2]())
    led.low()  # stage: commit

    halt_core1()  # core 1 must NOT be fetching from XIP during commit
    write32(MB + 0x04, 2)  # done
    external_call["flash_commit_reboot", NoneType](
        MB_FLASH_OFF, MB, UInt32(256), UInt32(0)
    )
    while True:  # unreachable
        pass
