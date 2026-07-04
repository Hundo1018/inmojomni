//! Minimal blink (Rust) — size-comparison counterpart of src/main.mojo.
//! Same crt0/link.ld, same clock bring-up, same LED-toggle-every-250ms
//! behavior; built with -C opt-level=2 by tools/sizes.mojo.

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

fn board_init() {
    reg_write(0x4002400C, 47);
    reg_write(0x40024000, (0xFAB << 12) | 0xAA0);
    while reg_read(0x40024004) & 0x8000_0000 == 0 {}
    reg_write(0x40008030, 2);
    while reg_read(0x40008038) != 1 << 2 {}
    reg_write(0x4000803C, 0);
    while reg_read(0x40008044) != 1 {}
    reg_write(0x4000C000 + 0x3000, (1 << 5) | (1 << 8) | (1 << 21));
    let mask = (1 << 5) | (1 << 8) | (1 << 21);
    while reg_read(0x4000C008) & mask != mask {}
    reg_write(0x4005802C, (1 << 9) | 12);
}

#[inline(always)]
fn time_us() -> u32 {
    reg_read(0x40054028)
}

#[no_mangle]
pub extern "C" fn mojo_main() -> ! {
    board_init();
    reg_write(0x400140CC, 5); /* GPIO25 CTRL = SIO */
    reg_write(0xD0000024, 1 << 25); /* OE set */
    loop {
        reg_write(0xD000001C, 1 << 25); /* OUT XOR */
        let t0 = time_us();
        while time_us().wrapping_sub(t0) < 250_000 {}
    }
}
