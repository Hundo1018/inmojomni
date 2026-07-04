# Benchmarks

Only numbers we actually measured are reported, with the full measurement
conditions stated. Anything we did not measure is explicitly marked as such.

## Methodology

- One Raspberry Pi Pico (RP2040 at 12 MHz XOSC, no PLL) for all runs.
- Identical `runtime/crt0.S`, `runtime/link.ld` and clock bring-up for every
  firmware; identical fixed-address RAM scratch buffers in every language.
- Timing by the same 1 MHz hardware timer (µs resolution).
- **Three full-suite runs per firmware.** The host reports medians, requires
  cross-run spread < 2%, and requires checksums to be identical across runs
  and across all four languages. (The spread gate has already caught a real
  contamination source: polling the mailbox over SWD while the suite runs
  steals ~6 ms of AHB bus time per probe-rs attach, so the driver sleeps
  through the run and reads results only afterwards.)
- Every workload writes a checksum; identical checksums prove every language
  did the same work on the same data (shared PRNG, shared seeds).
- Compilers, all targeting Cortex-M0+ and linked by arm-none-eabi-gcc with
  the same crt0/link.ld/libgcc:
  - Mojo: `mojo build --emit=llvm` (riscv32) → IR retarget → system
    `opt`/`llc -O2` (LLVM 18). Mojo 1.0.0b3 nightly (2026-07-03).
  - C: `arm-none-eabi-gcc -O2` (GCC 13.2) — the conventional embedded baseline.
  - C: `clang -O2 --target=armv6m-none-eabi` (clang 18.1) — **the same LLVM
    backend the Mojo pipeline uses**; this column isolates language overhead.
  - Rust: `rustc 1.89 --crate-type staticlib -C opt-level=2
    -C codegen-units=1 -C panic=abort` for `thumbv6m-none-eabi` (also
    LLVM). Note: Rust bundles its own `compiler_builtins` in the staticlib,
    so its software division and float intrinsics are not libgcc's — see
    interpretation note 4.
- Reproduce: `pixi run bench`, then `pixi run chart` for the SVG
  (requires a CMSIS-DAP probe, `clang`, and `rustc` with the
  `thumbv6m-none-eabi` target installed).

## Results (measured 2026-07-04)

![Benchmark chart](assets/benchmarks.svg)

| Workload | Mojo µs | C gcc µs | C clang µs | Rust µs | Mojo/gcc | **Mojo/clang** |
|---|---:|---:|---:|---:|---:|---:|
| 100k GPIO toggles (SIO XOR, volatile) | 8,834 | 41,668 | 8,835 | 8,835 | **0.21** | **1.00** |
| 200k xorshift32 rounds | 102,501 | 166,668 | 102,501 | 102,501 | **0.62** | **1.00** |
| 50k u32 divisions (software divide) | 109,673 | 110,923 | 111,756 | 211,686 | 0.99 | 0.98 |
| 20k float32 mul-adds (soft-float) | 598,833 | 609,566 | 596,815 | 525,915 | 0.98 | 1.00 |
| 100k noinline function calls | 75,001 | 83,334 | 75,001 | 133,334 | 0.90 | 1.00 |
| CRC-32 over 4 KB ×4 (bitwise) | 68,958 | 114,012 | 81,246 | 71,690 | 0.60 | **0.85** |
| quicksort 512 u32 ×20 | 230,148 | 164,060 | 204,537 | 204,484 | 1.40 | **1.13** |
| 16×16 u32 matmul ×50 | 137,951 | 193,652 | 159,201 | 139,127 | 0.71 | **0.87** |
| recursive fib(24) | 161,079 | 171,437 | 167,330 | 167,331 | 0.94 | 0.96 |

Checksums: identical across all three runs of each firmware and across all
four languages, for every workload.

### Interpretation

1. **Microbenchmarks: exact parity with same-backend C.** The five
   register-loop workloads land at 0.98–1.00× of clang C; the xorshift and
   GPIO loops are equal *to the microsecond* across Mojo, clang C and Rust —
   the backend emits the same inner loop for all three. No interpreter, no
   GC, no hidden runtime, measured rather than claimed.
2. **Larger workloads: ±13%, no cliff.** With 4 KB working sets, recursion
   and nested loops, Mojo lands at 0.85× (CRC-32), 0.87× (matmul), 0.96×
   (fib) and 1.13× (quicksort) of clang C. Performance does not degrade as
   programs grow; individual workloads swing both ways, which is ordinary
   optimizer variance (loop unrolling and if-conversion decisions), not a
   language tax.
