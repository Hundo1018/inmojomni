"""ADC driver: 12-bit SAR, channels 0-3 = GPIO26-29, channel 4 = the
internal temperature sensor (zero external parts).

clk_adc runs from the 12 MHz crystal here (no PLL in this project), so
a conversion takes 96 ADC cycles = 8 µs instead of the 2 µs you would
get at the datasheet's 48 MHz — same result bits, just slower.

    import pico.adc as adc

    adc.init()
    var raw = adc.read(0)                # GPIO26, 0..4095
    var mc = adc.read_temp_milli_c()     # e.g. 23451 = 23.451 °C
"""

from pico.chips import Chip, RP2040
from pico.mmio import read32, write32, write32_clr, write32_set
from pico.rp2040 import (
    ADC_CS_AINSEL_LSB,
    ADC_CS_EN,
    ADC_CS_READY,
    ADC_CS_START_ONCE,
    ADC_CS_TS_EN,
    CLK_ADC_AUXSRC_XOSC,
    CLK_ENABLE,
)


def init[C: Chip = RP2040]():
    """Release the ADC from reset, clock it from XOSC, power it up.
    XOSC must already be running (board init on the RP2040;
    `time.init[RP2350]()` on the Pico 2)."""
    write32(C.CLOCKS_BASE + C.CLK_ADC_CTRL_OFF, CLK_ENABLE | CLK_ADC_AUXSRC_XOSC)
    write32_clr(C.RESETS_RESET, C.RESET_ADC)
    while (read32(C.RESETS_RESET_DONE) & C.RESET_ADC) == 0:
        pass
    write32(C.ADC_BASE, ADC_CS_EN)
    while (read32(C.ADC_BASE) & ADC_CS_READY) == 0:
        pass


def read[C: Chip = RP2040](channel: UInt32) -> UInt32:
    """One-shot conversion on `channel` (0-3 = GPIO26-29, 4 = temp
    sensor; the sensor is powered on demand). Returns 0..4095.
    Channel 4 is the temperature sensor on both supported chips
    (RP2040 and the RP2350A package on the Pico 2)."""
    var cs = ADC_CS_EN | (channel << ADC_CS_AINSEL_LSB)
    if channel == 4:
        cs |= ADC_CS_TS_EN
    write32(C.ADC_BASE, cs)
    while (read32(C.ADC_BASE) & ADC_CS_READY) == 0:
        pass
    write32_set(C.ADC_BASE, ADC_CS_START_ONCE)
    while (read32(C.ADC_BASE) & ADC_CS_READY) == 0:
        pass
    return read32(C.ADC_BASE + 0x04) & 0xFFF


def read_temp_milli_c[C: Chip = RP2040]() -> Int32:
    """Die temperature in milli-°C via the channel-4 sensor.
    Datasheet §4.9.5: T = 27 - (V_sense - 0.706 V) / 1.721 mV, with
    V_sense = raw * 3.3 V / 4096. Integer math throughout."""
    var raw = read[C](4)
    var uv = (Int64(Int(raw)) * 3_300_000) // 4096
    return Int32(27_000 - ((uv - 706_000) * 1000) // 1721)
