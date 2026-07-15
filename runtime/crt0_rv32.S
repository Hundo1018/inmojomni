/* Minimal RISC-V (Hazard3) startup for RP2350 / Raspberry Pi Pico 2.
 *
 * Counterpart to crt0.S (the Cortex-M0+ startup for RP2040). The RP2350
 * bootrom, after validating the flash image's metadata block, transfers
 * control here; this file does the little that must happen before Mojo
 * can run: set gp/sp, initialise .data/.bss, then call mojo_main.
 *
 * NOTE: the RP2350 flash boot metadata (IMAGE_DEF "block loop") is emitted
 * separately in runtime/rp2350_image_def.S so the bootrom recognises this
 * as a bootable RISC-V image. Linked first, at the very start of flash.
 */
.attribute arch, "rv32i"

.section .text.reset, "ax"
.global _reset
_reset:
    /* global pointer (linker relaxation off around this one load) */
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop

    /* stack pointer = top of RAM (grows down) */
    la sp, _stack_top

    /* trap vector -> park (any trap is a bug on bare metal) */
    la t0, _trap
    csrw mtvec, t0

    /* copy .data (initialised globals) from flash (LMA) to RAM (VMA) */
    la a0, _sidata
    la a1, _sdata
    la a2, _edata
1:  bgeu a1, a2, 2f
    lw a3, 0(a0)
    sw a3, 0(a1)
    addi a0, a0, 4
    addi a1, a1, 4
    j 1b
2:
    /* zero .bss */
    la a0, _sbss
    la a1, _ebss
3:  bgeu a0, a1, 4f
    sw zero, 0(a0)
    addi a0, a0, 4
    j 3b
4:
    call mojo_main
    /* mojo_main should never return; park the core if it does */
_hang:
    wfi
    j _hang

/* trap handler: no OS here, so any exception/interrupt just halts */
.align 2
_trap:
    j _trap
