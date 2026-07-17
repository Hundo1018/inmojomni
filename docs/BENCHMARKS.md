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
    `opt`/`llc -O2` (LLVM 18). Mojo 1.0.0b3 nightly (2026-07-04).
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

## RP2350 / Pico 2 results (measured 2026-07-17)

The same nine kernel bodies, on the Pico 2's Hazard3 RISC-V cores.
Methodology differences from the RP2040 run, in fairness-relevant order:

- **ISA: rv32imac for all four languages** (hardware multiply/divide —
  matching the silicon instead of handicapping it). Mojo emits it natively
  (`--target-features=+m,+a,+c`); baselines are riscv-gcc `-O2`, clang `-O2`
  and Rust `-C opt-level=2` for `riscv32imac-unknown-none-elf`. All four link
  the same `crt0_rv32.S`, `link_rv32.ld` and the rv32imac `libgcc`.
- **Timing: the `mcycle` CSR** through one shared `read_mcycle` symbol.
  Results are CPU cycles: ratios are exact regardless of the ring
  oscillator's frequency drift (the board runs at the boot ROSC clock).
- **Result channel: flash mailbox + PICOBOOT.** The firmware commits its
  result page to a reserved flash sector and reboots into BOOTSEL, where the
  host reads it over USB. No debug probe, no button press, no polling that
  could steal bus cycles mid-run. (Verified on hardware: the RP2350 bootrom
  clears **all** of main SRAM on any reboot into BOOTSEL, and the Arm debug
  AP faults while the cores run RISC-V — an RP2040-style RAM mailbox is
  impossible on this path.)
- Same gates: checksums identical across runs and across languages
  (enforced), cross-run spread < 2% (enforced), a per-language id in the
  mailbox header so a stale page can never pass as a fresh result.

| Workload | Mojo | C (gcc) | C (clang) | Rust | Mojo / clang |
|---|---:|---:|---:|---:|---:|
| 100k GPIO toggles (volatile) | 300,013 | 300,013 | 300,011 | 300,012 | 1.00 |
| 200k xorshift32 rounds | 1,600,014 | 1,600,013 | 1,600,013 | 1,600,014 | 1.00 |
| 50k u32 divisions (hardware M) | 1,250,016 | 1,200,016 | 1,250,010 | 1,250,016 | 1.00 |
| 20k float32 mul-adds (soft-float) | 6,128,786 | 5,968,394 | 5,928,380 | 2,876,368 | 1.03 |
| 100k noinline function calls | 900,011 | 900,010 | 800,008 | 900,011 | 1.13 |
| CRC-32 over 4 KB ×4 (bitwise) | 1,187,884 | 1,110,053 | 630,846 | 626,741 | 1.88 |
| quicksort 512 u32 ×20 | 1,885,255 | 1,153,999 | 1,387,042 | 1,380,228 | 1.36 |
| 16×16 u32 matmul ×50 (hardware M) | 1,853,061 | 1,593,616 | 880,065 | 874,409 | 2.11 |
| recursive fib(24) | 1,961,602 | 1,372,190 | 1,886,573 | 2,018,912 | 1.04 |

*(cycles; medians of 3 runs; lower is better)*

### Interpretation (RP2350)

1. **The Hazard3 is cycle-deterministic.** Runs 2 and 3 agree to the cycle
   in all 36 firmware×workload cells; run 1 differs only through the cold
   XIP cache. This makes cycle counts unusually trustworthy here.
2. **Straight-line parity again.** GPIO, xorshift, division, soft-float and
   fib land at 1.00–1.04× of clang C — same picture as the RP2040.
3. **The nested-loop kernels are a real gap on this path.** CRC-32 runs at
   1.88× and matmul at 2.11× of clang C (quicksort 1.36×) — clearly larger
   than the same kernels' gap on the RP2040/Arm path (0.85×/0.87×/1.13×).
   Same LLVM family, same kernel source: the difference is in what the Mojo
   frontend hands the RISC-V backend for these loop nests. Reported as-is;
   an open item, not smoothed over.
4. **The Rust soft-float row compares libraries, not languages.** Rust's
   `compiler_builtins` f32 path is ~2.1× faster than the libgcc soft-float
   the other three link. Same caveat as the RP2040 run, opposite magnitude.
5. Firmware `.text`: Mojo 3,790 B — the smallest of the four (clang
   4,184 B, gcc 4,496 B, Rust 13,658 B, which drags in its own intrinsics).

Reproduce: `pixi run bench-rp2350` with a Pico 2 in BOOTSEL mode (no probe
needed), then `pixi run chart build/bench_rp2350_results.csv
docs/assets/benchmarks_rp2350.svg "<subtitle>"`.

## Language-feature measurements, RP2350 (measured 2026-07-17)

Sixteen on-silicon measurements of Mojo language mechanics (10k iterations
each, seeded through a volatile load so nothing constant-folds; every claim
below is enforced by a checksum or size assertion in the driver).
Reproduce: `pixi run features-rp2350`.

| Measurement | cycles/iter | Paired against | cycles/iter |
|---|---:|---|---:|
| trait-bound generic call | 6.03 | direct call | 6.04 |
| comptime-materialized LUT | 27.11 | recomputing inline | 11.04 |
| `comptime for` unrolled ×16 | 63.15 | runtime loop ×16 | 106.04 |
| `@no_inline` call | 9.04 | `@always_inline` | ~0 (loop strength-reduced) |

- **Traits are zero-cost**: the trait-generic and direct versions agree to
  0.2% (monomorphized; identical checksums).
- **A comptime lookup table is not free on an XIP part**: the table lives in
  flash, so each lookup pays the XIP path while the recomputation stays in
  registers — the LUT loses by 2.5×. Measure before caching.
- `size_of` reports 4/8/12 for packed u32 structs and 16 for
  `{3×u32, u8}` (tail padding to alignment).

**Struct-passing boundary** (by-value through an `@no_inline` call,
cycles/call):

| Argument | cycles/call |
|---|---:|
| 8 B `TrivialRegisterPassable` | 10.02 |
| 8 B plain struct (owned) | 10.05 |
| 16 B plain struct | 12.03 |
| 32 B plain struct | 16.06 |
| 64 B plain struct | 26.07 |
| returning a 16 B struct | 18.05 |

The register boundary sits at 8 bytes — the RISC-V ilp32 ABI's two argument
registers — and an 8-byte *memory* struct already passes as cheaply as a
`TrivialRegisterPassable` one. Beyond that, cost grows linearly with the
copy (~4 cycles per 16 bytes).

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
