# boot2 (second-stage bootloader) — vendored from pico-sdk

Verbatim sources from [raspberrypi/pico-sdk](https://github.com/raspberrypi/pico-sdk)
at tag **2.1.0**, BSD-3-Clause (see LICENSE.TXT):

- `boot2_w25q080.S` — src/rp2040/boot_stage2/
- `boot2_helpers/*.S` — src/rp2040/boot_stage2/asminclude/boot2_helpers/
- `hardware/regs/*.h`, `hardware/platform_defs.h` — src/rp2040/hardware_regs/include/hardware/
- `pico/asm_helper.S` — src/rp2040/pico_platform/include/pico/
- `pico/pico.h` — local stub (marked), not from upstream

The build pipeline (tools/boot2.mojo) assembles this with
`PICO_FLASH_SPI_CLKDIV=2`, pads to 252 bytes and appends the
CRC32-MPEG2 checksum the RP2040 mask ROM requires, producing
`build/boot2.bin`. `runtime/boot2.bin` is the golden reference: a host
regression test asserts the generated binary is byte-identical to it
(verified 2026-07-04 — the golden blob is exactly this source at this
tag with this clkdiv).
