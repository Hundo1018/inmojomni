# GitHub issue for modular/modular
# Title: `load[volatile=True]` is elided when its result is unused (elaborator drops it before LLVM IR)

## Summary

A `UnsafePointer.load[volatile=True]()` whose result is discarded is removed
**before LLVM IR is emitted** — the volatile memory access never happens. The
identical load is preserved as soon as its result is used. For memory-mapped
I/O (reading a peripheral register to clear a flag, draining a hardware FIFO,
etc.) this silently drops a required bus transaction.

Discussed on the forum with @clattner, who asked for a repro.

## Version

`Mojo 1.0.0b3.dev2026070406 (df00bfa0)`

## Minimal reproduction

```mojo
@export("discards_result")
def discards_result() abi("C"):
    var src = UnsafePointer[UInt32, MutUntrackedOrigin](
        unsafe_from_address=0x40054028
    )
    _ = src.load[volatile=True]()          # result discarded

@export("uses_result")
def uses_result() abi("C"):
    var src = UnsafePointer[UInt32, MutUntrackedOrigin](
        unsafe_from_address=0x40054028
    )
    var dst = UnsafePointer[UInt32, MutUntrackedOrigin](
        unsafe_from_address=0x20030000
    )
    dst.store[volatile=True](0, src.load[volatile=True]())   # result used
```

```
mojo build --emit=llvm volatile_repro.mojo -o out.ll
```

## Emitted IR (verbatim, no opt pass involved — this is `--emit=llvm` output)

`@discards_result` — the `load volatile` is **gone**:

```llvm
define dso_local void @discards_result() #0 {
  ret void
}
```

`@uses_result` — same load, kept, because its result is consumed:

```llvm
define dso_local void @uses_result() #0 {
  ; ... pointer setup ...
  %5 = load volatile i32, ptr %3, align 4
  store volatile i32 %5, ptr %4, align 4
  ret void
}
```

## Expected vs actual

- **Expected:** a `volatile` load is an observable side effect and must be
  emitted even if its result is unused (this is what `volatile` means for MMIO;
  it matches C `(void)*(volatile uint32_t*)addr;` and Rust
  `read_volatile(...)` with `let _ =`).
- **Actual:** the discarded-result load is dropped in the elaborator, before
  it reaches LLVM, so `opt`/`llc` never even see it — it's not a backend DCE
  issue.

## Target independence

Reproduces identically on the default host target and on
`--target-triple=riscv32-unknown-none-elf`, consistent with the elision
happening in the elaborator rather than in target lowering.

## Real-world impact / workaround

Hit in bare-metal RP2040 firmware (https://github.com/Hundo1018/inmojomni)
draining an inter-core hardware FIFO: `while VLD: _ = read32(FIFO_RD)` spun
forever because the pop reads were elided. Current workaround is to route the
value into a comparison whose branch has a side effect so the compiler must
keep the load:

```mojo
var junk: UInt32 = 0
while (read32(FIFO_ST) & VLD) != 0:
    junk ^= read32(FIFO_RD)
if junk == 0x5AFE_C0DE:   # opaque sink the optimizer can't fold away
    side_effect()
```

Happy to provide anything else useful.
