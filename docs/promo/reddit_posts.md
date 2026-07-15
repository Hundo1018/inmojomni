# Reddit 草稿(兩個版本)

## r/embedded

Title: I wrote a bare-metal RP2040 firmware + SDK in Mojo (the AI language) —
here's what the numbers actually look like

[貼 docs/assets/hw-tests.png 當首圖 — r/embedded 允許圖文]

I know how "I rewrote firmware in <new language>" posts usually go, so let me
lead with the measurement rig instead of the language pitch.

Same board, same crt0/linker script/clock init for every firmware. Nine
workloads implemented identically in Mojo, C (built twice: gcc -O2 and
clang -O2), and Rust (opt-level=2). Three runs each, timed by the 1 MHz
hardware timer, and every workload writes a checksum that the host verifies is
identical across all four implementations — so nobody quietly skipped work.
The host also refuses results if cross-run spread exceeds 2% (this gate caught
a real contamination source: probe-rs steals ~6 ms of AHB bus time per attach,
so never poll SWD during a timing run).

Results: against clang C — the same LLVM backend, i.e. the fair comparison —
the register-loop benchmarks match to the microsecond, and the bigger
workloads (CRC-32 over 4 KB, quicksort, 16x16 matmul, recursive fib) land
within ±13% in both directions. The 4.7x "win" over gcc on volatile GPIO
toggles is loop unrolling, not magic, and the writeup says so. Blink firmware
is 780 bytes, identical to the clang C blink; Rust is 784.

The interesting engineering bit: Mojo's LLVM has no 32-bit ARM backend, so the
pipeline emits riscv32 IR (same ILP32 LE data model as ARMv6-M), retargets the
triple/datalayout, and feeds the system LLVM. Unit-tested, volatile-op count
verified end to end.

Everything is validated by 26 on-target tests over SWD per commit — including
NVIC dispatch, a genuinely contended dual-core spinlock test (2x20k increments
== exactly 40,000), UART loopback, and PIO with side-set. F5 debugging in
VS Code works in the Mojo sources via probe-rs.

Repo: https://github.com/Hundo1018/inmojomni

It's experimental (language is pre-1.0, tracks nightly), and there's no
I2C/SPI/DMA/USB yet. Happy to answer anything about the measurement setup —
that's the part I'd most like torn apart.

---

## r/rust

Title: Benchmarked Rust vs Mojo vs C on bare-metal RP2040 with a shared rig —
including a compiler_builtins vs libgcc surprise

[貼 docs/assets/benchmarks.png 當首圖]

While building a bare-metal Mojo SDK for the RP2040, I wanted a fair baseline,
so Rust joined the benchmark: same crt0.S, same linker script, same clock
init, no_std staticlib with `mojo_main` as the entry point, opt-level=2,
codegen-units=1. Nine workloads, three runs, checksums verified identical
across Mojo / gcc C / clang C / Rust.

Findings r/rust might find interesting:

- On the pure register loops, Rust, Mojo and clang C produce identical timings
  to the microsecond — same LLVM, same inner loop. No surprises, which is
  itself the result.
- Rust's u32 software division came out ~1.9x slower than everyone else's, and
  its float32 mul-add ~12% faster. Both turned out to be compiler_builtins vs
  libgcc: the staticlib bundles Rust's own intrinsics while the C/Mojo builds
  link libgcc's __aeabi_* routines. Those rows compare runtime libraries, not
  languages — worth knowing if you benchmark no_std code against C.
- Sizes on the identical rig: blink is 712 B (gcc) / 780 B (Mojo) / 780 B
  (clang) / 784 B (Rust).

Methodology, caveats (XIP flash alignment noise on tight loops, etc.) and all
the code: https://github.com/Hundo1018/inmojomni — bench/bench.rs is the Rust
side if you want to check my flags.
