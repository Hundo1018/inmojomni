/* On-target benchmarks (C side) — mirror of bench.mojo / bench.rs.
 * Built twice: arm-none-eabi-gcc -O2 and clang -O2 (same LLVM backend as
 * the Mojo pipeline); same crt0/link.ld, same clocks, same 1 MHz timer.
 *
 * Scratch buffers live at fixed RAM addresses (identical in every
 * language) and are accessed through plain, non-volatile pointers so the
 * optimizer is equally free in all implementations. Only MMIO, the
 * mailbox and FIB_N are volatile.
 */
#include <stdint.h>

#define REG(a) (*(volatile uint32_t *)(a))

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

static inline uint32_t time_us(void) { return REG(0x40054028); }

#define MB       0x20030000u
#define COUNT    9u
#define RUNS     3u
#define CRC_BUF  ((uint32_t *)0x20020000u)   /* 1024 u32 (4 KB) */
#define SORT_BUF ((uint32_t *)0x20021000u)   /* 512 u32 */
#define MAT_A    ((uint32_t *)0x20022000u)   /* 16x16 u32 each */
#define MAT_B    ((uint32_t *)0x20022400u)
#define MAT_C    ((uint32_t *)0x20022800u)
#define FIB_N    0x20023000u                 /* volatile: no const folding */

static inline uint32_t step(uint32_t x) {
    x ^= x << 13; x ^= x >> 17; x ^= x << 5;
    return x;
}

static uint32_t bm_gpio_toggle(uint32_t *ck) {
    REG(0x4001407C) = 5;                 /* GPIO15 CTRL = FUNCSEL SIO */
    REG(0xD0000024) = 1u << 15;          /* OE set */
    uint32_t t0 = time_us();
    for (uint32_t i = 0; i < 100000; i++)
        REG(0xD000001C) = 1u << 15;      /* OUT XOR */
    uint32_t dt = time_us() - t0;
    *ck = 0;                             /* no checksum for I/O */
    return dt;
}

static uint32_t bm_xorshift(uint32_t *ck) {
    uint32_t x = 0xDEADBEEF;
    uint32_t t0 = time_us();
    for (uint32_t i = 0; i < 200000; i++)
        x = step(x);
    uint32_t dt = time_us() - t0;
    *ck = x;
    return dt;
}

static uint32_t bm_div(uint32_t *ck) {
    uint32_t acc = 0, d = 1;
    uint32_t t0 = time_us();
    for (uint32_t i = 0; i < 50000; i++) {
        acc += 1000000u / d;
        d = (d + i) | 1;
    }
    uint32_t dt = time_us() - t0;
    *ck = acc;
    return dt;
}

static uint32_t bm_f32(uint32_t *ck) {
    float sum = 0.0f, a = 1.5f;
    uint32_t t0 = time_us();
    for (uint32_t i = 0; i < 20000; i++) {
        sum += a * 1.000119f;
        a = sum * 0.5f + a;
    }
    uint32_t dt = time_us() - t0;
    *ck = (sum > 1.0f);
    return dt;
}

__attribute__((noinline)) static uint32_t add_one(uint32_t x) { return x + 1; }

static uint32_t bm_call(uint32_t *ck) {
    uint32_t x = 0;
    uint32_t t0 = time_us();
    for (uint32_t i = 0; i < 100000; i++)
        x = add_one(x);
    uint32_t dt = time_us() - t0;
    *ck = x;
    return dt;
}

static uint32_t bm_crc32(uint32_t *ck) {
    uint32_t *buf = CRC_BUF;
    uint32_t x = 0x12345678;
    for (uint32_t i = 0; i < 1024; i++) {
        x = step(x);
        buf[i] = x;
    }
    uint32_t acc = 0;
    uint32_t t0 = time_us();
    for (uint32_t k = 0; k < 4; k++) {
        uint32_t crc = 0xFFFFFFFFu ^ k;
        for (uint32_t i = 0; i < 1024; i++) {
            uint32_t w = buf[i];
            for (uint32_t b = 0; b < 4; b++) {
                crc ^= (w >> (8 * b)) & 0xFF;
                for (uint32_t r = 0; r < 8; r++)
                    crc = (crc >> 1) ^ (0xEDB88320u & (0u - (crc & 1u)));
            }
        }
        acc ^= ~crc;
    }
    uint32_t dt = time_us() - t0;
    *ck = acc;
    return dt;
}