3. **The gcc gaps are backend differences, not language differences.** gcc
   does not unroll the volatile GPIO store loop (4.7× slower) and makes
   different unrolling choices on xorshift/CRC-32 — but it wins quicksort
   (0.80× of clang). This is LLVM 18 vs GCC 13, visible because the clang
   column tracks Mojo almost exactly.
4. **The Rust outliers are runtime-library differences.** Rust's staticlib
   links its own `compiler_builtins`: its software u32 division is ~1.9×
   slower than libgcc's `__aeabi_uidiv`, while its float32 multiply-add path
   is ~12% faster than libgcc's. Those two rows compare intrinsic libraries,
   not languages. The noinline-call row (1.78× of clang) is a code-alignment
   artifact of a 3-instruction loop on XIP flash — see note 5.
5. **Absolute numbers depend on flash code layout.** Code executes from QSPI
   flash through the RP2040 XIP cache; whether a tight loop straddles a fetch
   boundary changes its cost by a cycle or two per iteration, which is
   visible at 100k iterations. Cross-firmware differences under ~15% on tight
   loops should be read with that in mind; the checksum equality proves the
   work done is identical.
6. Bare metal, no interrupts: execution is deterministic (cross-run spread
   here is 0–2 µs on most workloads). A later startup-code change shifted
   every firmware by 20 bytes and reproduced all nine timings within 1 µs.

## Binary size (measured)

All firmwares below share the identical rig — crt0.S, link.ld, 256 B boot2,
192 B vector table, dual-core launch metadata, and the same clock bring-up —
so the size comparison is apples to apples. The blink counterparts implement
exactly the behavior of `src/main.mojo`; reproduce with `pixi run sizes`.

| Firmware | .text | Notes |
|---|---:|---|
| blink — C (gcc -O2) | 712 B | gcc leaves the wait loops rolled |
| blink — **Mojo** | **780 B** | identical size to same-backend C |
| blink — C (clang -O2) | 780 B | LLVM unrolls the timer wait loop |
| blink — Rust (opt-level=2) | 784 B | |
| benchmark — C (gcc) | 4,916 B | 9 workloads + clock bring-up |
| benchmark — Rust | 6,386 B | same, plus compiler_builtins intrinsics |
| benchmark — Mojo | 6,608 B | same, plus stdlib assert machinery (below) |
| benchmark — C (clang) | 7,420 B | same `bench.c` as gcc; clang unrolls/aligns more aggressively |

**The cost of safety:** once bounds-checked standard-library features (such as
`InlineArray` indexing) are used, Mojo firmware grows by roughly 1.5–5 KB of
assert/formatting machinery. This project routes its output to a `bkpt` trap,
so a violation halts straight into the attached debugger. C has no such checks
and therefore none of this cost. With 2 MB of flash it rarely matters; where it
does, unsafe accessors avoid it.

## MicroPython / CircuitPython — not measured

Measuring them requires reflashing the board with their firmware (physical
BOOTSEL button) and driving it over a USB REPL, which is mutually exclusive
with this rig (SWD probe, our own firmware). **No first-hand numbers are
reported here.** Published figures for interpreted Python on register-toggle
loops of this kind are typically 2–3 orders of magnitude slower than C
(`machine.Pin` toggling is commonly reported in the tens of kHz, versus
~11 MHz for Mojo in the table above); `@micropython.native`/`viper` narrows
the gap. A first-hand comparison is planned once a second board is available.

## Qualitative comparison (opinion, not measurement)

| Aspect | Mojo (this toolchain) | C | Rust | MicroPython |
|---|---|---|---|---|
| Memory safety | bounds checks on by default (violation → `bkpt`); `UnsafePointer` marks unsafe boundaries explicitly | none | borrow checker + unsafe boundaries | interpreter-level safety |
| Compile-time hardware checks | `Pin[30]()` is a **compile error** (comptime assert); pins/PIO/SM are type parameters | none (fails at run time) | achievable via typestate, heavier code | none |
| Zero-cost abstraction | measured: the `rp2040.mojo` register map folds to immediates, 780 B blink | yes (by hand) | yes | no |
| Predictability | no GC, no hidden allocation; some stdlib features pull in assert machinery (visible in the link map) | highest | high | GC pauses, heap fragmentation |
| Readability | Python-like syntax with types; PIO written as method calls | macro and bit-shift heavy | expressive, steep learning curve | most approachable |
| Debugging | F5 breakpoints/stepping/registers/SVD + RTT logging (both verified in this project) | mature | mature | mostly print |
| Ecosystem maturity | **experimental** (this project + a nightly compiler; language pre-1.0) | most mature | mature | mature |

The last row is the most important caveat: choosing Mojo for an MCU today means
working at the frontier; choosing C or Rust means shipping a product. The goal
of this project is to close that gap.
