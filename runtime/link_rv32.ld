/* RP2350 (Raspberry Pi Pico 2), RISC-V, linker script for inmojomni.
 *
 * Memory map: RP2350 datasheet §2.2. XIP flash window starts at
 * 0x10000000 (Pico 2 carries 4 MiB); SRAM is 520 KiB from 0x20000000
 * (8 striped banks 0x20000000..0x2007ffff + two 4 KiB banks after).
 *
 * The flash image must OPEN with the RP2350 metadata block loop (the
 * IMAGE_DEF), or the bootrom will not launch it — so .image_def is the
 * first section, at 0x10000000.
 */

MEMORY {
    FLASH (rx)  : ORIGIN = 0x10000000, LENGTH = 4096K
    RAM   (rwx) : ORIGIN = 0x20000000, LENGTH = 520K  /* 0x82000: 512K striped + 2x4K */
}

ENTRY(_reset)

_stack_top = ORIGIN(RAM) + LENGTH(RAM);          /* core 0: scratch Y top */
_core1_stack_top = ORIGIN(RAM) + LENGTH(RAM) - 4K;  /* core 1: scratch X top */

SECTIONS {
    .image_def : {
        KEEP(*(.image_def))
    } > FLASH

    .text : {
        KEEP(*(.text.reset))
        *(.text*)
    } > FLASH

    .rodata : {
        *(.rodata*)
        *(.srodata*)
    } > FLASH

    /* RISC-V global pointer: covers +/-2 KiB of small data with gp-relative
     * addressing. Placed between .data and .sdata/.sbss. */
    . = ALIGN(4);

    .data : ALIGN(4) {
        _sdata = .;
        /* RAM-resident code (e.g. flash_commit_reboot): must execute
         * while XIP is disabled, so it lives in RAM, loaded from flash
         * by the crt0 .data copy loop like any initialised data. */
        *(.ramfunc*)
        . = ALIGN(4);
        *(.data*)
        . = ALIGN(4);
        __global_pointer$ = . + 0x800;
        *(.sdata*)
        . = ALIGN(4);
        _edata = .;
    } > RAM AT> FLASH
    _sidata = LOADADDR(.data);

    .bss (NOLOAD) : ALIGN(4) {
        _sbss = .;
        *(.sbss*)
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > RAM

    /DISCARD/ : {
        *(.riscv.attributes)
        *(.comment)
        *(.eh_frame*)
    }
}
