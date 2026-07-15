Title: Bare-metal Mojo on a $4 microcontroller — a pure-Mojo RP2040 firmware + SDK
Category: Community Showcase

---

Mojo is usually pointed at GPUs and AI kernels. I wanted to see how far the
other direction goes, so I wrote a bare-metal firmware **and** peripheral SDK
for the Raspberry Pi Pico (RP2040, a dual Cortex-M0+) in pure Mojo — no OS, no
C application layer. The whole application plus SDK is Mojo; startup is ~60
lines of assembly and one linker script.

Repo: https://github.com/Hundo1018/inmojomni

📷 **[IMAGE 1 — docs/assets/hw-tests.png]** *(hero: the on-hardware test suite, all green)*

A complete blink is **780 bytes**, and it turns out that's byte-for-byte the
size of the same blink compiled with `clang -O2` on the identical rig. Blinking
an LED looks like this:

```mojo
import pico
from pico import Pin, pins, sleep_ms


@export("mojo_main")
def start() abi("C"):
    pico.init()

    var led = Pin[pins.LED]()   # pin number is a compile-time parameter;
    led.make_output()           # Pin[99]() is a compile-time error

    while True:
        led.toggle()
        sleep_ms(250)
```

## The trick that makes it possible

📷 **[IMAGE 2 — docs/assets/pipeline.png]** *(the retarget pipeline)*

The bundled Mojo LLVM has no 32-bit ARM backend, so `mojo build` can't target
Cortex-M0+ directly. The workaround is a source-to-source-ish pipeline at the
IR level:

1. `mojo build --emit=llvm` targeting **riscv32** — it shares the exact ILP32
   little-endian data model of ARMv6-M, so the emitted IR is layout-compatible.
2. Rewrite the target triple + datalayout to `thumbv6m-none-eabi`, and downgrade
   the handful of IR constructs the *system* LLVM (18) doesn't understand yet
   (`captures(none)`, `#dbg_*` records, `f0x` float literals, single-arg
   lifetime intrinsics).
3. System `opt -O2` / `llc -O2` → Cortex-M0+ object.
4. `arm-none-eabi-gcc` links it with crt0 + linker script + boot2 + libgcc.

The retarget pass is guarded by unit tests, `opt -verify`, and a check that the
number of volatile ops is preserved end to end. When a nightly emits new IR
syntax, supporting it is usually one more rewrite rule. (The whole pipeline
driver is itself a Mojo program, not a shell script.)

## What's measured, honestly

📷 **[IMAGE 3 — docs/assets/benchmarks.png]** *(9 workloads × 4 languages, normalized to clang C)*

I didn't want to hand-wave the performance claim, so the benchmark builds the
same 9 workloads four ways — Mojo, `gcc -O2`, `clang -O2` (same LLVM backend as
Mojo, which is the fair yardstick for *language* overhead), and Rust
`opt-level=2` — on the same board, crt0, clocks and 1 MHz timer, three runs
each, with checksums verified identical across all four languages.

- Register-loop microbenchmarks: Mojo == clang C **to the microsecond** (the
  200k-round xorshift is 102,501 µs in all three of Mojo / clang / Rust).
- Larger workloads (CRC-32, quicksort, 16×16 matmul, recursive fib): Mojo lands
  within ±13% of clang C, ahead on some, behind on others — ordinary optimizer
  variance, no systematic "language tax", no cliff as programs grow.

Full methodology and the honest caveats (Rust's own compiler-builtins skew the
division/float rows; XIP flash alignment adds noise on tight loops) are in the
repo's BENCHMARKS.md.

## What the SDK does today

GPIO (pins as compile-time-checked types), PIO (assembler written as method
calls, with side-set, forward labels, and **compile-time assembly** — a PIO
program can be a `comptime` value so the instruction words become flash
constants, with `comptime assert` turning an invalid program into a build
error), PWM, ADC + on-die temperature sensor, UART, NVIC interrupts, RTT
logging, dual-core launch, SIO hardware spinlocks and inter-core FIFO.

Everything is backed by 26 on-target tests that run on real silicon (results
written to a RAM mailbox, read back over SWD) — including a genuinely contended
dual-core spinlock test (2×20k increments == exactly 40,000) and full F5
breakpoint debugging validated over the DAP protocol. There's a scheduled CI
job that re-tests against the newest nightly daily.

## The stack, end to end

- **Language & toolchain**: Mojo nightly, managed by **pixi** (pinned lock for
  reproducibility, plus a daily CI job that re-tests against the *newest*
  nightly so breakage surfaces within a day).
- **Build**: `mojo build --emit=llvm` → `tools/retarget.mojo` → system LLVM 18
  `opt`/`llc` → `arm-none-eabi-gcc` with a 60-line crt0.S, one linker script,
  and boot2 assembled from vendored pico-sdk source (checksummed at build time,
  regression-tested byte-identical to the reference).
- **The tooling is Mojo, too**: the pipeline driver, IR retarget pass, ELF
  verifier, benchmark driver and chart generator are all Mojo programs — Python
  survives only as the test orchestrator and DAP protocol client.
- **Debugging**: probe-rs + VS Code — press F5 and you get breakpoints,
  stepping, variables, CPU registers and live SVD peripheral views *in the
  `.mojo` sources*, on a $4 MCU. RTT logging over the same probe, no UART wires.
- **Tests & CI**: Mojo host unit tests (retarget rules, PIO encodings,
  boot2 provenance) + the 26-test on-target suite over SWD; GitHub Actions runs
  the host suite on every push and the newest-nightly job on a schedule.
- **Packaging**: the SDK installs into any pixi project via the
  `pixi-build-mojo` backend —
  `pixi add --git https://github.com/Hundo1018/inmojomni.git inmojomni`,
  then `import pico`. (Verified end-to-end from a fresh environment.)

## Where I could use the team's input (embedded feedback)

A few things came up that I think are relevant to Mojo reaching freestanding /
embedded targets, and I'd love to know what's on the radar:

1. **A 32-bit ARM (thumbv6m/v7m) backend** would remove the entire retarget
   hack. The riscv32 detour works precisely *because* the data models match,
   but it's a workaround.
2. **Discarded volatile loads.** `_ = read32(mmio_addr)` (a volatile load whose
   result is unused) is dropped by the elaborator *before* it reaches LLVM, so
   the volatile access never happens. On an MCU this is a real footgun — I hit
   it as a hang draining a hardware FIFO and had to route the value into a
   branch with a side effect to keep the load alive. Is eliminating an
   unused-but-volatile load intended? (Happy to file a minimal repro.)
3. **A no-std / freestanding profile.** The bounds-check/assert path pulls in a
   small printf/formatting machinery; on bare metal I stub those symbols to a
   `bkpt` trap. A supported freestanding profile (and a way to opt the assert
   I/O into a user-provided trap) would make this cleaner.

On the flip side, **comptime is a joy here** — folding an entire register map to
immediates, and assembling PIO programs at compile time with real assertions,
are exactly the ergonomics that make this fun rather than painful.

It's experimental and pinned to nightly (the language isn't 1.0), but every
claim in the README has a test behind it. Feedback, questions, and "you're
holding LLVM wrong" corrections all very welcome.
