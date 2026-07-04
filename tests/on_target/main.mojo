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
import pico.irq as irq
import pico.rtt as rtt
from pico import Drive, Event, Function, Pin, sleep_us, time_us
from pico.mmio import read8, read32, write32
from pico.time import alarm0_ack, alarm0_arm
from pico.pio import Asm, StateMachine
from pico.rp2040 import PADS_DRIVE_LSB, PADS_DRIVE_MASK, PADS_SCHMITT


comptime MAILBOX: UInt32 = 0x2003_0000
comptime MAGIC: UInt32 = 0x4D4F_4A4F
comptime STATUS_RUNNING: UInt32 = 1
comptime STATUS_DONE: UInt32 = 2
comptime RESULT_BASE: UInt32 = MAILBOX + 0x20
comptime PASS: UInt32 = 0x600D_0001
comptime FAIL: UInt32 = 0xBAD0_0001
comptime NUM_TESTS: UInt32 = 17


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
