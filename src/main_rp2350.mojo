"""Blink for the Raspberry Pi Pico 2 (RP2350), native RISC-V.

This is the "Mojo 直出 RISC-V" milestone: unlike the RP2040 firmware
(which emits riscv32 IR and *retargets* it to thumbv6m because Mojo has no
ARM backend), the RP2350's Hazard3 cores are RISC-V, so Mojo compiles for
them directly:

    mojo build --emit=object --target-triple=riscv32-unknown-none-elf

No retarget.mojo, no external llc, no IR rewriting. See tools/build.mojo
(the rp2350 branch) and runtime/crt0_rv32.S.

Register addresses/bit positions below are from pico-sdk 2.1.0
src/rp2350/hardware_regs/RP2350.svd. They differ from RP2040: the whole
peripheral map moved (RESETS 0x4000c000 -> 0x40020000, IO_BANK0
0x40014000 -> 0x40028000, PADS_BANK0 0x4001c000 -> 0x40038000), and every
pad now powers up ISOlated (PADS.ISO bit 8) and must be un-isolated
before it will drive — an RP2350-only step with no RP2040 equivalent.
The SIO low bank (GPIO0..31) keeps the RP2040 offsets.
"""

from pico.mmio import read32, write32, write32_clr

# --- RESETS (RP2350 datasheet §12.1; RP2350.svd RESETS @ 0x40020000) ---
comptime RESETS_RESET: UInt32 = 0x40020000
comptime RESETS_RESET_DONE: UInt32 = 0x40020008
comptime RST_IO_BANK0: UInt32 = 1 << 6  # RESET.IO_BANK0
comptime RST_PADS_BANK0: UInt32 = 1 << 9  # RESET.PADS_BANK0

# --- PADS_BANK0 (RP2350.svd @ 0x40038000; GPIO25 at offset 0x68) --------
comptime PADS_GPIO25: UInt32 = 0x40038068
comptime PAD_ISO: UInt32 = 1 << 8  # isolation latch — clear to enable pad
comptime PAD_OD: UInt32 = 1 << 7  # output disable — clear to allow drive

# --- IO_BANK0 (RP2350.svd @ 0x40028000; GPIO25_CTRL at offset 0xCC) -----
comptime IO_GPIO25_CTRL: UInt32 = 0x400280CC
comptime FUNCSEL_SIO: UInt32 = 5  # GPIO25_CTRL.FUNCSEL = siob_proc_25

# --- SIO (RP2350.svd @ 0xD0000000; low-bank offsets match RP2040) -------
comptime SIO_GPIO_OE_SET: UInt32 = 0xD0000038
comptime SIO_GPIO_OUT_XOR: UInt32 = 0xD0000028

comptime LED_MASK: UInt32 = 1 << 25  # on-board LED is GPIO25 (same as Pico 1)

# Scratch word used only to keep the busy-delay loop from being optimised
# away: write32 is a volatile store, which the compiler must not elide.
comptime SPIN_SCRATCH: UInt32 = 0x20040000
comptime SPIN_COUNT: UInt32 = 2_000_000


def _spin(count: UInt32):
    """Busy-wait `count` iterations. Each iteration does a volatile store,
    so the loop survives -O2 (a pure arithmetic loop would be dead-code
    eliminated). Delay is proportional to `count`, tuned on hardware."""
    var i: UInt32 = 0
    while i < count:
        write32(SPIN_SCRATCH, i)
        i += 1


@export("mojo_main")
def start() abi("C"):
    # Bring the GPIO peripherals out of reset and wait until they ack.
    write32_clr(RESETS_RESET, RST_IO_BANK0 | RST_PADS_BANK0)
    while (
        read32(RESETS_RESET_DONE) & (RST_IO_BANK0 | RST_PADS_BANK0)
    ) != (RST_IO_BANK0 | RST_PADS_BANK0):
        pass

    # Route GPIO25 to the SIO (software) function.
    write32(IO_GPIO25_CTRL, FUNCSEL_SIO)
    # Drive GPIO25 as an output from SIO.
    write32(SIO_GPIO_OE_SET, LED_MASK)
    # Finally un-isolate the pad. On RP2350 every pad powers up ISOlated
    # (ISO=1) and de-resetting PADS does NOT clear it (datasheet §9.7), so
    # this explicit clear is mandatory. Done last, so the pad only connects
    # once the output is already configured (avoids a transient glitch).
    write32_clr(PADS_GPIO25, PAD_ISO)

    while True:
        write32(SIO_GPIO_OUT_XOR, LED_MASK)
        _spin(SPIN_COUNT)
