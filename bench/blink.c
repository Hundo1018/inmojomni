/* Minimal blink (C) — size-comparison counterpart of src/main.mojo.
 * Same crt0/link.ld, same clock bring-up, same LED-toggle-every-250ms
 * behavior; built with gcc -O2 and clang -O2 by tools/sizes.mojo.
 */
#include <stdint.h>

#define REG(a) (*(volatile uint32_t *)(a))

static void board_init(void) {
    REG(0x4002400C) = 47;                       /* XOSC STARTUP */
    REG(0x40024000) = (0xFAB << 12) | 0xAA0;    /* XOSC enable  */
    while (!(REG(0x40024004) & 0x80000000u)) {}
    REG(0x40008030) = 2;                        /* clk_ref <- xosc */
    while (REG(0x40008038) != (1u << 2)) {}
    REG(0x4000803C) = 0;                        /* clk_sys <- clk_ref */
    while (REG(0x40008044) != 1u) {}
    REG(0x4000C000 + 0x3000) = (1u << 5) | (1u << 8) | (1u << 21);
    uint32_t mask = (1u << 5) | (1u << 8) | (1u << 21);
    while ((REG(0x4000C008) & mask) != mask) {}
    REG(0x4005802C) = (1u << 9) | 12;           /* 1 MHz tick */
}

static inline uint32_t time_us(void) { return REG(0x40054028); }

void mojo_main(void) {
    board_init();
    REG(0x400140CC) = 5;                        /* GPIO25 CTRL = SIO */
    REG(0xD0000024) = 1u << 25;                 /* OE set */
    for (;;) {
        REG(0xD000001C) = 1u << 25;             /* OUT XOR */
        uint32_t t0 = time_us();
        while (time_us() - t0 < 250000u) {}
    }
}
