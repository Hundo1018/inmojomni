"""Chip/board descriptors — the road to multi-MCU inmojomni.

A chip is a *compile-time value*: a struct conforming to `Chip`, whose
associated constants describe what the silicon has. SDK types take the
chip as a parameter and enforce constraints with `comptime assert`, so
"this pin doesn't exist on that package" is a compile error, not a
field bug. See docs/MULTICHIP.md for the full design.

Status: prototype. The RP2040 SDK modules don't consume these yet.
"""


trait Chip:
    """The per-chip register-map source of truth.

    Every field is `comptime`, so an SDK type parameterized on a `Chip`
    (e.g. `Pin[N, C]`, `init[C]()`) folds these into immediates — the
    descriptor costs zero firmware bytes. Fields that name absolute
    addresses differ between chips (the whole peripheral map moved
    between RP2040 and RP2350), so they must live here, not hard-coded
    in the driver.
    """

    comptime NAME: StaticString
    comptime NUM_GPIOS: Int
    comptime NUM_CORES: Int
    comptime NUM_PIO_BLOCKS: Int
    comptime SRAM_BYTES: Int

    # --- capability flags (steer `comptime if` in the SDK) -------------
    comptime HAS_PAD_ISO: Bool  # pads power up ISOlated (RP2350 only)
    comptime USES_HW_TIMER: Bool  # `init`/`sleep` use the 1 µs TIMER

    # --- RESETS block ---------------------------------------------------
    comptime RESETS_RESET: UInt32
    comptime RESETS_RESET_DONE: UInt32
    comptime RESET_IO_BANK0: UInt32  # RESET bit for IO_BANK0
    comptime RESET_PADS_BANK0: UInt32  # RESET bit for PADS_BANK0

    # --- GPIO peripheral bases (per-pin regs derived from these) --------
    comptime IO_BANK0_BASE: UInt32
    comptime PADS_BANK0_BASE: UInt32

    # --- SIO single-cycle GPIO (ABSOLUTE addresses; offsets differ:
    #     RP2350 interleaves two banks, so OUT_SET.. do NOT match RP2040) -
    comptime SIO_BASE: UInt32
    comptime SIO_GPIO_IN: UInt32
    comptime SIO_GPIO_OUT: UInt32
    comptime SIO_GPIO_OUT_SET: UInt32
    comptime SIO_GPIO_OUT_CLR: UInt32
    comptime SIO_GPIO_OUT_XOR: UInt32
    comptime SIO_GPIO_OE: UInt32
    comptime SIO_GPIO_OE_SET: UInt32
    comptime SIO_GPIO_OE_CLR: UInt32

    # --- multicore: PSM reset + inter-core SIO FIFO ---------------------
    comptime IS_RISCV: Bool  # cores boot RISC-V (mtvec + h3.unblock)
    comptime PSM_FRCE_OFF: UInt32
    comptime PSM_PROC1: UInt32  # FRCE_OFF bit for core 1
    comptime SIO_FIFO_ST: UInt32
    comptime SIO_FIFO_WR: UInt32
    comptime SIO_FIFO_RD: UInt32

    # --- PIO -------------------------------------------------------------
    comptime PIO0_BASE: UInt32  # PIOn = PIO0_BASE + n * 0x10_0000
    comptime RESET_PIO0_SHIFT: Int  # RESETS bit index of PIO0 (PIOn = +n)

    # --- clocks / timebase ----------------------------------------------
    comptime XOSC_BASE: UInt32
    comptime CLOCKS_BASE: UInt32
    comptime CLK_ADC_CTRL_OFF: UInt32  # CLOCKS offset (moved on RP2350)
    comptime HAS_TICKS_BLOCK: Bool  # RP2350: TICKS block feeds TIMER0
    comptime TICKS_BASE: UInt32  # 0 where absent
    comptime TIMER_BASE: UInt32
    comptime TIMER_INTR_OFF: UInt32  # RP2350 inserted regs before INTR/INTE
    comptime TIMER_INTE_OFF: UInt32
    comptime RESET_TIMER: UInt32

    # --- PWM / ADC / UART -------------------------------------------------
    comptime PWM_BASE: UInt32
    comptime NUM_PWM_SLICES: Int
    comptime RESET_PWM: UInt32
    comptime ADC_BASE: UInt32
    comptime RESET_ADC: UInt32
    comptime UART0_BASE: UInt32
    comptime RESET_UART0: UInt32


