"""De-risk gate for the RP2350 result-readback loop, v4: flash mailbox.

Findings so far (all on hardware, 2026-07-17):
  v1/v2 — rom_reboot_bootsel works (lhu of the u16 entry at 0x7dfa;
  REBOOT_TO_ARM 0x10 required for the BOOTSEL session to be SWD-readable),
  but the bootrom clears ALL of main SRAM on the way in: an SRAM mailbox
  cannot survive. Only watchdog SCRATCH0/1 survive (8 bytes).
  v3 — the SRAM clear happens with or without the architecture switch,
  and PICOBOOT rejects peripheral addresses, so the scratch registers
  are only reachable over SWD.

v4 bets on the one large persistent medium: flash. The firmware stages a
result page in SRAM and calls flash_commit_reboot (crt0_rv32.S, runs
from RAM because programming flash kills XIP): erase the reserved sector,
program the page, reboot to BOOTSEL. The host then reads the sector over
PICOBOOT at its XIP address — no probe, no button press, any payload size
up to 4 KiB.

Mailbox: last 4 KiB sector of the Pico 2's 4 MiB flash
  flash offset 0x003FF000  =  XIP address 0x103FF000
Page layout: magic "RV32", payload word count, payload..., XOR checksum.
"""

from std.ffi import external_call

from pico.mmio import read32, write32
from pico.pico2 import init

comptime BUF: UInt32 = 0x2000_8000  # SRAM staging (clear of .data and stack)
comptime MB_FLASH_OFF: UInt32 = 0x003F_F000


@export("mojo_main")
def start() abi("C"):
    init()
    write32(BUF + 0x00, 0x52563332)  # magic "RV32"
    write32(BUF + 0x04, 2)  # payload words
    write32(BUF + 0x08, 0xC0FFEE01)
    write32(BUF + 0x0C, 0x12345678)
    write32(BUF + 0x10, read32(BUF + 0x08) ^ read32(BUF + 0x0C))
    external_call["flash_commit_reboot", NoneType](
        MB_FLASH_OFF, BUF, UInt32(256), UInt32(0)
    )
    while True:  # unreachable: flash_commit_reboot never returns
        pass
