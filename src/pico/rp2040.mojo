"""RP2040 register map (the subset pico-mojo uses).

All addresses and bit positions come from the RP2040 datasheet.
Everything here is `comptime`, so the register map costs zero bytes
of firmware — addresses fold directly into the generated `ldr`/`str`.
"""

# --- RESETS (§2.14) -------------------------------------------------
comptime RESETS_BASE: UInt32 = 0x4000_C000
comptime RESETS_RESET: UInt32 = RESETS_BASE + 0x0
comptime RESETS_RESET_DONE: UInt32 = RESETS_BASE + 0x8

comptime RESET_IO_BANK0: UInt32 = 1 << 5
comptime RESET_PADS_BANK0: UInt32 = 1 << 8
comptime RESET_PIO0: UInt32 = 1 << 10
comptime RESET_PIO1: UInt32 = 1 << 11
comptime RESET_TIMER: UInt32 = 1 << 21

# --- XOSC (§2.16): 12 MHz crystal on the Pico board ----------------
comptime XOSC_BASE: UInt32 = 0x4002_4000
comptime XOSC_CTRL: UInt32 = XOSC_BASE + 0x00
comptime XOSC_STATUS: UInt32 = XOSC_BASE + 0x04
comptime XOSC_STARTUP: UInt32 = XOSC_BASE + 0x0C

comptime XOSC_CTRL_ENABLE: UInt32 = 0xFAB << 12  # magic "enable" key
comptime XOSC_CTRL_RANGE_1_15MHZ: UInt32 = 0xAA0
comptime XOSC_STATUS_STABLE: UInt32 = 1 << 31
comptime XOSC_STARTUP_DELAY: UInt32 = 47  # ~1 ms @ 12 MHz, in 256-cycle units

# --- CLOCKS (§2.15) -------------------------------------------------
comptime CLOCKS_BASE: UInt32 = 0x4000_8000
comptime CLK_REF_CTRL: UInt32 = CLOCKS_BASE + 0x30
comptime CLK_REF_SELECTED: UInt32 = CLOCKS_BASE + 0x38
comptime CLK_SYS_CTRL: UInt32 = CLOCKS_BASE + 0x3C
comptime CLK_SYS_SELECTED: UInt32 = CLOCKS_BASE + 0x44

comptime CLK_REF_SRC_XOSC: UInt32 = 2  # xosc_clksrc
comptime CLK_SYS_SRC_CLK_REF: UInt32 = 0

# --- WATCHDOG (§4.7): provides the 1 MHz tick for TIMER -------------
comptime WATCHDOG_BASE: UInt32 = 0x4005_8000
comptime WATCHDOG_TICK: UInt32 = WATCHDOG_BASE + 0x2C
comptime WATCHDOG_TICK_ENABLE: UInt32 = 1 << 9

# --- TIMER (§4.6): 64-bit microsecond timer -------------------------
comptime TIMER_BASE: UInt32 = 0x4005_4000
comptime TIMER_TIMERAWL: UInt32 = TIMER_BASE + 0x28  # raw read, low 32 bits
comptime TIMER_ALARM0: UInt32 = TIMER_BASE + 0x10  # fires TIMER_IRQ_0
comptime TIMER_ARMED: UInt32 = TIMER_BASE + 0x20
comptime TIMER_INTR: UInt32 = TIMER_BASE + 0x34  # raw latched, write-1-clear
comptime TIMER_INTE: UInt32 = TIMER_BASE + 0x38  # interrupt enable

# --- SIO (§2.3.1): single-cycle GPIO access -------------------------
comptime SIO_BASE: UInt32 = 0xD000_0000
comptime SIO_GPIO_IN: UInt32 = SIO_BASE + 0x04
comptime SIO_GPIO_OUT: UInt32 = SIO_BASE + 0x10
comptime SIO_GPIO_OUT_SET: UInt32 = SIO_BASE + 0x14
comptime SIO_GPIO_OUT_CLR: UInt32 = SIO_BASE + 0x18
comptime SIO_GPIO_OUT_XOR: UInt32 = SIO_BASE + 0x1C
comptime SIO_GPIO_OE_SET: UInt32 = SIO_BASE + 0x24

# --- SIO GPIO direction / input ------------------------------------
comptime SIO_GPIO_OE: UInt32 = SIO_BASE + 0x20
comptime SIO_GPIO_OE_CLR: UInt32 = SIO_BASE + 0x28

# --- IO_BANK0 (§2.19.6): per-pin function select & interrupts -------
# Per pin N: STATUS at 8*N, CTRL at 8*N + 4.
comptime IO_BANK0_BASE: UInt32 = 0x4001_4000
comptime FUNCSEL_SIO: UInt32 = 5

# Raw interrupt status, write-1-clear for edge bits.
# INTR0..INTR3 cover 8 pins each, 4 event bits per pin.
comptime IO_BANK0_INTR0: UInt32 = IO_BANK0_BASE + 0xF0

# --- PADS_BANK0 (§2.19.6.3): electrical pad control ------------------
# Per pin N: GPIO pad register at BASE + 4 + 4*N.
comptime PADS_BANK0_BASE: UInt32 = 0x4001_C000
comptime PADS_SLEWFAST: UInt32 = 1 << 0
comptime PADS_SCHMITT: UInt32 = 1 << 1
comptime PADS_PDE: UInt32 = 1 << 2  # pull-down enable
comptime PADS_PUE: UInt32 = 1 << 3  # pull-up enable
comptime PADS_DRIVE_LSB: UInt32 = 4
comptime PADS_DRIVE_MASK: UInt32 = 0x3 << 4
comptime PADS_IE: UInt32 = 1 << 6  # input enable (reset: on)
comptime PADS_OD: UInt32 = 1 << 7  # output disable (overrides all)
