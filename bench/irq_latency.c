/* IRQ -> GPIO latency gate, C side — mirror of bench/irq_latency.mojo.
 * Built by tools/irq_latency.mojo with arm-none-eabi-gcc -O2 and clang
 * -O2, each with the handler in XIP flash and (-DISR_IN_RAM) in SRAM.
 * Same crt0/link.ld, same clock bring-up (XOSC -> PLL_SYS 125 MHz), same
 * pins, same PIO program words, same three stores in the handler, same
 * main loop. See the Mojo file for the measurement and mailbox layout.
 */
#include <stdint.h>

#define REG(a) (*(volatile uint32_t *)(a))

#define PIN_A 15u
#define PIN_C 16u
#define N 10000u
#define RUNS 3u
#ifndef LANG_ID
#define LANG_ID 2u            /* 2 = gcc; the clang build passes -DLANG_ID=3 */
#endif

#define MB        0x20030000u
#define MAGIC     0x4952514Cu
#define SAMPLES   0x20010000u
#define IRQ_COUNT 0x20024000u

#define IO_BANK0  0x40014000u
#define INTR1     (IO_BANK0 + 0xF4u)       /* GPIO 8..15 raw events */
#define INTE1     (IO_BANK0 + 0x104u)      /* PROC0 enables, GPIO 8..15 */
#define A_EDGE_HIGH (1u << 31)             /* EDGE_HIGH of GPIO 15 */

#define PIO0      0x50200000u

/* --- minimal board init: identical sequence to pico.board.init() --- */
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

/* --- identical to pico.clocks.sys_clock_125mhz() -------------------- */
static void sys_clock_125mhz(void) {
    REG(0x4000C000 + 0x2000) = 1u << 12;        /* PLL_SYS into reset */
    REG(0x4000C000 + 0x3000) = 1u << 12;        /* ... and out again */
    while (!(REG(0x4000C008) & (1u << 12))) {}
    REG(0x40028000) = 1;                        /* CS.REFDIV = 1 */
    REG(0x40028008) = 125;                      /* FBDIV_INT: VCO 1500 MHz */
    REG(0x40028004 + 0x3000) = (1u << 0) | (1u << 5);  /* PWR: ~PD, ~VCOPD */
    while (!(REG(0x40028000) & 0x80000000u)) {} /* CS.LOCK */
    REG(0x4002800C) = (6u << 16) | (2u << 12);  /* PRIM: /6 /2 -> 125 MHz */
    REG(0x40028004 + 0x3000) = 1u << 3;         /* PWR: ~POSTDIVPD */
    REG(0x4000803C) = 0;                        /* CLK_SYS AUXSRC = pll_sys */
    REG(0x4000803C + 0x2000) = 1;               /* SRC = aux */
    while (REG(0x40008044) != (1u << 1)) {}
}

/* --- identical to pico.clocks.measure_khz() -------------------------- */
static uint32_t measure_khz(uint32_t src) {
    while (REG(0x40008098) & (1u << 8)) {}      /* FC0_STATUS.RUNNING */
    REG(0x40008080) = 12000;                    /* FC0_REF_KHZ */
    REG(0x40008090) = 10;                       /* FC0_INTERVAL */
    REG(0x40008084) = 0;                        /* FC0_MIN_KHZ */
    REG(0x40008088) = 0x1FFFFFFu;               /* FC0_MAX_KHZ */
    REG(0x40008094) = src;                      /* FC0_SRC: start */
    while (!(REG(0x40008098) & (1u << 4))) {}   /* DONE */
    return REG(0x4000809C) >> 5;
}

static inline uint32_t time_us(void) { return REG(0x40054028); }

static void sleep_us(uint32_t us) {
    uint32_t t0 = time_us();
    while (time_us() - t0 < us) {}
}

/* The PIO program, word for word what pico.pio.Asm emits for
 * tools/irq_latency.mojo's reference_program() (the host checks it). */
static const uint16_t PROG[7] = {
    0x200F,  /* 0: wait 0 gpio 15   arm: previous pulse over            */
    0x208F,  /* 1: wait 1 gpio 15   rising edge of the interrupt input  */
    0xA02B,  /* 2: mov x, ~null     x = 0xFFFFFFFF                      */
    0x00C5,  /* 3: jmp pin, 5       GPIO 16 high -> done                */
    0x0043,  /* 4: jmp x--, 3       else x--, loop (2 cycles/iteration) */
    0x4020,  /* 5: in x, 32         isr = x                             */
    0x8020,  /* 6: push block       RX FIFO <- x (count = ~x); wrap     */
};

