"""On-target self-test suite, in pure Mojo.

Runs on the RP2040 and writes results into a RAM "mailbox" that the
host reads back over SWD (tools/hil.py). No wiring needed: the GPIO
tests use internal loopback (pad input-enable is on by default).

Mailbox layout (base 0x2003_0000):
  +0x00  magic       0x4D4F4A4F  ("MOJO")
  +0x04  status      1 = running, 2 = done
  +0x08  test count
  +0x0C  heartbeat   increments forever after the suite finishes
  +0x20  result[i]   0x600D0001 = pass, 0xBAD00001 = fail
"""

import pico
import pico.adc as adc
from pico.sync import Spinlock
import pico.irq as irq
import pico.multicore as multicore
import pico.rtt as rtt
import pico.uart as uart
from pico.pwm import Pwm
from pico import Drive, Event, Function, Pin, sleep_us, time_us
from pico.mmio import read8, read32, write32
from pico.time import alarm0_ack, alarm0_arm
from pico.pio import Asm, StateMachine
from pico.rp2040 import (
    PADS_DRIVE_LSB,
    PADS_DRIVE_MASK,
    PADS_SCHMITT,
    SIO_GPIO_IN,
)


comptime MAILBOX: UInt32 = 0x2003_0000
comptime MAGIC: UInt32 = 0x4D4F_4A4F
comptime STATUS_RUNNING: UInt32 = 1
comptime STATUS_DONE: UInt32 = 2
comptime RESULT_BASE: UInt32 = MAILBOX + 0x20
comptime PASS: UInt32 = 0x600D_0001
comptime FAIL: UInt32 = 0xBAD0_0001
comptime NUM_TESTS: UInt32 = 26


def report(idx: UInt32, ok: Bool):
    if ok:
        write32(RESULT_BASE + idx * 4, PASS)
    else:
        write32(RESULT_BASE + idx * 4, FAIL)


def test_u32_arithmetic() -> Bool:
    var a: UInt32 = 0xFFFF_FFFF
    var wrapped = a + 1  # modular arithmetic must wrap to 0
    var c: UInt32 = 1_000_003
    return wrapped == 0 and (a >> 31) == 1 and c * 3 - c * 2 == c


def test_division() -> Bool:
    # u32 division lowers to __aeabi_uidiv: exercises the libgcc link.
    var n: UInt32 = 1_000_000
    var d: UInt32 = 997
    var q = n // d
    var r = n % d
    return q * d + r == n and r < d


def test_u64() -> Bool:
    # 64-bit ops on a 32-bit core (register pairs / libgcc helpers).
    var x: UInt64 = 0x1_0000_0001
    var y = x * 3
    return y == 0x3_0000_0003 and (y >> 32) == 3 and (y & 0xFFFF_FFFF) == 3


def test_float32() -> Bool:
    # Cortex-M0+ has no FPU: this exercises libgcc soft-float.
    var a: Float32 = 1.5
    var b: Float32 = 2.25
    return a + b == 3.75 and a * b == 3.375 and b > a


def test_simd() -> Bool:
    # Mojo SIMD on an MCU (LLVM scalarizes <4 x i32> for M0+).
    var v = SIMD[DType.uint32, 4](1, 2, 3, 4)
    var w = v * 2
    return w.reduce_add() == 20 and w[3] == 8 and w.reduce_max() == 8


def test_comptime_unroll() -> Bool:
    var acc: UInt32 = 0
    comptime for i in range(8):
        acc += UInt32(1 << i)
    return acc == 255


def wait_level[N: Int](pin: Pin[N], expect: Bool) -> Bool:
    """Poll until the pad reads `expect` (input synchronizer = 2 clk_sys,
    plus rise time on loaded pads like the LED pin). 100 µs is orders of
    magnitude more than a healthy pad needs."""
    var start = time_us()
    while time_us() - start < 100:
        if pin.read() == expect:
            return True
    return False


def test_gpio_loopback[N: Int]() -> Bool:
    var pin = Pin[N]()
    pin.make_output()
    pin.high()
    var hi = wait_level(pin, True)
    pin.low()
    var lo = wait_level(pin, False)
    return hi and lo