struct RP2040(Chip):
    comptime NAME: StaticString = "RP2040"
    comptime NUM_GPIOS: Int = 30
    comptime NUM_CORES: Int = 2
    comptime NUM_PIO_BLOCKS: Int = 2
    comptime SRAM_BYTES: Int = 264 * 1024

    comptime HAS_PAD_ISO: Bool = False
    comptime USES_HW_TIMER: Bool = True

    comptime RESETS_RESET: UInt32 = 0x4000_C000
    comptime RESETS_RESET_DONE: UInt32 = 0x4000_C008
    comptime RESET_IO_BANK0: UInt32 = 1 << 5
    comptime RESET_PADS_BANK0: UInt32 = 1 << 8

    comptime IO_BANK0_BASE: UInt32 = 0x4001_4000
    comptime PADS_BANK0_BASE: UInt32 = 0x4001_C000

    comptime SIO_BASE: UInt32 = 0xD000_0000
    comptime SIO_GPIO_IN: UInt32 = 0xD000_0004
    comptime SIO_GPIO_OUT: UInt32 = 0xD000_0010
    comptime SIO_GPIO_OUT_SET: UInt32 = 0xD000_0014
    comptime SIO_GPIO_OUT_CLR: UInt32 = 0xD000_0018
    comptime SIO_GPIO_OUT_XOR: UInt32 = 0xD000_001C
    comptime SIO_GPIO_OE: UInt32 = 0xD000_0020
    comptime SIO_GPIO_OE_SET: UInt32 = 0xD000_0024
    comptime SIO_GPIO_OE_CLR: UInt32 = 0xD000_0028

    comptime IS_RISCV: Bool = False
    comptime PSM_FRCE_OFF: UInt32 = 0x4001_0004
    comptime PSM_PROC1: UInt32 = 1 << 16
    comptime SIO_FIFO_ST: UInt32 = 0xD000_0050  # VLD bit0, RDY bit1
    comptime SIO_FIFO_WR: UInt32 = 0xD000_0054
    comptime SIO_FIFO_RD: UInt32 = 0xD000_0058

    comptime PIO0_BASE: UInt32 = 0x5020_0000
    comptime RESET_PIO0_SHIFT: Int = 10

    comptime XOSC_BASE: UInt32 = 0x4002_4000
    comptime CLOCKS_BASE: UInt32 = 0x4000_8000
    comptime CLK_ADC_CTRL_OFF: UInt32 = 0x60
    comptime HAS_TICKS_BLOCK: Bool = False
    comptime TICKS_BASE: UInt32 = 0
    comptime TIMER_BASE: UInt32 = 0x4005_4000
    comptime TIMER_INTR_OFF: UInt32 = 0x34
    comptime TIMER_INTE_OFF: UInt32 = 0x38
    comptime RESET_TIMER: UInt32 = 1 << 21

    comptime PWM_BASE: UInt32 = 0x4005_0000
    comptime NUM_PWM_SLICES: Int = 8
    comptime RESET_PWM: UInt32 = 1 << 14
    comptime ADC_BASE: UInt32 = 0x4004_C000
    comptime RESET_ADC: UInt32 = 1 << 0
    comptime UART0_BASE: UInt32 = 0x4003_4000
    comptime RESET_UART0: UInt32 = 1 << 22