#ifdef ISR_IN_RAM
__attribute__((section(".ramfunc.isr_irq13")))
#endif
void isr_irq13(void) {
    REG(0xD0000014) = 1u << PIN_C;              /* SIO OUT_SET: GPIO 16 high */
    REG(INTR1) = A_EDGE_HIGH;                   /* ack the latched edge */
    REG(IRQ_COUNT) = REG(IRQ_COUNT) + 1;
}

static void fail(uint32_t code) {
    REG(MB + 0x20) = code;
    REG(MB + 0x04) = 3;
    for (;;) {}
}

void mojo_main(void) {
    board_init();
    REG(MB + 0x00) = MAGIC;
    REG(MB + 0x04) = 1;
    REG(MB + 0x08) = N;
    REG(MB + 0x0C) = RUNS;
    REG(MB + 0x10) = LANG_ID;
    REG(MB + 0x1C) = 0;
    REG(MB + 0x20) = 0;
    sys_clock_125mhz();
    REG(MB + 0x14) = measure_khz(9);            /* FC0_SRC 9 = clk_sys */

    /* GPIO 15 and 16: FUNCSEL SIO, outputs, low (Pin[N]() + make_output + low) */
    REG(IO_BANK0 + 8 * PIN_A + 4) = 5;
    REG(IO_BANK0 + 8 * PIN_C + 4) = 5;
    REG(0xD0000018) = (1u << PIN_A) | (1u << PIN_C);   /* OUT_CLR */
    REG(0xD0000024) = (1u << PIN_A) | (1u << PIN_C);   /* OE_SET */

    /* PIO0 SM0 (StateMachine[0, 0]() + load + set_clkdiv + set_jmp_pin) */
    REG(0x4000C000 + 0x3000) = 1u << 10;        /* PIO0 out of reset */
    while (!(REG(0x4000C008) & (1u << 10))) {}
    for (uint32_t i = 0; i < 7; i++)
        REG(PIO0 + 0x048 + 4 * i) = PROG[i];
    REG(PIO0 + 0x0CC) = 6u << 12;               /* EXECCTRL: WRAP_TOP 6, BOTTOM 0 */
    REG(PIO0 + 0x0C8) = 1u << 16;               /* CLKDIV 1.0 */
    REG(PIO0 + 0x0CC) = (REG(PIO0 + 0x0CC) & ~(0x1Fu << 24)) | (PIN_C << 24);
    REG(MB + 0x60) = 7;
    for (uint32_t i = 0; i < 7; i++)
        REG(MB + 0x64 + 4 * i) = PROG[i];
    REG(PIO0 + 0x000) = REG(PIO0 + 0x000) | 1u; /* SM0 enable */

    REG(IRQ_COUNT) = 0;
    REG(INTR1) = 0xFu << 28;                    /* ack all GPIO 15 events */
    REG(INTE1 + 0x2000) = A_EDGE_HIGH;          /* route EDGE_HIGH to IO_IRQ_BANK0 */
    REG(0xE000E100) = 1u << 13;                 /* NVIC ISER: IO_IRQ_BANK0 */
    sleep_us(10);

    uint32_t total = 0;
    for (uint32_t r = 0; r < RUNS; r++) {
        uint32_t mn = 0xFFFFFFFFu, mx = 0, sum = 0;
        for (uint32_t i = 0; i < N; i++) {
            total++;
            REG(0xD0000014) = 1u << PIN_A;      /* GPIO 15 high: fires the IRQ */
            uint32_t spins = 0;
            while (REG(IRQ_COUNT) != total)
                if (++spins > 1000000u) fail(1);
            spins = 0;
            while ((REG(PIO0 + 0x004) >> 8) & 1u)   /* FSTAT.RXEMPTY0 */
                if (++spins > 1000000u) fail(2);
            uint32_t n = ~REG(PIO0 + 0x020);    /* RXF0 */
            REG(0xD0000018) = 1u << PIN_C;
            REG(0xD0000018) = 1u << PIN_A;
            if (n < mn) mn = n;
            if (n > mx) mx = n;
            sum += n;
            if (r == RUNS - 1) REG(SAMPLES + 4 * i) = n;
            if (r == 0 && i == 0) REG(MB + 0x18) = n;
            sleep_us(5);
        }
        uint32_t base = MB + 0x30 + 12 * r;
        REG(base) = mn;
        REG(base + 4) = mx;
        REG(base + 8) = sum;
    }

    REG(0xE000E180) = 1u << 13;                 /* NVIC ICER */
    REG(INTE1 + 0x3000) = 0xFu << 28;
    REG(MB + 0x1C) = total;
    REG(MB + 0x04) = 2;

    REG(IO_BANK0 + 8 * 25 + 4) = 5;             /* LED: slow blink */
    REG(0xD0000024) = 1u << 25;
    for (;;) {
        REG(0xD000001C) = 1u << 25;
        sleep_us(250000);
    }
}
