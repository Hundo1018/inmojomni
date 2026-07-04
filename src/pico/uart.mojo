"""UART0 driver (ARM PL011), polled.

clk_peri is switched to clk_sys (12 MHz XOSC in this project), which
bounds usable baud rates at 12 MHz / 16 = 750 kBd. The peripheral's
internal loopback mode (LBE) lets the test suite verify TX->RX framing
with zero wiring.

    import pico.uart as uart

    uart.init(115_200)
    uart.write_byte(0xA5)
    var b = uart.read_byte(1000)   # -1 on timeout
"""

from pico.mmio import read32, write32, write32_clr, write32_set
from pico.rp2040 import (
    CLK_ENABLE,
    CLK_PERI_CTRL,
    RESET_UART0,
    RESETS_RESET,
    RESETS_RESET_DONE,
    UART0_CR,
    UART0_DR,
    UART0_FBRD,
    UART0_FR,
    UART0_IBRD,
    UART0_LCR_H,
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


def init(baud: UInt32):
    """8N1 at `baud`, FIFOs on, TX+RX enabled. Route pins yourself if
    you need them (pins.UART0_TX/RX + Function.UART); loopback tests
    need no pins at all."""
    write32(CLK_PERI_CTRL, CLK_ENABLE)  # AUXSRC 0 = clk_sys
    write32_clr(RESETS_RESET, RESET_UART0)
    while (read32(RESETS_RESET_DONE) & RESET_UART0) == 0:
        pass
    # 16.6 fixed-point divisor, rounded to the nearest 1/64
    var div64 = (UInt64(CLK_PERI_HZ) * 64 + UInt64(8) * UInt64(baud)) // (
        UInt64(16) * UInt64(baud)
    )
    write32(UART0_IBRD, UInt32(div64 >> 6))
    write32(UART0_FBRD, UInt32(div64 & 0x3F))
    # LCR_H write latches the baud divisors; keep it after IBRD/FBRD.
    write32(UART0_LCR_H, UART_LCR_WLEN8 | UART_LCR_FEN)
    write32(UART0_CR, UART_CR_UARTEN | UART_CR_TXE | UART_CR_RXE)


def loopback(enable: Bool):
    """PL011 internal TX->RX loopback (LBE): zero-wire self-test mode.
    The TRM forbids changing CR while the UART is enabled/busy, so this
    drains, disables, flips LBE, then re-enables."""
    while (read32(UART0_FR) & UART_FR_BUSY) != 0:
        pass
    var cr = read32(UART0_CR)
    write32(UART0_CR, cr & ~UART_CR_UARTEN)
    if enable:
        cr |= UART_CR_LBE
    else:
        cr &= ~UART_CR_LBE
    write32(UART0_CR, cr & ~UART_CR_UARTEN)
    write32(UART0_CR, cr | UART_CR_UARTEN)
    if enable:
        # Until now the receiver was sampling the unrouted (low) pad
        # and has collected break garbage — flush it. read_byte keeps
        # the volatile pops alive (its value is compared; a bare
        # `_ = read32(DR)` would be elaborated away entirely).
        while read_byte(300) != -1:
            pass


def write_byte(b: UInt8):
    while (read32(UART0_FR) & UART_FR_TXFF) != 0:
        pass
    write32(UART0_DR, UInt32(b))


def flush():
    while (read32(UART0_FR) & UART_FR_BUSY) != 0:
        pass


def read_byte(timeout_us: UInt32) -> Int32:
    """Next received byte, or -1 if none arrives within the timeout."""
    var t0 = time_us()
    while (read32(UART0_FR) & UART_FR_RXFE) != 0:
        if time_us() - t0 > timeout_us:
            return -1
    return Int32(Int(read32(UART0_DR) & 0xFF))