struct RP2350(Chip):
    """Pico 2. Hazard3 RISC-V cores: Mojo can target these natively
    (riscv32 backend built in — no IR retargeting needed at all).

    The peripheral map moved wholesale from RP2040, every pad powers up
    ISOlated (HAS_PAD_ISO), and the SIO GPIO register offsets differ
    because the block interleaves two 32-pin banks. Values are from
    pico-sdk 2.1.0 RP2350.svd; SIO_GPIO_OUT_XOR/OE_SET are hardware-
    verified (the native-RISC-V blink used exactly these)."""

    comptime NAME: StaticString = "RP2350"
    comptime NUM_GPIOS: Int = 30  # QFN-60; RP2350B has 48
    comptime NUM_CORES: Int = 2
    comptime NUM_PIO_BLOCKS: Int = 3
    comptime SRAM_BYTES: Int = 520 * 1024

    comptime HAS_PAD_ISO: Bool = True
    comptime USES_HW_TIMER: Bool = False

    comptime RESETS_RESET: UInt32 = 0x4002_0000
    comptime RESETS_RESET_DONE: UInt32 = 0x4002_0008
    comptime RESET_IO_BANK0: UInt32 = 1 << 6
    comptime RESET_PADS_BANK0: UInt32 = 1 << 9

    comptime IO_BANK0_BASE: UInt32 = 0x4002_8000
    comptime PADS_BANK0_BASE: UInt32 = 0x4003_8000

    comptime SIO_BASE: UInt32 = 0xD000_0000
    comptime SIO_GPIO_IN: UInt32 = 0xD000_0004
    comptime SIO_GPIO_OUT: UInt32 = 0xD000_0010
    comptime SIO_GPIO_OUT_SET: UInt32 = 0xD000_0018
    comptime SIO_GPIO_OUT_CLR: UInt32 = 0xD000_0020
    comptime SIO_GPIO_OUT_XOR: UInt32 = 0xD000_0028
    comptime SIO_GPIO_OE: UInt32 = 0xD000_0030
    comptime SIO_GPIO_OE_SET: UInt32 = 0xD000_0038
    comptime SIO_GPIO_OE_CLR: UInt32 = 0xD000_0040

    comptime IS_RISCV: Bool = True
    comptime PSM_FRCE_OFF: UInt32 = 0x4001_8004
    comptime PSM_PROC1: UInt32 = 1 << 24
    comptime SIO_FIFO_ST: UInt32 = 0xD000_0050  # VLD bit0, RDY bit1
    comptime SIO_FIFO_WR: UInt32 = 0xD000_0054
    comptime SIO_FIFO_RD: UInt32 = 0xD000_0058

    comptime PIO0_BASE: UInt32 = 0x5020_0000
    comptime RESET_PIO0_SHIFT: Int = 11

    comptime XOSC_BASE: UInt32 = 0x4004_8000
    comptime CLOCKS_BASE: UInt32 = 0x4001_0000
    comptime CLK_ADC_CTRL_OFF: UInt32 = 0x6C
    comptime HAS_TICKS_BLOCK: Bool = True  # ticks.h: TIMER0 tick source
    comptime TICKS_BASE: UInt32 = 0x4010_8000
    comptime TIMER_BASE: UInt32 = 0x400B_0000  # TIMER0
    comptime TIMER_INTR_OFF: UInt32 = 0x3C  # LOCKED/SOURCE inserted
    comptime TIMER_INTE_OFF: UInt32 = 0x40
    comptime RESET_TIMER: UInt32 = 1 << 23  # TIMER0

    comptime PWM_BASE: UInt32 = 0x400A_8000
    comptime NUM_PWM_SLICES: Int = 12
    comptime RESET_PWM: UInt32 = 1 << 16
    comptime ADC_BASE: UInt32 = 0x400A_0000
    comptime RESET_ADC: UInt32 = 1 << 0
    comptime UART0_BASE: UInt32 = 0x4007_0000
    comptime RESET_UART0: UInt32 = 1 << 26


struct PicoBoard:
    """Board = chip + wiring facts."""

    comptime CHIP = RP2040  # the chip is a type, not a value
    comptime LED: Int = 25
    comptime XOSC_HZ: Int = 12_000_000


def gpio_budget[C: Chip]() -> Int:
    """Example of chip-generic code: constraints resolve at compile time."""
    return C.NUM_GPIOS
