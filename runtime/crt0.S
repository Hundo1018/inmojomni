/* Minimal Cortex-M0+ startup for RP2040.
 *
 * boot2 (first 256 bytes of flash) configures the QSPI flash for XIP,
 * points VTOR at 0x10000100, loads SP/PC from the vector table below,
 * and jumps here. All application code is Mojo; this file only does
 * what must happen before a high-level language can run.
 */
.syntax unified
.cpu cortex-m0plus
.thumb

/* --- second-stage bootloader, checksummed, exactly 256 bytes ------- */
.section .boot2, "a"
.incbin "build/boot2.bin"   /* generated from source: tools/boot2.mojo */

/* --- vector table at 0x10000100 ------------------------------------ */
.section .vector_table, "a"
.global __vector_table
__vector_table:
    .word _stack_top          /* initial MSP */
    .word reset_handler       /* Reset */
    .word default_handler     /* NMI */
    .word default_handler     /* HardFault */
    .rept 12                  /* reserved/system (SVC, PendSV, SysTick) */
    .word default_handler
    .endr
    /* 32 external IRQ slots. Each is a weak symbol so Mojo application
     * code overrides it at link time by exporting a C-ABI function of
     * the same name:  @export("isr_irq0") def handler() abi("C")     */
    .irp n, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
    .word isr_irq\n
    .endr

    .irp n, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
    .weak isr_irq\n
    .thumb_set isr_irq\n, default_handler
    .endr

/* --- reset: init .data/.bss, call into Mojo ------------------------ */
.text
.thumb_func
.global reset_handler
reset_handler:
    /* copy .data from flash to RAM */
    ldr r0, =_sidata
    ldr r1, =_sdata
    ldr r2, =_edata
1:  cmp r1, r2
    bcs 2f
    ldmia r0!, {r3}
    stmia r1!, {r3}
    b 1b
2:
    /* zero .bss */
    ldr r1, =_sbss
    ldr r2, =_ebss
    movs r3, #0
3:  cmp r1, r2
    bcs 4f
    stmia r1!, {r3}
    b 3b
4:
    bl mojo_main
    /* mojo_main should never return; park the core if it does */
hang:
    wfi
    b hang

.thumb_func
default_handler:
    b default_handler

/* --- core 1 support -------------------------------------------------
 * pico.multicore reads {trampoline, stack} from .core1_meta (linked at
 * 0x100001C0, right after the vector table) and feeds them through the
 * bootrom's SIO-FIFO wake-up handshake. The trampoline calls the weak
 * mojo_core1_main, which application code overrides via
 *   @export("mojo_core1_main") def core1() abi("C")
 */
.section .core1_meta, "a"
.global __core1_meta
__core1_meta:
    .word core1_trampoline
    .word _core1_stack_top

.text
.thumb_func
core1_trampoline:
    bl mojo_core1_main
5:  wfe
    b 5b

.weak mojo_core1_main
.thumb_set mojo_core1_main, default_handler

/* sev from Mojo (no inline asm there): wakes core 1 out of wfe */
.thumb_func
.global pico_sev
pico_sev:
    sev
    bx lr

/* --- stdlib assert/io externs -> debugger trap ----------------------
 * Mojo's runtime safety checks (e.g. InlineArray bounds) reference a
 * tiny printf path. There is no OS here: any of these firing means a
 * bug, so they all trap into the debugger (bkpt), or HardFault-halt
 * when no debugger is attached.
 */
.thumb_func
__pico_mojo_trap:
    bkpt #0
    b __pico_mojo_trap

.macro stub name
.global \name
.thumb_set \name, __pico_mojo_trap
.endm

stub dup
stub fdopen
stub fclose
stub fflush
stub fwrite
stub write
stub putchar
stub abort
stub exit
stub KGEN_CompilerRT_fprintf
stub KGEN_CompilerRT_AlignedAlloc
stub KGEN_CompilerRT_AlignedFree

.section .note.GNU-stack, "", %progbits
