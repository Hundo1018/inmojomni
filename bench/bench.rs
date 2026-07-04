//! On-target benchmarks (Rust side) — mirror of bench.mojo / bench.c.
//!
//! Built as a #![no_std] staticlib for thumbv6m-none-eabi and linked with
//! the same crt0.S / link.ld / libgcc as every other implementation; the
//! entry point is `mojo_main`, called by crt0 exactly like the Mojo and C
//! firmwares. Scratch buffers live at fixed RAM addresses (identical in
//! every language) and are accessed through plain, non-volatile pointers.
//! Only MMIO, the mailbox and FIB_N are volatile.

#![no_std]

use core::panic::PanicInfo;
use core::ptr::{read_volatile, write_volatile};

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    loop {}
}

#[inline(always)]
fn reg_write(a: u32, v: u32) {
    unsafe { write_volatile(a as *mut u32, v) }
}

#[inline(always)]
fn reg_read(a: u32) -> u32 {
    unsafe { read_volatile(a as *const u32) }
}

/* --- minimal board init: identical sequence to pico.board.init() --- */
fn board_init() {
    reg_write(0x4002400C, 47); /* XOSC STARTUP */
    reg_write(0x40024000, (0xFAB << 12) | 0xAA0); /* XOSC enable */
    while reg_read(0x40024004) & 0x8000_0000 == 0 {}
    reg_write(0x40008030, 2); /* clk_ref <- xosc */
    while reg_read(0x40008038) != 1 << 2 {}
    reg_write(0x4000803C, 0); /* clk_sys <- clk_ref */
    while reg_read(0x40008044) != 1 {}
    reg_write(0x4000C000 + 0x3000, (1 << 5) | (1 << 8) | (1 << 21));
    let mask = (1 << 5) | (1 << 8) | (1 << 21);
    while reg_read(0x4000C008) & mask != mask {}
    reg_write(0x4005802C, (1 << 9) | 12); /* 1 MHz tick */
}

#[inline(always)]
fn time_us() -> u32 {
    reg_read(0x40054028)
}

const MB: u32 = 0x2003_0000;
const COUNT: u32 = 9;
const RUNS: u32 = 3;
const CRC_BUF: u32 = 0x2002_0000; /* 1024 u32 (4 KB) */
const SORT_BUF: u32 = 0x2002_1000; /* 512 u32 */
const MAT_A: u32 = 0x2002_2000; /* 16x16 u32 each */
const MAT_B: u32 = 0x2002_2400;
const MAT_C: u32 = 0x2002_2800;
const FIB_N: u32 = 0x2002_3000; /* volatile: no const folding */

#[inline(always)]
fn step(mut x: u32) -> u32 {
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    x
}

fn bm_gpio_toggle() -> (u32, u32) {
    reg_write(0x4001407C, 5); /* GPIO15 CTRL = FUNCSEL SIO */
    reg_write(0xD0000024, 1 << 15); /* OE set */
    let t0 = time_us();
    for _ in 0..100_000u32 {
        reg_write(0xD000001C, 1 << 15); /* OUT XOR */
    }
    (time_us().wrapping_sub(t0), 0) /* no checksum for I/O */
}

fn bm_xorshift() -> (u32, u32) {
    let mut x: u32 = 0xDEADBEEF;
    let t0 = time_us();
    for _ in 0..200_000u32 {
        x = step(x);
    }
    (time_us().wrapping_sub(t0), x)
}

fn bm_div() -> (u32, u32) {
    let mut acc: u32 = 0;
    let mut d: u32 = 1;
    let t0 = time_us();
    for i in 0..50_000u32 {
        acc = acc.wrapping_add(1_000_000 / d);
        d = d.wrapping_add(i) | 1;
    }
    (time_us().wrapping_sub(t0), acc)
}

fn bm_f32() -> (u32, u32) {
    let mut sum: f32 = 0.0;
    let mut a: f32 = 1.5;
    let t0 = time_us();
    for _ in 0..20_000u32 {
        sum += a * 1.000119;
        a = sum * 0.5 + a;
    }
    (time_us().wrapping_sub(t0), (sum > 1.0) as u32)
}

#[inline(never)]
fn add_one(x: u32) -> u32 {
    x + 1
}

fn bm_call() -> (u32, u32) {
    let mut x: u32 = 0;
    let t0 = time_us();
    for _ in 0..100_000u32 {
        x = add_one(x);
    }
    (time_us().wrapping_sub(t0), x)
}

