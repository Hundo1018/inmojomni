/* RP2350 flash boot metadata — the IMAGE_DEF "block loop".
 *
 * RP2350 datasheet §5.9; field values from pico-sdk 2.1.0
 * src/common/boot_picobin_headers/include/boot/picobin.h.
 *
 * Linked first, at the very start of flash (0x10000000). The bootrom
 * scans the first 4 KiB for the start marker, validates the IMAGE_DEF
 * item, and — because a blank Pico 2 powers up in Arm mode (§3.9) — on
 * seeing CPU=RISC-V it automatically resets both cores into Hazard3
 * RISC-V mode (§3.9.1), then enters at the ENTRY_POINT item's PC.
 *
 * Without a valid block here the bootrom silently refuses to launch the
 * image (no fault, just no blink), so this file is load-bearing.
 */
.section .image_def, "a"
.global __image_def
__image_def:
    .word 0xffffded3   /* PICOBIN_BLOCK_MARKER_START */
    .word 0x11010142   /* IMAGE_DEF item: type 0x42, size 1 word, flags 0x1101
                        *   = Image Type EXE(1) | EXE CPU RISC-V(1<<8)
                        *   | EXE CHIP RP2350(1<<12). This CPU field is what
                        *   makes the bootrom switch to Hazard3. */
    .word 0x00000344   /* ENTRY_POINT item: type 0x44, size 3 words */
    .word _reset       /*   initial PC  = RISC-V reset handler (crt0_rv32.S) */
    .word 0x20082000   /*   initial SP  = SRAM_END (520 KiB from 0x20000000) */
    .word 0x000004ff   /* LAST item: type 0xff, size 4 words (IMAGE_DEF 1 +
                        *   ENTRY_POINT 3) */
    .word 0x00000000   /* LINK: byte offset to next block's header; 0 = self-loop */
    .word 0xab123579   /* PICOBIN_BLOCK_MARKER_END */
