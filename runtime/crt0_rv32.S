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

/* --- bootrom helpers (RP2350 datasheet §5.4; boot/bootrom_constants.h) ---
 * rom_reboot_bootsel(delay_ms): look up ROM_FUNC_REBOOT ('R'|'B'<<8 =
 * 0x4252, mask RT_FLAG_FUNC_RISCV=1) and call
 * reboot(BOOT_TYPE_BOOTSEL=2, delay_ms, 0, 0). The reboot is scheduled;
 * this returns and the caller spins until it fires. Used by test/bench
 * firmwares so the host can read results back over SWD in BOOTSEL
 * (the M33 debug AP is only alive there while a RISC-V image runs).
 */
.global rom_reboot_bootsel
rom_reboot_bootsel:
    addi sp, sp, -16
    sw   ra, 12(sp)
    sw   s0, 8(sp)
    sw   s1, 4(sp)
    mv   s0, a0              /* delay_ms */
    mv   s1, a1              /* extra reboot flags to OR in (e.g. 0x10) */
    li   a0, 0x4252          /* ROM_FUNC_REBOOT 'R','B' */
    li   a1, 1               /* RT_FLAG_FUNC_RISCV */
    /* RISC-V uses TABLE_LOOKUP_ENTRY at 0x7dfa (= BOOTROM_ENTRY_OFFSET
     * 0x7dfc - BOOTROM_WELL_KNOWN_PTR_SIZE 2): a 16-bit halfword whose
     * value IS the callable lookup address (pico-sdk bootrom.h: "on
     * RISC-V the code (a jmp) is actually embedded in the table").
     * NOT a 32-bit pointer, and NOT 0x7df8 (that is TABLE_LOOKUP_OFFSET,
     * the non-entry variant). rom_size_is_64k() is false on real
     * silicon (FPGA-only), so no +32k adjust. */
    li   t0, 0x7dfa
    lhu  t0, 0(t0)           /* 16-bit entry -> callable address */
    jalr ra, t0, 0
    beqz a0, 9f              /* lookup failed: bail */
    mv   t0, a0
    /* flags = 0x2 BOOTSEL | caller's extras (picoboot_constants.h).
     * Pass 0x10 REBOOT_TO_ARM to make the BOOTSEL session SWD-readable:
     * without it the cores stay RISC-V and the M33 debug AP faults on
     * every access (verified on hardware 2026-07-17). */
    ori  a0, s1, 0x2
    mv   a1, s0              /* delay_ms */
    li   a2, 0
    li   a3, 0
    jalr ra, t0, 0
9:  lw   ra, 12(sp)
    lw   s0, 8(sp)
    lw   s1, 4(sp)
    addi sp, sp, 16
    ret

/* read_mcycle(): Hazard3 cycle counter, for clock-independent timing.
 * Same symbol is linkable from every benchmark language (fairness). */
.global read_mcycle
read_mcycle:
    csrr a0, mcycle
    ret

/* --- flash result mailbox -----------------------------------------------
 * The RP2350 bootrom clears ALL of main SRAM on any reboot into BOOTSEL
 * (verified on hardware 2026-07-17: 10 probes across every bank read 0,
 * with and without an architecture switch), so results cannot ride SRAM
 * across a reboot. Flash is the persistent channel: firmware commits a
 * result page to a reserved sector, reboots to BOOTSEL, and the host
 * reads it back over PICOBOOT (tools/picoboot_read.py) — no probe, no
 * button press.
 *
 * flash_commit_reboot(a0=flash byte offset (4 KiB-aligned),
 *                     a1=source buffer in SRAM (256-aligned size),
 *                     a2=byte count (multiple of 256),
 *                     a3=extra reboot flags, e.g. 0x10 REBOOT_TO_ARM)
 * Never returns. Erases one 4 KiB sector at the offset, programs the
 * buffer, then reboots to BOOTSEL.
 *
 * Programming flash kills XIP, so no flash-resident code may run between
 * flash_exit_xip and the reboot: this routine lives in .ramfunc (copied
 * to RAM by the crt0 .data loop) and only calls ROM code. ROM functions
 * follow the RISC-V ABI, so s-registers hold the arguments across calls.
 * ROM lookup per bootrom.h: the u16 at 0x7dfa IS the callable entry.
 */
.macro _romlk code               /* a0 <- ROM function for \code */
    li   a0, \code
    li   a1, 1                   /* RT_FLAG_FUNC_RISCV */
    li   t0, 0x7dfa
    lhu  t0, 0(t0)
    jalr ra, t0, 0
.endm

.section .ramfunc, "ax"
.global flash_commit_reboot
flash_commit_reboot:
    mv   s0, a0              /* flash offset */
    mv   s1, a1              /* src buffer */
    mv   s2, a2              /* byte count */
    mv   s3, a3              /* extra reboot flags */
    _romlk 0x4649            /* 'I','F' connect_internal_flash */
    jalr ra, a0, 0
    _romlk 0x5845            /* 'E','X' flash_exit_xip */
    jalr ra, a0, 0
    _romlk 0x4552            /* 'R','E' flash_range_erase */
    mv   t1, a0
    mv   a0, s0
    li   a1, 4096            /* one sector */
    li   a2, 65536           /* block_size */
    li   a3, 0xD8            /* block erase cmd */
    jalr ra, t1, 0
    _romlk 0x5052            /* 'R','P' flash_range_program */
    mv   t1, a0
    mv   a0, s0
    mv   a1, s1
    mv   a2, s2
    jalr ra, t1, 0
    _romlk 0x4346            /* 'F','C' flash_flush_cache */
    jalr ra, a0, 0
    _romlk 0x4252            /* 'R','B' reboot */
    mv   t1, a0
    ori  a0, s3, 0x2         /* BOOTSEL | extras */
    li   a1, 100             /* ms until it fires */
    li   a2, 0
    li   a3, 0
    jalr ra, t1, 0
1:  j 1b                     /* park until the reboot fires */
