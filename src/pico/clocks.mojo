"""System clock control: PLL_SYS bring-up and the on-chip frequency counter.

`pico.init()` leaves clk_sys on the 12 MHz crystal with no PLL (the
benchmark suite relies on that shared, PLL-free clock). Code that wants
the RP2040's nominal speed calls `sys_clock_125mhz()` afterwards:

    pico.init()
    clocks.sys_clock_125mhz()
    var khz = clocks.measure_khz(clocks.FC_CLK_SYS)   # ~125_000

clk_ref stays on the crystal, so the 1 µs TIMER tick (and therefore
`time_us` / `sleep_us`) is unaffected by the switch. clk_peri follows
clk_sys: `pico.uart` computes its baud divisor for 12 MHz and must be
re-initialised for a different clk_sys. Sequence: datasheet §2.18.3,
mirrored by `bench/irq_latency.c` so both languages share one clock setup.
"""

from pico.mmio import read32, write32, write32_clr, write32_set
from pico.rp2040 import (
    CLK_SYS_AUXSRC_PLL_SYS,
    CLK_SYS_CTRL,
    CLK_SYS_SELECTED,
    CLK_SYS_SRC_AUX,
    CLK_SYS_SRC_CLK_REF,
    FC0_INTERVAL,
    FC0_MAX_KHZ,
    FC0_MIN_KHZ,
    FC0_REF_KHZ,
    FC0_RESULT,
    FC0_SRC,
    FC0_STATUS,
    FC0_STATUS_DONE,
    FC0_STATUS_RUNNING,
    PLL_CS_LOCK,
    PLL_PWR_PD,
    PLL_PWR_POSTDIVPD,
    PLL_PWR_VCOPD,
    PLL_SYS_CS,
    PLL_SYS_FBDIV_INT,
    PLL_SYS_PRIM,
    PLL_SYS_PWR,
    RESET_PLL_SYS,
    RESETS_RESET,
    RESETS_RESET_DONE,
)

# FC0_SRC values (§2.15.7, CLOCKS: FC0_SRC)
comptime FC_PLL_SYS: UInt32 = 1
comptime FC_XOSC: UInt32 = 5
comptime FC_CLK_REF: UInt32 = 8
comptime FC_CLK_SYS: UInt32 = 9
comptime FC_CLK_PERI: UInt32 = 10

comptime XOSC_KHZ: UInt32 = 12_000


def sys_clock_125mhz():
    """clk_sys <- PLL_SYS at 125 MHz (XOSC 12 MHz x 125 = 1500 MHz VCO,
    post-dividers 6 x 2). Requires `pico.init()` first (XOSC running,
    clk_ref = XOSC, clk_sys = clk_ref). Same divider choice as the
    pico-sdk default, so boot2's QSPI divider (/2) stays in spec."""
    # 1. PLL_SYS through reset (also stops a PLL left running).
    write32_set(RESETS_RESET, RESET_PLL_SYS)
    write32_clr(RESETS_RESET, RESET_PLL_SYS)
    while (read32(RESETS_RESET_DONE) & RESET_PLL_SYS) == 0:
        pass
    # 2. Reference divider 1, feedback divider 125 -> VCO 1500 MHz.
    write32(PLL_SYS_CS, 1)
    write32(PLL_SYS_FBDIV_INT, 125)
    # 3. Power up PLL + VCO (post-divider stays off), wait for lock.
    write32_clr(PLL_SYS_PWR, PLL_PWR_PD | PLL_PWR_VCOPD)
    while (read32(PLL_SYS_CS) & PLL_CS_LOCK) == 0:
        pass
    # 4. Post-dividers 6 and 2 -> 125 MHz, then power them up.
    write32(PLL_SYS_PRIM, (UInt32(6) << 16) | (UInt32(2) << 12))
    write32_clr(PLL_SYS_PWR, PLL_PWR_POSTDIVPD)
    # 5. Glitchless switch: AUXSRC = pll_sys while SRC is still clk_ref,
    #    then SRC = aux and wait for SELECTED to follow.
    write32(CLK_SYS_CTRL, CLK_SYS_AUXSRC_PLL_SYS)
    write32_set(CLK_SYS_CTRL, CLK_SYS_SRC_AUX)
    while read32(CLK_SYS_SELECTED) != (UInt32(1) << CLK_SYS_SRC_AUX):
        pass


def sys_clock_12mhz():
    """Back to clk_sys = clk_ref (12 MHz XOSC) and PLL_SYS powered down:
    the state `pico.init()` leaves the chip in."""
    write32_clr(CLK_SYS_CTRL, CLK_SYS_SRC_AUX)
    while read32(CLK_SYS_SELECTED) != (UInt32(1) << CLK_SYS_SRC_CLK_REF):
        pass
    write32_set(PLL_SYS_PWR, PLL_PWR_PD | PLL_PWR_VCOPD | PLL_PWR_POSTDIVPD)


def measure_khz(src: UInt32) -> UInt32:
    """Measure clock `src` (an FC_* value) with frequency counter 0,
    referenced to clk_ref (assumed 12 MHz XOSC). Interval 2^10 ref
    cycles (~85 µs, about 1 kHz resolution); blocks until done."""
    while (read32(FC0_STATUS) & FC0_STATUS_RUNNING) != 0:
        pass
    write32(FC0_REF_KHZ, XOSC_KHZ)
    write32(FC0_INTERVAL, 10)
    write32(FC0_MIN_KHZ, 0)
    write32(FC0_MAX_KHZ, 0x1FF_FFFF)
    write32(FC0_SRC, src)  # starts the measurement
    while (read32(FC0_STATUS) & FC0_STATUS_DONE) == 0:
        pass
    return read32(FC0_RESULT) >> 5
