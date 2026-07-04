"""NVIC interrupt control (ARMv6-M) and RP2040 IRQ numbers.

Handler binding is static, at link time: export a C-ABI function named
`isr_irq<N>` and it replaces the weak vector-table slot in crt0.S. No
RAM vector table, no runtime registration, no function pointers — the
handler address is burned into the vector table like a hand-written C
SDK would do.

    import pico.irq as irq
    from pico.time import alarm0_ack, alarm0_arm

    @export("isr_irq0")           # TIMER_IRQ_0 vector
    def on_alarm0() abi("C"):
        alarm0_ack()
        ...

    irq.enable(irq.TIMER_IRQ_0)
    alarm0_arm(1000)              # fires in 1 ms
"""

from pico.mmio import read32, write32

# ARMv6-M NVIC (one 32-bit register bank each; RP2040 has 26 usable IRQs)
comptime NVIC_ISER: UInt32 = 0xE000_E100  # set-enable
comptime NVIC_ICER: UInt32 = 0xE000_E180  # clear-enable
comptime NVIC_ISPR: UInt32 = 0xE000_E200  # set-pending
comptime NVIC_ICPR: UInt32 = 0xE000_E280  # clear-pending

# RP2040 IRQ numbers (datasheet §2.3.2)
comptime TIMER_IRQ_0: UInt32 = 0
comptime TIMER_IRQ_1: UInt32 = 1
comptime TIMER_IRQ_2: UInt32 = 2
comptime TIMER_IRQ_3: UInt32 = 3
comptime PWM_IRQ_WRAP: UInt32 = 4
comptime USBCTRL_IRQ: UInt32 = 5
comptime XIP_IRQ: UInt32 = 6
comptime PIO0_IRQ_0: UInt32 = 7
comptime PIO0_IRQ_1: UInt32 = 8
comptime PIO1_IRQ_0: UInt32 = 9
comptime PIO1_IRQ_1: UInt32 = 10
comptime DMA_IRQ_0: UInt32 = 11
comptime DMA_IRQ_1: UInt32 = 12
comptime IO_IRQ_BANK0: UInt32 = 13
comptime IO_IRQ_QSPI: UInt32 = 14
comptime SIO_IRQ_PROC0: UInt32 = 15
comptime SIO_IRQ_PROC1: UInt32 = 16
comptime CLOCKS_IRQ: UInt32 = 17
comptime SPI0_IRQ: UInt32 = 18
comptime SPI1_IRQ: UInt32 = 19
comptime UART0_IRQ: UInt32 = 20
comptime UART1_IRQ: UInt32 = 21
comptime ADC_IRQ_FIFO: UInt32 = 22
comptime I2C0_IRQ: UInt32 = 23
comptime I2C1_IRQ: UInt32 = 24
comptime RTC_IRQ: UInt32 = 25


@always_inline
def enable(irq: UInt32):
    """Enable an IRQ line in the NVIC."""
    write32(NVIC_ISER, UInt32(1) << irq)


@always_inline
def disable(irq: UInt32):
    write32(NVIC_ICER, UInt32(1) << irq)


@always_inline
def is_enabled(irq: UInt32) -> Bool:
    return (read32(NVIC_ISER) & (UInt32(1) << irq)) != 0


@always_inline
def pend(irq: UInt32):
    """Software-trigger an IRQ (sets it pending in the NVIC)."""
    write32(NVIC_ISPR, UInt32(1) << irq)


@always_inline
def clear_pending(irq: UInt32):
    write32(NVIC_ICPR, UInt32(1) << irq)
