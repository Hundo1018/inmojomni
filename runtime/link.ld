/* RP2040 (Raspberry Pi Pico) linker script for pico-mojo firmware. */

MEMORY {
    BOOT2 (rx)  : ORIGIN = 0x10000000, LENGTH = 0x100
    FLASH (rx)  : ORIGIN = 0x10000100, LENGTH = 2048K - 0x100
    RAM   (rwx) : ORIGIN = 0x20000000, LENGTH = 256K
}

ENTRY(reset_handler)

_stack_top = ORIGIN(RAM) + LENGTH(RAM);

SECTIONS {
    .boot2 : {
        KEEP(*(.boot2))
    } > BOOT2

    .vector_table : {
        KEEP(*(.vector_table))
    } > FLASH

    .text : {
        *(.text*)
    } > FLASH

    .rodata : {
        *(.rodata*)
    } > FLASH

    .data : ALIGN(4) {
        _sdata = .;
        *(.data*)
        . = ALIGN(4);
        _edata = .;
    } > RAM AT> FLASH
    _sidata = LOADADDR(.data);

    .bss (NOLOAD) : ALIGN(4) {
        _sbss = .;
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > RAM

    /DISCARD/ : {
        *(.ARM.exidx*)
        *(.ARM.attributes)
        *(.comment)
    }
}

ASSERT(SIZEOF(.boot2) == 256, "boot2 must be exactly 256 bytes")
