"""UART0 driver (ARM PL011), polled — chip-generic.

clk_peri is switched to clk_sys (12 MHz XOSC in this project), which
bounds usable baud rates at 12 MHz / 16 = 750 kBd. The peripheral's
internal loopback mode (LBE) lets the test suite verify TX->RX framing
with zero wiring.

    import pico.uart as uart

    uart.init(115_200)
    uart.write_byte(0xA5)
    var b = uart.read_byte(1000)   # -1 on timeout
"""

from pico.chips import Chip, RP2040
from pico.mmio import read32, write32, write32_clr, write32_set
from pico.rp2040 import (
    CLK_ENABLE,
    UART_CR_LBE,
    UART_CR_RXE,
    UART_CR_TXE,
    UART_CR_UARTEN,
    UART_FR_BUSY,
    UART_FR_RXFE,
    UART_FR_TXFF,
    UART_LCR_FEN,
    UART_LCR_WLEN8,
)
from pico.time import time_us

comptime CLK_PERI_HZ: UInt32 = 12_000_000  # clk_sys = XOSC, no PLL
# PL011 register offsets (identical on both chips; bases differ)
comptime _DR: UInt32 = 0x00
comptime _FR: UInt32 = 0x18
comptime _IBRD: UInt32 = 0x24
comptime _FBRD: UInt32 = 0x28
comptime _LCR_H: UInt32 = 0x2C
comptime _CR: UInt32 = 0x30


def init[C: Chip = RP2040](baud: UInt32):
    """8N1 at `baud`, FIFOs on, TX+RX enabled. Route pins yourself if
    you need them (pins.UART0_TX/RX + Function.UART); loopback tests
    need no pins at all. clk_sys must be the 12 MHz XOSC (board init
    on the RP2040, `time.init[RP2350]()` on the Pico 2)."""
    write32(C.CLOCKS_BASE + 0x48, CLK_ENABLE)  # CLK_PERI: AUXSRC 0 = clk_sys
    write32_clr(C.RESETS_RESET, C.RESET_UART0)
    while (read32(C.RESETS_RESET_DONE) & C.RESET_UART0) == 0:
        pass
    # 16.6 fixed-point divisor, rounded to the nearest 1/64
    var div64 = (UInt64(CLK_PERI_HZ) * 64 + UInt64(8) * UInt64(baud)) // (
        UInt64(16) * UInt64(baud)
    )
    write32(C.UART0_BASE + _IBRD, UInt32(div64 >> 6))
    write32(C.UART0_BASE + _FBRD, UInt32(div64 & 0x3F))
    # LCR_H write latches the baud divisors; keep it after IBRD/FBRD.
    write32(C.UART0_BASE + _LCR_H, UART_LCR_WLEN8 | UART_LCR_FEN)
    write32(C.UART0_BASE + _CR, UART_CR_UARTEN | UART_CR_TXE | UART_CR_RXE)


def loopback[C: Chip = RP2040](enable: Bool):
    """PL011 internal TX->RX loopback (LBE): zero-wire self-test mode.
    The TRM forbids changing CR while the UART is enabled/busy, so this
    drains, disables, flips LBE, then re-enables."""
    while (read32(C.UART0_BASE + _FR) & UART_FR_BUSY) != 0:
        pass
    var cr = read32(C.UART0_BASE + _CR)
    write32(C.UART0_BASE + _CR, cr & ~UART_CR_UARTEN)
    if enable:
        cr |= UART_CR_LBE
    else:
        cr &= ~UART_CR_LBE
    write32(C.UART0_BASE + _CR, cr & ~UART_CR_UARTEN)
    write32(C.UART0_BASE + _CR, cr | UART_CR_UARTEN)
    if enable:
        # Until now the receiver was sampling the unrouted (low) pad
        # and has collected break garbage — flush it. read_byte keeps
        # the volatile pops alive (its value is compared; a bare
        # `_ = read32(DR)` would be elaborated away entirely).
        while read_byte[C](300) != -1:
            pass


def write_byte[C: Chip = RP2040](b: UInt8):
    while (read32(C.UART0_BASE + _FR) & UART_FR_TXFF) != 0:
        pass
    write32(C.UART0_BASE + _DR, UInt32(b))


def flush[C: Chip = RP2040]():
    while (read32(C.UART0_BASE + _FR) & UART_FR_BUSY) != 0:
        pass


def read_byte[C: Chip = RP2040](timeout_us: UInt32) -> Int32:
    """Next received byte, or -1 if none arrives within the timeout."""
    var t0 = time_us[C]()
    while (read32(C.UART0_BASE + _FR) & UART_FR_RXFE) != 0:
        if time_us[C]() - t0 > timeout_us:
            return -1
    return Int32(Int(read32(C.UART0_BASE + _DR) & 0xFF))