def test_timer() -> Bool:
    var t0 = time_us()
    sleep_us(1000)
    var dt = time_us() - t0
    return dt >= 1000 and dt <= 1500


def test_pulls() -> Bool:
    # A floating input pin must follow the internal pull resistors.
    var pin = Pin[16]()  # unconnected header pin
    pin.make_input()
    pin.pull_up()
    sleep_us(10)
    var pulled_high = pin.read()
    pin.pull_down()
    sleep_us(10)
    var pulled_low = not pin.read()
    pin.pull_none()
    return pulled_high and pulled_low


def test_output_disable() -> Bool:
    # OD overrides the driver: with pull-down, the pad must read low
    # even though SIO drives high.
    var pin = Pin[14]()
    pin.make_output()
    pin.high()
    pin.pull_down()
    pin.output_disable(True)
    sleep_us(10)
    var forced_low = not pin.read()
    pin.output_disable(False)
    sleep_us(10)
    var driving_again = pin.read()
    pin.pull_none()
    pin.low()
    return forced_low and driving_again


def test_edge_events() -> Bool:
    var pin = Pin[13]()
    pin.make_output()
    pin.low()
    sleep_us(5)
    pin.ack_events(Event.ALL)
    if (pin.events() & Event.EDGE_HIGH) != 0:
        return False  # must be clear after ack
    pin.high()
    sleep_us(5)
    var latched = (pin.events() & Event.EDGE_HIGH) != 0
    pin.ack_events(Event.EDGE_HIGH)
    var cleared = (pin.events() & Event.EDGE_HIGH) == 0
    var level = (pin.events() & Event.LEVEL_HIGH) != 0
    pin.low()
    return latched and cleared and level


def test_funcsel_roundtrip() -> Bool:
    var pin = Pin[12]()
    pin.set_function(Function.PWM)
    var is_pwm = pin.get_function() == Function.PWM
    pin.set_function(Function.SIO)
    var back = pin.get_function() == Function.SIO
    return is_pwm and back


def test_pad_config() -> Bool:
    var pin = Pin[11]()
    pin.set_drive(Drive.MA_12)
    pin.schmitt(False)
    var cfg = pin.pad_config()
    var drive_ok = (cfg & PADS_DRIVE_MASK) >> PADS_DRIVE_LSB == Drive.MA_12
    var schmitt_off = (cfg & PADS_SCHMITT) == 0
    pin.set_drive(Drive.MA_4)  # restore reset defaults
    pin.schmitt(True)
    return drive_ok and schmitt_off


def test_pio() -> Bool:
    # A 4-instruction PIO program toggles GP17; the CPU counts edges.
    var pin = Pin[17]()
    pin.set_function(Function.PIO0)

    var asm = Asm()
    var top = asm.label()
    asm.set_pindirs(1)
    asm.set_pins(1)
    asm.set_pins(0)
    asm.jmp(top)

    var sm = StateMachine[0, 1]()
    sm.load(asm)
    sm.set_set_pins(17, 1)
    sm.set_clkdiv(1200)  # 12 MHz / 1200 = 10k instr/s -> ~0.4 ms period
    sm.enable()

    var last = pin.read()
    var edges: UInt32 = 0
    var start = time_us()
    while time_us() - start < 3000:
        var now = pin.read()
        if now != last:
            edges += 1
            last = now
    sm.disable()
    pin.set_function(Function.SIO)
    return edges >= 6


comptime IRQ_COUNTER: UInt32 = 0x2002_4000  # scratch word, outside mailbox


@export("isr_irq0")
def on_alarm0() abi("C"):
    # TIMER_IRQ_0 vector: ack the alarm, bump the counter.
    alarm0_ack()
    write32(IRQ_COUNTER, read32(IRQ_COUNTER) + 1)


