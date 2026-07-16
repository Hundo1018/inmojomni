/* On-target benchmarks, RP2350 / Pico 2 (C side) — mirror of
 * bench_rp2350.mojo / bench_rp2350.rs; kernel bodies copied verbatim
 * from bench.c so checksums must agree. Built twice: riscv gcc -O2 and
 * clang -O2, both -march=rv32imac; same crt0_rv32.S, link_rv32.ld and
 * libgcc as every other implementation. Timing is the shared
 * read_mcycle symbol; results go out through the shared
 * flash_commit_reboot (see crt0_rv32.S for why SRAM cannot carry them).
 */
#include <stdint.h>

#define REG(a) (*(volatile uint32_t *)(a))

extern uint32_t read_mcycle(void);
extern void flash_commit_reboot(uint32_t off, const void *src, uint32_t len,
                                uint32_t flags);

/* --- minimal board init: identical sequence to pico.pico2.init() --- */
static void board_init(void) {
    /* de-reset IO_BANK0 + PADS_BANK0 (atomic clear alias), wait for ack */
    uint32_t mask = (1u << 6) | (1u << 9);
    REG(0x40020000 + 0x3000) = mask;
    while ((REG(0x40020008) & mask) != mask) {}
}

#define MB       0x20030000u
#define COUNT    9u
#define RUNS     3u
#define LANG_GCC   2u
#define LANG_CLANG 3u
#define CRC_BUF  ((uint32_t *)0x20020000u)   /* 1024 u32 (4 KB) */
#define SORT_BUF ((uint32_t *)0x20021000u)   /* 512 u32 */
#define MAT_A    ((uint32_t *)0x20022000u)   /* 16x16 u32 each */
#define MAT_B    ((uint32_t *)0x20022400u)
#define MAT_C    ((uint32_t *)0x20022800u)
#define FIB_N    0x20023000u                 /* volatile: no const folding */

#define MB_FLASH_OFF 0x003FF000u             /* last 4 KiB sector */

#ifdef __clang__
#define LANG LANG_CLANG
#else
#define LANG LANG_GCC
#endif

static inline uint32_t step(uint32_t x) {
    x ^= x << 13; x ^= x >> 17; x ^= x << 5;
    return x;
}

static uint32_t bm_gpio_toggle(uint32_t *ck) {
    REG(0x4002807C) = 5;                 /* IO_BANK0 GPIO15 CTRL = SIO */
    REG(0xD0000038) = 1u << 15;          /* OE set (RP2350 offsets) */
    REG(0x4003B040) = 1u << 8;           /* PADS GPIO15: clear ISO (clr alias) */
    uint32_t t0 = read_mcycle();
    for (uint32_t i = 0; i < 100000; i++)
        REG(0xD0000028) = 1u << 15;      /* OUT XOR */
    uint32_t dt = read_mcycle() - t0;
    *ck = 0;                             /* no checksum for I/O */
    return dt;
}

static uint32_t bm_xorshift(uint32_t *ck) {
    uint32_t x = 0xDEADBEEF;
    uint32_t t0 = read_mcycle();
    for (uint32_t i = 0; i < 200000; i++)
        x = step(x);
    uint32_t dt = read_mcycle() - t0;
    *ck = x;
    return dt;
}

static uint32_t bm_div(uint32_t *ck) {
    uint32_t acc = 0, d = 1;
    uint32_t t0 = read_mcycle();
    for (uint32_t i = 0; i < 50000; i++) {
        acc += 1000000u / d;
        d = (d + i) | 1;
    }
    uint32_t dt = read_mcycle() - t0;
    *ck = acc;
    return dt;
}

static uint32_t bm_f32(uint32_t *ck) {
    float sum = 0.0f, a = 1.5f;
    uint32_t t0 = read_mcycle();
    for (uint32_t i = 0; i < 20000; i++) {
        sum += a * 1.000119f;
        a = sum * 0.5f + a;
    }
    uint32_t dt = read_mcycle() - t0;
    *ck = (sum > 1.0f);
    return dt;
}

__attribute__((noinline)) static uint32_t add_one(uint32_t x) { return x + 1; }

static uint32_t bm_call(uint32_t *ck) {
    uint32_t x = 0;
    uint32_t t0 = read_mcycle();
    for (uint32_t i = 0; i < 100000; i++)
        x = add_one(x);
    uint32_t dt = read_mcycle() - t0;
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
    uint32_t t0 = read_mcycle();
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
    uint32_t dt = read_mcycle() - t0;
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
    uint32_t t0 = read_mcycle();
    for (uint32_t rep = 0; rep < 20; rep++) {
        uint32_t x = 0x00C0FFEEu + rep;
        for (uint32_t i = 0; i < 512; i++) {
            x = step(x);
            a[i] = x;
        }
        qsort_u32(a, 0, 511);
        acc += a[0] ^ a[255] ^ a[511];
    }
    uint32_t dt = read_mcycle() - t0;
    *ck = acc;
    return dt;
}

static uint32_t bm_mat16(uint32_t *ck) {
    uint32_t *A = MAT_A, *B = MAT_B, *C = MAT_C;
    uint32_t x = 0x600D5EED;
    for (uint32_t i = 0; i < 256; i++) { x = step(x); A[i] = x; }
    for (uint32_t i = 0; i < 256; i++) { x = step(x); B[i] = x; }
    uint32_t acc = 0;
    uint32_t t0 = read_mcycle();
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
    uint32_t dt = read_mcycle() - t0;
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
    uint32_t t0 = read_mcycle();
    uint32_t r = fib(n);
    uint32_t dt = read_mcycle() - t0;
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
    REG(MB + 0x10) = LANG;
    REG(FIB_N) = 24;

    for (uint32_t run = 0; run < RUNS; run++) {
        for (uint32_t i = 0; i < COUNT; i++) {
            uint32_t ck = 0;
            uint32_t cyc = BMS[i](&ck);
            uint32_t base = MB + 0x14 + (run * COUNT + i) * 8;
            REG(base) = cyc;
            REG(base + 4) = ck;
        }
    }

    REG(MB + 0x04) = 2;
    flash_commit_reboot(MB_FLASH_OFF, (const void *)MB, 256, 0);
    for (;;) {}
}
