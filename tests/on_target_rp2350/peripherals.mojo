"""RP2350 peripheral proofs: hardware TIMER, PWM, ADC, UART.

Runs after `pico.pico2.init_timer()` — XOSC started, clk_ref/clk_sys
at 12 MHz, TICKS feeding TIMER0 at 1 MHz. With clk_sys on the crystal,
mcycle runs at exactly 12 MHz, which turns the timer test into a hard
ratio gate instead of a hand-wave: cycles per microsecond must be 12.

Results leave through the flash mailbox (see crt0_rv32.S), read back
over PICOBOOT — no probe, no button.

Mailbox ("PER1", 5 pairs):
  0 (timer µs delta, mcycle delta)      host: ratio == 12 ±2%
  1 (pwm counter moving, in range)      host: (1, 1)
  2 (die temp milli-°C, raw ADC)        host: 5000..60000 m°C
  3 (uart loopback ok, echoed bytes)    host: (1, 0xA53C)
  4 (mcycle delta of sleep_us(10_000))  host: 120_000 ±2%
  5 (irq fired, isr call count)         host: (1, 1) — Xh3irq dispatch
"""

from std.ffi import external_call

from pico.mmio import read32, write32
from pico.pico2 import Pin, Pwm, init, init_timer, sleep_us, time_us
from pico.chips import RP2350
from pico.time import alarm0_ack, alarm0_arm
import pico.adc as adc
import pico.uart as uart
import pico.xh3irq as xh3irq

comptime MB: UInt32 = 0x2003_0000
comptime MAGIC: UInt32 = 0x31524550  # "PER1"
comptime COUNT: UInt32 = 6
comptime MB_FLASH_OFF: UInt32 = 0x003F_F000


@always_inline
def _cyc() -> UInt32:
    return external_call["read_mcycle", UInt32]()


def t_timer_rate() -> Tuple[UInt32, UInt32]:
    var t0 = time_us()
    var c0 = _cyc()
    sleep_us(50_000)
    var dt = time_us() - t0
    var dc = _cyc() - c0
    return (dt, dc)


def t_pwm() -> Tuple[UInt32, UInt32]:
    var pwm = Pwm[15]()
    pwm.set_top(999)
    pwm.set_div_int(1)
    pwm.set_level(500)
    pwm.enable()
    sleep_us(500)
    var c1 = pwm.counter()
    sleep_us(137)  # not a multiple of the 1000-tick wrap
    var c2 = pwm.counter()
    pwm.disable()
    var moving: UInt32 = 1 if c1 != c2 else 0
    var in_range: UInt32 = 1 if (c1 <= 999 and c2 <= 999) else 0
    return (moving, in_range)


def t_adc() -> Tuple[UInt32, UInt32]:
    adc.init[RP2350]()
    var raw = adc.read[RP2350](4)
    var mc = adc.read_temp_milli_c[RP2350]()
    return (UInt32(Int(mc)), raw)


def t_uart() -> Tuple[UInt32, UInt32]:
    uart.init[RP2350](115_200)
    uart.loopback[RP2350](True)
    uart.write_byte[RP2350](0xA5)
    var a = uart.read_byte[RP2350](10_000)
    uart.write_byte[RP2350](0x3C)
    var b = uart.read_byte[RP2350](10_000)
    var ok: UInt32 = 1 if (a == 0xA5 and b == 0x3C) else 0
    var got = (UInt32(Int(a & 0xFF)) << 8) | UInt32(Int(b & 0xFF))
    return (ok, got)


comptime IRQ_COUNTER: UInt32 = 0x2002_4000  # scratch, outside mailbox


@export("isr_riscv_extirq")
def isr(irq: UInt32) abi("C"):
    # level-sensitive: ack the TIMER first, then count the visit
    alarm0_ack[RP2350]()
    write32(IRQ_COUNTER, read32(IRQ_COUNTER) + 1)


def t_irq() -> Tuple[UInt32, UInt32]:
    write32(IRQ_COUNTER, 0)  # RAM survives soft resets: clear first
    xh3irq.enable(0)  # TIMER0_IRQ_0 (intctrl.h)
    xh3irq.global_enable()
    alarm0_arm[RP2350](1000)
    var t0 = time_us()
    while read32(IRQ_COUNTER) == 0 and time_us() - t0 < 100_000:
        pass
    var n = read32(IRQ_COUNTER)
    return (1 if n > 0 else 0, n)


def t_sleep() -> Tuple[UInt32, UInt32]:
    var c0 = _cyc()
    sleep_us(10_000)
    return (_cyc() - c0, 0)


def _report(idx: UInt32, r: Tuple[UInt32, UInt32]):
    var base = MB + 0x14 + idx * 8
    write32(base, r[0])
    write32(base + 4, r[1])


@export("mojo_main")
def start() abi("C"):
    init()
    init_timer()
    write32(MB + 0x00, MAGIC)
    write32(MB + 0x04, 1)
    write32(MB + 0x08, COUNT)
    write32(MB + 0x0C, 1)
    write32(MB + 0x10, 0)

    _report(0, t_timer_rate())
    _report(1, t_pwm())
    _report(2, t_adc())
    _report(3, t_uart())
    _report(4, t_sleep())
    _report(5, t_irq())

    write32(MB + 0x04, 2)  # done
    external_call["flash_commit_reboot", NoneType](
        MB_FLASH_OFF, MB, UInt32(256), UInt32(0)
    )
    while True:  # unreachable
        pass
