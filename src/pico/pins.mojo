"""Raspberry Pi Pico board pin map.

Names follow the official pinout. Use with the parametric Pin type:

    from pico import Pin, pins
    var led = Pin[pins.LED]()

GP0..GP28 are the pins on the 40-pin header (GP23/24/25 are internal:
SMPS mode, VBUS sense and the on-board LED).
"""

# --- header / internal GPIOs ----------------------------------------
comptime GP0: Int = 0
comptime GP1: Int = 1
comptime GP2: Int = 2
comptime GP3: Int = 3
comptime GP4: Int = 4
comptime GP5: Int = 5
comptime GP6: Int = 6
comptime GP7: Int = 7
comptime GP8: Int = 8
comptime GP9: Int = 9
comptime GP10: Int = 10
comptime GP11: Int = 11
comptime GP12: Int = 12
comptime GP13: Int = 13
comptime GP14: Int = 14
comptime GP15: Int = 15
comptime GP16: Int = 16
comptime GP17: Int = 17
comptime GP18: Int = 18
comptime GP19: Int = 19
comptime GP20: Int = 20
comptime GP21: Int = 21
comptime GP22: Int = 22
comptime GP26: Int = 26
comptime GP27: Int = 27
comptime GP28: Int = 28

# --- board functions (not on the header) ----------------------------
comptime SMPS_MODE: Int = 23   # high = PWM mode (lower ripple)
comptime VBUS_SENSE: Int = 24  # high when USB VBUS present
comptime LED: Int = 25         # on-board LED

# --- ADC-capable pins ------------------------------------------------
comptime ADC0: Int = 26
comptime ADC1: Int = 27
comptime ADC2: Int = 28
# ADC3 measures VSYS/3, ADC4 is the internal temperature sensor.

# --- default peripheral pins (Pico pinout defaults) -------------------
# Set the matching Function on the pin: UART=2, I2C=3, SPI=1, PWM=4.
comptime UART0_TX: Int = 0
comptime UART0_RX: Int = 1
comptime I2C0_SDA: Int = 4
comptime I2C0_SCL: Int = 5
comptime SPI0_RX: Int = 16
comptime SPI0_CSN: Int = 17
comptime SPI0_SCK: Int = 18
comptime SPI0_TX: Int = 19