def test_timer_irq() -> Bool:
    # NVIC + vector dispatch: ALARM0 must call our exported isr_irq0
    # twice (one-shot alarm re-armed once), asynchronously to this loop.
    write32(IRQ_COUNTER, 0)
    irq.clear_pending(irq.TIMER_IRQ_0)
    irq.enable(irq.TIMER_IRQ_0)
    alarm0_arm(500)
    var t0 = time_us()
    while read32(IRQ_COUNTER) < 1:
        if time_us() - t0 > 5000:
            irq.disable(irq.TIMER_IRQ_0)
            return False
    alarm0_arm(500)
    t0 = time_us()
    while read32(IRQ_COUNTER) < 2:
        if time_us() - t0 > 5000:
            irq.disable(irq.TIMER_IRQ_0)
            return False
    irq.disable(irq.TIMER_IRQ_0)
    return True


def test_rtt() -> Bool:
    # The control block + message are also verified host-side over SWD
    # (hil.check_rtt); here we check the target-visible state.
    rtt.init()
    rtt.write("RTT self-test\n")
    var wroff_ok = read32(rtt.RTT_BASE + 36) == 14
    var first = read8(rtt.BUF) == 0x52  # 'R'
    var magic_ok = read32(rtt.RTT_BASE) == 0x4747_4553  # "SEGG"
    return wroff_ok and first and magic_ok


comptime GPIO_IRQ_COUNT: UInt32 = 0x2002_4004
comptime CORE1_FLAG: UInt32 = 0x2002_4008
comptime CORE1_HEART: UInt32 = 0x2002_400C
comptime CORE1_JOB: UInt32 = 0x2002_401C  # selects mojo_core1_main behavior
comptime SHARED_CTR: UInt32 = 0x2002_4020
comptime CORE1_DONE: UInt32 = 0x2002_4024
comptime LOCKED_INCS: UInt32 = 20_000


@export("isr_irq13")
def on_gpio_irq() abi("C"):
    # IO_IRQ_BANK0 vector: count rising edges on GPIO15, ack the latch.
    var p = Pin[15]()
    if (p.irq_status() & Event.EDGE_HIGH) != 0:
        write32(GPIO_IRQ_COUNT, read32(GPIO_IRQ_COUNT) + 1)
    p.ack_events(Event.EDGE_HIGH | Event.EDGE_LOW)


def test_gpio_irq() -> Bool:
    # Internal loopback: driving the pin from SIO must raise the edge
    # event, route through IO_IRQ_BANK0 and dispatch our handler twice.
    var p = Pin[15]()
    p.make_output()
    p.low()
    sleep_us(10)
    p.ack_events(Event.ALL)
    write32(GPIO_IRQ_COUNT, 0)
    p.irq_enable(Event.EDGE_HIGH)
    irq.enable(irq.IO_IRQ_BANK0)
    var ok = True
    p.high()
    var t0 = time_us()
    while read32(GPIO_IRQ_COUNT) < 1:
        if time_us() - t0 > 5000:
            ok = False
            break
    if ok:
        p.low()
        sleep_us(10)
        p.high()
        t0 = time_us()
        while read32(GPIO_IRQ_COUNT) < 2:
            if time_us() - t0 > 5000:
                ok = False
                break
    p.irq_disable(Event.ALL)
    irq.disable(irq.IO_IRQ_BANK0)
    return ok


def test_pwm() -> Bool:
    # 12 kHz, 50% duty on GPIO15; the pad state is read back through
    # GPIO_IN (input enable is on), the counter must move.
    var pwm = Pwm[15]()
    pwm.set_div_int(1)
    pwm.set_top(999)
    pwm.set_level(500)
    pwm.enable()
    var moving = False
    var c0 = pwm.counter()
    for _ in range(10):
        sleep_us(37)
        if pwm.counter() != c0:
            moving = True
    # NOTE: constructing Pin[15]() here would reset funcsel to SIO and
    # kill the PWM output — sample the pad through SIO_GPIO_IN directly.
    var saw_hi = False
    var saw_lo = False
    var t0 = time_us()
    while time_us() - t0 < 1000:
        if (read32(SIO_GPIO_IN) >> 15) & 1 != 0:
            saw_hi = True
        else:
            saw_lo = True
    pwm.disable()
    var pin = Pin[15]()  # restores FUNCSEL_SIO
    _ = pin
    return moving and saw_hi and saw_lo


