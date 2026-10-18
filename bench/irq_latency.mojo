"""IRQ -> GPIO latency gate, Mojo side (mirror of bench/irq_latency.c).

What is measured
  Core 0 drives GPIO 15 high through SIO. The pad input is enabled, so
  the same pin is the interrupt source (internal loopback, no wiring):
  EDGE_HIGH -> IO_IRQ_BANK0 -> `isr_irq13`, whose first instruction
  drives GPIO 16 high (SIO), then acks the edge and counts the
  interrupt. PIO0 SM0, clocked at clk_sys = 125 MHz (PLL_SYS), waits
  for GPIO 15 to read high, then runs a 2-cycle `jmp pin / jmp x--`
  loop until GPIO 16 reads high and pushes the iteration count. Both
  pins reach the PIO through the same 2-stage input synchroniser, so
  the count is the pad-to-pad latency in units of 2 clk_sys cycles
  (16 ns), taken by hardware that is independent of the core:

      latency_cycles = 2 * count + 2      (mov + first jmp pin)

  The main loop spins on the handler's counter in SRAM (single-cycle
  reads, so the pending interrupt is not held off by a stalled APB
  access), then pops the FIFO, lowers both pins and pauses 5 µs. The
  handler writes registers directly (SIO OUT_SET, IO_BANK0 INTR1): the
  C firmware executes the same three stores in the same order.

  Built twice by tools/irq_latency.mojo: handler in XIP flash (default)
  and handler in SRAM (`build.mojo --ramfunc isr_irq13`).

Mailbox (0x2003_0000):
  +0x00 magic 0x4952_514C ("IRQL")      +0x04 status 1 run / 2 done / 3 err
  +0x08 N per run                        +0x0C runs
  +0x10 language id (1 Mojo, 2 C gcc, 3 C clang)
  +0x14 clk_sys in kHz (frequency counter FC0 against the 12 MHz XOSC)
  +0x18 first sample (run 0, iteration 0: cold caches)
  +0x1C total interrupts taken (must equal N * runs)
  +0x20 error code (0 ok; 1 handler never ran; 2 PIO never pushed)
  +0x30 + 12*r: run r {min, max, sum} of the count
  +0x60 PIO program length, +0x64.. program words
  0x2001_0000: the N counts of the last run (host recomputes min/avg/max)
"""

import pico
import pico.clocks as clocks
import pico.irq as irq
from pico import Event, Pin, sleep_us
from pico.mmio import read32, write32
from pico.pio import Asm, StateMachine
from pico.rp2040 import IO_BANK0_BASE, SIO_GPIO_OUT_SET

comptime PIN_A = 15  # driven by core 0; its own EDGE_HIGH source
comptime PIN_C = 16  # driven by the interrupt handler
comptime N: UInt32 = 10_000
comptime RUNS = 3
comptime LANG_ID: UInt32 = 1

comptime MB: UInt32 = 0x2003_0000
comptime MAGIC: UInt32 = 0x4952_514C
comptime SAMPLES: UInt32 = 0x2001_0000
comptime IRQ_COUNT: UInt32 = 0x2002_4000  # scratch word, outside mailbox

# IO_BANK0 INTR1 covers GPIO 8..15, 4 event bits per pin: EDGE_HIGH of
# GPIO 15 is bit 3 + 4 * 7 = 31.
comptime INTR1: UInt32 = IO_BANK0_BASE + 0xF4
comptime A_EDGE_HIGH: UInt32 = UInt32(1) << 31
comptime C_MASK: UInt32 = UInt32(1) << PIN_C


@export("isr_irq13")
def on_gpio_irq() abi("C"):
    write32(SIO_GPIO_OUT_SET, C_MASK)  # first instruction: GPIO 16 high
    write32(INTR1, A_EDGE_HIGH)  # ack the latched edge
    write32(IRQ_COUNT, read32(IRQ_COUNT) + 1)


def program() -> Asm:
    var a = Asm()
    a.wait_gpio(0, PIN_A)  # 0: arm -- the previous pulse is over
    a.wait_gpio(1, PIN_A)  # 1: rising edge of the interrupt input
    a.mov_x_not_null()  # 2: x = 0xFFFFFFFF
    var loop = a.label()
    var done = a.future()
    a.jmp_pin(done)  # 3: GPIO 16 high -> done
    a.jmp_x_dec(loop)  # 4: else x--, loop (2 cycles per iteration)
    a.bind(done)
    a.in_x(32)  # 5: isr = x
    a.push_block()  # 6: RX FIFO <- x (count = ~x); wrap to 0
    return a^


def fail(code: UInt32):
    write32(MB + 0x20, code)
    write32(MB + 0x04, 3)
    while True:
        pass


@export("mojo_main")
def start() abi("C"):
    pico.init()
    write32(MB + 0x00, MAGIC)
    write32(MB + 0x04, 1)
    write32(MB + 0x08, N)
    write32(MB + 0x0C, RUNS)
    write32(MB + 0x10, LANG_ID)
    write32(MB + 0x1C, 0)
    write32(MB + 0x20, 0)
    clocks.sys_clock_125mhz()
    write32(MB + 0x14, clocks.measure_khz(clocks.FC_CLK_SYS))

    var a = Pin[PIN_A]()
    a.make_output()
    a.low()
    var c = Pin[PIN_C]()
    c.make_output()
    c.low()

    var sm = StateMachine[0, 0]()
    var prog = program()
    sm.load(prog)
    sm.set_clkdiv(1)
    sm.set_jmp_pin(PIN_C)
    write32(MB + 0x60, UInt32(prog.len))
    for i in range(prog.len):
        write32(MB + 0x64 + UInt32(i) * 4, UInt32(prog.code[i]))
    sm.enable()

    write32(IRQ_COUNT, 0)
    a.ack_events(Event.ALL)
    a.irq_enable(Event.EDGE_HIGH)
    irq.enable(irq.IO_IRQ_BANK0)
    sleep_us(10)

    var total: UInt32 = 0
    for r in range(RUNS):
        var mn: UInt32 = 0xFFFF_FFFF
        var mx: UInt32 = 0
        var sum: UInt32 = 0
        var i: UInt32 = 0
        while i < N:
            total += 1
            a.high()
            var spins: UInt32 = 0
            while read32(IRQ_COUNT) != total:
                spins += 1
                if spins > 1_000_000:
                    fail(1)
            spins = 0
            while sm.rx_empty():
                spins += 1
                if spins > 1_000_000:
                    fail(2)
            var n = ~sm.rx_pull()
            c.low()
            a.low()
            if n < mn:
                mn = n
            if n > mx:
                mx = n
            sum += n
            if r == RUNS - 1:
                write32(SAMPLES + i * 4, n)
            if r == 0 and i == 0:
                write32(MB + 0x18, n)
            sleep_us(5)
            i += 1
        var base = MB + 0x30 + UInt32(r) * 12
        write32(base, mn)
        write32(base + 4, mx)
        write32(base + 8, sum)

    irq.disable(irq.IO_IRQ_BANK0)
    a.irq_disable(Event.ALL)
    write32(MB + 0x1C, total)
    write32(MB + 0x04, 2)

    var led = Pin[25]()
    led.make_output()
    while True:
        led.toggle()
        sleep_us(250_000)
