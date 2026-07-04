"""RP2040 register map (the subset pico-mojo uses).

All addresses and bit positions come from the RP2040 datasheet.
Everything here is `comptime`, so the register map costs zero bytes
of firmware — addresses fold directly into the generated `ldr`/`str`.
"""

# --- RESETS (§2.14) -------------------------------------------------
comptime RESETS_BASE: UInt32 = 0x4000_C000
comptime RESETS_RESET: UInt32 = RESETS_BASE + 0x0
comptime RESETS_RESET_DONE: UInt32 = RESETS_BASE + 0x8

comptime RESET_ADC: UInt32 = 1 << 0
comptime RESET_IO_BANK0: UInt32 = 1 << 5
comptime RESET_PADS_BANK0: UInt32 = 1 << 8
comptime RESET_PIO0: UInt32 = 1 << 10
comptime RESET_PIO1: UInt32 = 1 << 11
comptime RESET_PWM: UInt32 = 1 << 14
comptime RESET_TIMER: UInt32 = 1 << 21
comptime RESET_UART0: UInt32 = 1 << 22

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
comptime CLK_PERI_CTRL: UInt32 = CLOCKS_BASE + 0x48
comptime CLK_ADC_CTRL: UInt32 = CLOCKS_BASE + 0x60
comptime CLK_ENABLE: UInt32 = 1 << 11  # generic clock ENABLE bit
comptime CLK_ADC_AUXSRC_XOSC: UInt32 = 3 << 5  # AUXSRC field, xosc_clksrc

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

# --- PSM (§2.13): power-on state machine (per-core force off/on) ----
comptime PSM_FRCE_OFF: UInt32 = 0x4001_0004
comptime PSM_PROC1: UInt32 = 1 << 16

# --- SIO (§2.3.1): single-cycle GPIO access -------------------------
comptime SIO_BASE: UInt32 = 0xD000_0000
comptime SIO_FIFO_ST: UInt32 = SIO_BASE + 0x50  # VLD bit0, RDY bit1
comptime SIO_FIFO_WR: UInt32 = SIO_BASE + 0x54
comptime SIO_FIFO_RD: UInt32 = SIO_BASE + 0x58
comptime SIO_SPINLOCK_ST: UInt32 = SIO_BASE + 0x5C  # claim-state bitmap
comptime SIO_SPINLOCK0: UInt32 = SIO_BASE + 0x100  # read=claim, write=free

# --- PWM (§4.5): 8 slices x 2 channels, 0x14 bytes per slice --------
comptime PWM_BASE: UInt32 = 0x4005_0000

# --- ADC (§4.9): 500 ksps SAR, channel 4 = internal temp sensor -----
comptime ADC_BASE: UInt32 = 0x4004_C000
comptime ADC_CS: UInt32 = ADC_BASE + 0x00
comptime ADC_RESULT: UInt32 = ADC_BASE + 0x04
comptime ADC_CS_EN: UInt32 = 1 << 0
comptime ADC_CS_TS_EN: UInt32 = 1 << 1
comptime ADC_CS_START_ONCE: UInt32 = 1 << 2
comptime ADC_CS_READY: UInt32 = 1 << 8
comptime ADC_CS_AINSEL_LSB: UInt32 = 12

# --- UART0 (§4.2): ARM PL011 ----------------------------------------
comptime UART0_BASE: UInt32 = 0x4003_4000
comptime UART0_DR: UInt32 = UART0_BASE + 0x00
comptime UART0_FR: UInt32 = UART0_BASE + 0x18
comptime UART0_IBRD: UInt32 = UART0_BASE + 0x24
comptime UART0_FBRD: UInt32 = UART0_BASE + 0x28
comptime UART0_LCR_H: UInt32 = UART0_BASE + 0x2C
comptime UART0_CR: UInt32 = UART0_BASE + 0x30
comptime UART_FR_BUSY: UInt32 = 1 << 3
comptime UART_FR_RXFE: UInt32 = 1 << 4
comptime UART_FR_TXFF: UInt32 = 1 << 5
comptime UART_LCR_FEN: UInt32 = 1 << 4
comptime UART_LCR_WLEN8: UInt32 = 3 << 5
comptime UART_CR_UARTEN: UInt32 = 1 << 0
comptime UART_CR_LBE: UInt32 = 1 << 7
comptime UART_CR_TXE: UInt32 = 1 << 8
comptime UART_CR_RXE: UInt32 = 1 << 9
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
comptime IO_BANK0_PROC0_INTE0: UInt32 = IO_BANK0_BASE + 0x100
comptime IO_BANK0_PROC0_INTS0: UInt32 = IO_BANK0_BASE + 0x120

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