def test_adc_temp() -> Bool:
    # Channel 4 = die temperature sensor: plausible reading, stable
    # across two conversions. V_sense(27 C) = 0.706 V -> raw = ~876.
    adc.init()
    var mc = adc.read_temp_milli_c()
    var r1 = adc.read(4)
    var r2 = adc.read(4)
    var diff = r1 - r2 if r1 >= r2 else r2 - r1
    return (
        mc > 5_000 and mc < 70_000
        and r1 > 500 and r1 < 1500
        and diff < 100
    )


def test_uart_loopback() -> Bool:
    # PL011 internal loopback (LBE): TX->RX round trip, zero wiring.
    uart.init(115_200)
    uart.loopback(True)
    uart.write_byte(0xA5)
    uart.write_byte(0x3C)
    var a = uart.read_byte(2000)
    var b = uart.read_byte(2000)
    var empty = uart.read_byte(200) == -1
    uart.loopback(False)
    return a == 0xA5 and b == 0x3C and empty


def _locked_increments():
    var lock = Spinlock[0]()
    for _ in range(Int(LOCKED_INCS)):
        lock.acquire()
        write32(SHARED_CTR, read32(SHARED_CTR) + 1)
        lock.release()


@export("mojo_core1_main")
def core1_main() abi("C"):
    # Runs on core 1. Each launch() PSM-resets this core, so the tests
    # select a fresh behavior through the volatile CORE1_JOB word.
    var job = read32(CORE1_JOB)
    if job == 2:
        # contend on the shared counter under hardware spinlock 0
        _locked_increments()
        write32(CORE1_DONE, 0xD0E_0002)
        while True:
            pass
    elif job == 3:
        # FIFO echo: reply v+1 to everything core 0 sends
        while True:
            var r = multicore.fifo_pop(1_000_000)
            if r[0]:
                _ = multicore.fifo_push(r[1] + 1, 1_000_000)
    else:
        # default: raise the flag, then heartbeat forever
        write32(CORE1_FLAG, 0xC0DE_0001)
        while True:
            write32(CORE1_HEART, read32(CORE1_HEART) + 1)


def test_pio_sideset() -> Bool:
    # Forward label + side-set: instruction 0 forward-jumps over a
    # poison instruction (which would drive the SET pin high forever);
    # the loop toggles GP17 purely through side-set. Encoding checks
    # run first, then the pin must actually move.
    var pin = Pin[17]()
    pin.set_function(Function.PIO0)

    var asm = Asm()
    asm.side_set(1)
    var skip = asm.future()
    asm.jmp(skip, side=0)      # 0: forward jump (fixed up at bind)
    asm.set_pins(1, side=1)    # 1: skipped poison
    asm.bind(skip)
    asm.nop(side=1, delay=2)   # 2: pin high
    asm.jmp(0, side=0, delay=2)  # 3: pin low, loop through 0

    if asm.unresolved() != 0:
        return False
    if (Int(asm.code[0]) & 0x1F) != 2:  # fixup patched to address 2
        return False
    if (Int(asm.code[2]) & 0x1F00) != 0x1200:  # side=1 (bit12), delay=2
        return False

    var sm = StateMachine[0, 2]()
    sm.load(asm)
    sm.set_sideset_pins(17)
    sm.set_set_pins(17, 1)
    sm.exec(0xE081)  # set pindirs, 1 — output enable under SM control
    sm.set_clkdiv(1200)
    sm.enable()

    var last = pin.read()
    var edges: UInt32 = 0
    var start = time_us()
    while time_us() - start < 3000:
        var now = pin.read()
        if now != last:
            edges += 1
            last = now
    sm.disable()
    pin.set_function(Function.SIO)
    # side-set toggling proves flow went 0 -> 2 -> 3 (poison skipped:
    # a stuck-high pin would produce no edges)
    return edges >= 6


def _ct_square() -> Asm:
    var a = Asm()
    a.side_set(1)
    a.nop(side=1, delay=3)
    a.nop(side=0, delay=3)
    return a^


