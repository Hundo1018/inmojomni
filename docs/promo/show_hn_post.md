# Show HN 草稿(等 demo GIF 就緒再發)

Title: Show HN: Bare-metal Mojo on a $4 microcontroller (780-byte blink, C-parity)
URL: https://github.com/Hundo1018/inmojomni

HN 不吃內文圖,重點在「作者首則留言」——發文後立刻自己補這則:

---

Author here. Mojo is Modular's Python-syntax systems language, normally aimed
at GPUs/AI. I wanted to know what happens if you point it at the opposite end
of computing: a dual Cortex-M0+ with 264 KB of RAM, no OS, no C application
layer.

The catch: Mojo's bundled LLVM has no 32-bit ARM backend. The workaround is
the fun part — emit LLVM IR for riscv32 (identical ILP32 little-endian data
model to ARMv6-M), rewrite the triple/datalayout to thumbv6m, downgrade the
few IR constructs the system LLVM 18 doesn't know yet, then opt/llc + link
with arm-none-eabi-gcc. The retarget pass is unit-tested and verifies that
volatile-op counts survive end to end.

Numbers, because claims are cheap:

- blink firmware: 780 bytes, byte-for-byte the size of the same blink in
  clang -O2 C on the identical rig (Rust: 784 B, gcc: 712 B)
- 9 benchmark workloads x 4 languages (Mojo / gcc / clang / Rust), same crt0,
  same clocks, 3 runs, checksums verified identical across all four: the
  register-loop benchmarks match same-backend C to the microsecond; bigger
  workloads (CRC-32, quicksort, matmul, recursion) land within ±13%, both ways
- 26 on-target tests run on real silicon per commit (GPIO/PIO/PWM/ADC/UART/
  NVIC interrupts/RTT/dual-core/hardware spinlocks), results read back over SWD
- VS Code F5 gives breakpoints/stepping/registers/SVD views in the .mojo
  sources, via probe-rs

Favorite parts: the PIO assembler is written as Mojo method calls and runs at
compile time — an invalid PIO program is a build error, and the instruction
words are flash constants. Least favorite: I found that a discarded volatile
MMIO read (`_ = read32(addr)`) is elided by the compiler frontend before it
reaches LLVM, which cost me a fun debugging session with GDB attached over SWD.

Honest caveats: the language is pre-1.0 and this tracks nightly (a daily CI
job builds against the newest one); no I2C/SPI/DMA/USB drivers yet; and the
gcc comparison mostly measures LLVM-vs-GCC backend differences — the clang
column is the fair one.