fn bm_crc32() -> (u32, u32) {
    let buf = CRC_BUF as *mut u32;
    let mut x: u32 = 0x12345678;
    for i in 0..1024usize {
        x = step(x);
        unsafe { *buf.add(i) = x };
    }
    let mut acc: u32 = 0;
    let t0 = time_us();
    for k in 0..4u32 {
        let mut crc: u32 = 0xFFFF_FFFF ^ k;
        for i in 0..1024usize {
            let w = unsafe { *buf.add(i) };
            for b in 0..4u32 {
                crc ^= (w >> (8 * b)) & 0xFF;
                for _ in 0..8 {
                    crc = (crc >> 1) ^ (0xEDB8_8320 & 0u32.wrapping_sub(crc & 1));
                }
            }
        }
        acc ^= !crc;
    }
    (time_us().wrapping_sub(t0), acc)
}

unsafe fn qsort_u32(a: *mut u32, lo: i32, hi: i32) {
    if lo >= hi {
        return;
    }
    let p = *a.offset(hi as isize);
    let mut i = lo;
    for j in lo..hi {
        if *a.offset(j as isize) < p {
            let t = *a.offset(i as isize);
            *a.offset(i as isize) = *a.offset(j as isize);
            *a.offset(j as isize) = t;
            i += 1;
        }
    }
    let t = *a.offset(i as isize);
    *a.offset(i as isize) = *a.offset(hi as isize);
    *a.offset(hi as isize) = t;
    qsort_u32(a, lo, i - 1);
    qsort_u32(a, i + 1, hi);
}

fn bm_sort() -> (u32, u32) {
    let a = SORT_BUF as *mut u32;
    let mut acc: u32 = 0;
    let t0 = time_us();
    for rep in 0..20u32 {
        let mut x: u32 = 0x00C0_FFEE + rep;
        for i in 0..512usize {
            x = step(x);
            unsafe { *a.add(i) = x };
        }
        unsafe { qsort_u32(a, 0, 511) };
        acc = acc.wrapping_add(unsafe { *a.add(0) ^ *a.add(255) ^ *a.add(511) });
    }
    (time_us().wrapping_sub(t0), acc)
}

fn bm_mat16() -> (u32, u32) {
    let ma = MAT_A as *mut u32;
    let mb = MAT_B as *mut u32;
    let mc = MAT_C as *mut u32;
    let mut x: u32 = 0x600D_5EED;
    for i in 0..256usize {
        x = step(x);
        unsafe { *ma.add(i) = x };
    }
    for i in 0..256usize {
        x = step(x);
        unsafe { *mb.add(i) = x };
    }
    let mut acc: u32 = 0;
    let t0 = time_us();
    for rep in 0..50usize {
        for i in 0..16usize {
            for j in 0..16usize {
                let mut s: u32 = 0;
                for k in 0..16usize {
                    s = s.wrapping_add(unsafe {
                        (*ma.add(i * 16 + k)).wrapping_mul(*mb.add(k * 16 + j))
                    });
                }
                unsafe { *mc.add(i * 16 + j) = s };
            }
        }
        unsafe { *ma.add(rep) ^= *mc.add(rep) };
        acc ^= unsafe { (*mc.add(0)).wrapping_add(*mc.add(255)) };
    }
    (time_us().wrapping_sub(t0), acc)
}

fn fib(n: u32) -> u32 {
    if n < 2 {
        n
    } else {
        fib(n - 1).wrapping_add(fib(n - 2))
    }
}

fn bm_fib() -> (u32, u32) {
    let n = reg_read(FIB_N); /* volatile read: opaque to the optimizer */
    let t0 = time_us();
    let r = fib(n);
    (time_us().wrapping_sub(t0), r)
}

#[no_mangle]
pub extern "C" fn mojo_main() -> ! {
    board_init();
    reg_write(MB, 0x42454E43); /* "BENC" */
    reg_write(MB + 0x04, 1);
    reg_write(MB + 0x08, COUNT);
    reg_write(MB + 0x0C, RUNS);
    reg_write(FIB_N, 24);

    let bms: [fn() -> (u32, u32); COUNT as usize] = [
        bm_gpio_toggle,
        bm_xorshift,
        bm_div,
        bm_f32,
        bm_call,
        bm_crc32,
        bm_sort,
        bm_mat16,
        bm_fib,
    ];

    for run in 0..RUNS {
        for (i, bm) in bms.iter().enumerate() {
            let (us, ck) = bm();
            let base = MB + 0x10 + (run * COUNT + i as u32) * 8;
            reg_write(base, us);
            reg_write(base + 4, ck);
        }
    }

    reg_write(MB + 0x04, 2); /* done */
    loop {}
}