def test_pio_comptime() -> Bool:
    # The program is assembled at COMPILE time: `comptime assert` makes
    # an invalid program a build error, and the two instruction words
    # below are flash constants, not runtime computation.
    comptime PROG = _ct_square()
    comptime assert PROG.len == 2, "program must be 2 instructions"
    comptime assert PROG.unresolved() == 0, "labels must all be bound"

    var pin = Pin[17]()
    pin.set_function(Function.PIO0)
    var sm = StateMachine[0, 3]()
    sm.load(PROG)
    sm.set_sideset_pins(17)
    sm.set_set_pins(17, 1)
    sm.exec(0xE081)  # set pindirs, 1
    sm.set_clkdiv(1200)
    sm.enable()

    var last = pin.read()
    var edges: UInt32 = 0
    var start = time_us()
    while time_us() - start < 3000:
        var now = pin.read()
        if now != last:
            edges += 1
            last = now
    sm.disable()
    pin.set_function(Function.SIO)
    return edges >= 6


def test_spinlock_contention() -> Bool:
    # Both cores do LOCKED_INCS read-modify-write increments on the same
    # RAM word under hardware spinlock 0. Any mutual-exclusion failure
    # loses updates and the total comes up short.
    write32(CORE1_JOB, 2)
    write32(CORE1_DONE, 0)
    write32(SHARED_CTR, 0)
    if not multicore.launch():
        return False
    _locked_increments()
    var t0 = time_us()
    while read32(CORE1_DONE) != 0xD0E_0002:
        if time_us() - t0 > 500_000:
            return False
    return read32(SHARED_CTR) == LOCKED_INCS * 2


def test_fifo_pingpong() -> Bool:
    # Core 1 echoes v+1 through the inter-core FIFO, five rounds.
    write32(CORE1_JOB, 3)
    if not multicore.launch():
        return False
    for i in range(5):
        var v = UInt32(0x1000 + i * 0x111)
        if not multicore.fifo_push(v, 100_000):
            return False
        var r = multicore.fifo_pop(100_000)
        if not r[0] or r[1] != v + 1:
            return False
    return True


def test_multicore() -> Bool:
    # Bootrom FIFO handshake must start core 1 in Mojo code: flag set,
    # heartbeat advancing while core 0 watches.
    write32(CORE1_JOB, 1)
    write32(CORE1_FLAG, 0)
    write32(CORE1_HEART, 0)
    if not multicore.launch():
        return False
    var t0 = time_us()
    while read32(CORE1_FLAG) != 0xC0DE_0001:
        if time_us() - t0 > 100_000:
            return False
    var h1 = read32(CORE1_HEART)
    sleep_us(1000)
    return read32(CORE1_HEART) != h1


@export("mojo_main")
def start() abi("C"):
    pico.init()

    write32(MAILBOX + 0x00, MAGIC)
    write32(MAILBOX + 0x04, STATUS_RUNNING)
    write32(MAILBOX + 0x08, NUM_TESTS)

    report(0, test_u32_arithmetic())
    report(1, test_division())
    report(2, test_u64())
    report(3, test_float32())
    report(4, test_simd())
    report(5, test_comptime_unroll())
    report(6, test_gpio_loopback[15]())  # free pin, nothing attached
    report(7, test_gpio_loopback[25]())  # the LED pin
    report(8, test_timer())
    report(9, test_pulls())
    report(10, test_output_disable())
    report(11, test_edge_events())
    report(12, test_funcsel_roundtrip())
    report(13, test_pad_config())
    report(14, test_pio())
    report(15, test_timer_irq())
    report(16, test_rtt())
    report(17, test_gpio_irq())
    report(18, test_pwm())
    report(19, test_adc_temp())
    report(20, test_uart_loopback())
    report(21, test_pio_sideset())
    report(22, test_pio_comptime())
    report(23, test_spinlock_contention())
    report(24, test_fifo_pingpong())
    report(25, test_multicore())  # last: leaves core 1 heartbeating

    write32(MAILBOX + 0x04, STATUS_DONE)

    # Fast blink + heartbeat: proves the firmware is still alive.
    var led = Pin[25]()
    led.make_output()
    var beats: UInt32 = 0
    while True:
        write32(MAILBOX + 0x0C, beats)
        beats += 1
        led.toggle()
        sleep_us(100_000)