static void qsort_u32(uint32_t *a, int32_t lo, int32_t hi) {
    if (lo >= hi)
        return;
    uint32_t p = a[hi];
    int32_t i = lo;
    for (int32_t j = lo; j < hi; j++) {
        if (a[j] < p) {
            uint32_t t = a[i]; a[i] = a[j]; a[j] = t;
            i++;
        }
    }
    uint32_t t = a[i]; a[i] = a[hi]; a[hi] = t;
    qsort_u32(a, lo, i - 1);
    qsort_u32(a, i + 1, hi);
}

static uint32_t bm_sort(uint32_t *ck) {
    uint32_t *a = SORT_BUF;
    uint32_t acc = 0;
    uint32_t t0 = time_us();
    for (uint32_t rep = 0; rep < 20; rep++) {
        uint32_t x = 0x00C0FFEEu + rep;
        for (uint32_t i = 0; i < 512; i++) {
            x = step(x);
            a[i] = x;
        }
        qsort_u32(a, 0, 511);
        acc += a[0] ^ a[255] ^ a[511];
    }
    uint32_t dt = time_us() - t0;
    *ck = acc;
    return dt;
}

static uint32_t bm_mat16(uint32_t *ck) {
    uint32_t *A = MAT_A, *B = MAT_B, *C = MAT_C;
    uint32_t x = 0x600D5EED;
    for (uint32_t i = 0; i < 256; i++) { x = step(x); A[i] = x; }
    for (uint32_t i = 0; i < 256; i++) { x = step(x); B[i] = x; }
    uint32_t acc = 0;
    uint32_t t0 = time_us();
    for (uint32_t rep = 0; rep < 50; rep++) {
        for (uint32_t i = 0; i < 16; i++) {
            for (uint32_t j = 0; j < 16; j++) {
                uint32_t s = 0;
                for (uint32_t k = 0; k < 16; k++)
                    s += A[i * 16 + k] * B[k * 16 + j];
                C[i * 16 + j] = s;
            }
        }
        A[rep] ^= C[rep];
        acc ^= C[0] + C[255];
    }
    uint32_t dt = time_us() - t0;
    *ck = acc;
    return dt;
}

static uint32_t fib(uint32_t n) {
    if (n < 2)
        return n;
    return fib(n - 1) + fib(n - 2);
}

static uint32_t bm_fib(uint32_t *ck) {
    uint32_t n = REG(FIB_N);   /* volatile read: opaque to the optimizer */
    uint32_t t0 = time_us();
    uint32_t r = fib(n);
    uint32_t dt = time_us() - t0;
    *ck = r;
    return dt;
}

typedef uint32_t (*bm_fn)(uint32_t *);
static const bm_fn BMS[COUNT] = {
    bm_gpio_toggle, bm_xorshift, bm_div, bm_f32, bm_call,
    bm_crc32, bm_sort, bm_mat16, bm_fib,
};

void mojo_main(void) {
    board_init();
    REG(MB + 0x00) = 0x42454E43;
    REG(MB + 0x04) = 1;
    REG(MB + 0x08) = COUNT;
    REG(MB + 0x0C) = RUNS;
    REG(FIB_N) = 24;

    for (uint32_t run = 0; run < RUNS; run++) {
        for (uint32_t i = 0; i < COUNT; i++) {
            uint32_t ck = 0;
            uint32_t us = BMS[i](&ck);
            uint32_t base = MB + 0x10 + (run * COUNT + i) * 8;
            REG(base) = us;
            REG(base + 4) = ck;
        }
    }

    REG(MB + 0x04) = 2;
    for (;;) {}
}
