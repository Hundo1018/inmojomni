Thanks for the questions — and I've edited the original post to add the
disclosure.

**Checksums on GPIO writes**

Honestly: I didn't. The GPIO toggle benchmark's checksum slot is a literal
`0` — see `bm_gpio_toggle()` in
[bench/bench.mojo](https://github.com/Hundo1018/inmojomni/blob/main/bench/bench.mojo):

```mojo
def bm_gpio_toggle() -> Tuple[UInt32, UInt32]:
    var pin = Pin[15]()
    pin.make_output()
    var t0 = time_us()
    for _ in range(100_000):
        pin.toggle()
    var dt = time_us() - t0
    return (dt, UInt32(0))  # no checksum for I/O
```

Toggling a pin doesn't produce a data value — there's nothing to hash across
languages for that workload, so I didn't manufacture one. The other 8
workloads (xorshift, division, float mul-add, calls, CRC-32, sort, matmul,
fib) all produce an actual result, and those ARE checksummed and compared
across all four languages.

What I do verify for the GPIO case is a different thing: *does toggle()
actually flip the pin*, not "did every language toggle it the same number
of times." That's covered by a separate on-target test
([tests/on_target/main.mojo](https://github.com/Hundo1018/inmojomni/blob/main/tests/on_target/main.mojo),
`test_gpio_loopback`), which drives the pin high/low and polls the input path
(`wait_level`) to confirm the pad actually observes the state it was told to
drive — GPIO25/GPIO15 pads have input-enable on by default, so this needs no
external wiring. It's a correctness check, not a benchmark; it runs in the
hardware test suite, separately from the timing runs.

**Runtime externs: stubbed, not avoided**

Stubbed. There's currently no freestanding/no-std profile for Mojo that would
let me avoid emitting these symbols in the first place (that's my feedback
item #3 above), so the pragmatic bare-metal answer was to give the linker
what it's looking for. In
[runtime/crt0.S](https://github.com/Hundo1018/inmojomni/blob/main/runtime/crt0.S):

```asm
__pico_mojo_trap:
    bkpt #0
    b __pico_mojo_trap

.macro stub name
.global \name
.thumb_set \name, __pico_mojo_trap
.endm

stub dup
stub fdopen
stub fclose
stub fflush
stub fwrite
stub write
stub putchar
stub abort
stub exit
stub KGEN_CompilerRT_fprintf
stub KGEN_CompilerRT_AlignedAlloc
stub KGEN_CompilerRT_AlignedFree
```

These are the symbols the stdlib's bounds-check/assert formatting path
references (I found the exact list by linking without them and reading off
the undefined-symbol errors one at a time). Every one aliases to the same
`bkpt` trap rather than a real implementation. The reasoning:

- I want bounds checking to stay on — it's one of the project's actual safety
  claims — so removing the checks to avoid the symbols wasn't the right
  trade.
- The formatting/printf-style path is link-time-only dead weight unless a
  check actually fails at runtime, so the cost is a few bytes of stub code,
  not a spurious diagnostics dependency.
- Routing every one of them to a single trap means: any of them firing at all
  is by definition a bug (an actual bounds violation, or something calling
  `fwrite`/`abort` for real on a target with no OS to call them on), so
  stopping dead into `bkpt` (halts into an attached debugger, or HardFaults
  without one) is exactly the behavior I want during development.

This is the same pattern bare-metal C toolchains use for libc syscall stubs
(newlib's `_write`/`_read` on embedded targets) — just applied to Mojo's
runtime surface instead of libc's.
