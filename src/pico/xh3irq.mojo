"""External interrupt control for the RP2350's Hazard3 cores (Xh3irq).

The RP2350's RISC-V cores have no NVIC; external IRQs go through
Hazard3's custom Xh3irq controller (CSRs meiea/meipa/meinext — see
doc/sections in github.com/wren6991/hazard3). crt0_rv32.S installs a
dispatcher on mtvec that loops `h3.meinext` and calls the application's
handler for each pending+enabled IRQ:

    from pico.time import alarm0_ack
    import pico.xh3irq as xh3irq


    @export("isr_riscv_extirq")
    def isr(irq: UInt32) abi("C"):
        if irq == 0:              # TIMER0_IRQ_0
            alarm0_ack[RP2350]()  # ack at the source (level-sensitive!)

    xh3irq.enable(0)
    xh3irq.global_enable()

IRQs are level-sensitive: the handler must clear the peripheral's
interrupt or the dispatcher re-enters forever. IRQ numbers are the
RP2350 datasheet's external interrupt numbers (intctrl.h), e.g.
TIMER0_IRQ_0 = 0. Core 0 only; core 1's mtvec still parks.
Mojo has no CSR access, so these call two-instruction crt0 helpers.
"""

from std.ffi import external_call


def enable(irq: UInt32):
    """Enable one external IRQ in h3.meiea (windowed set, no clobber)."""
    external_call["h3_irq_enable", NoneType](irq)


def global_enable():
    """Set mie.meie + mstatus.mie: let enabled external IRQs fire."""
    external_call["h3_irq_global_enable", NoneType]()
