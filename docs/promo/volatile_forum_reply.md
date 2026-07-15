# Forum reply to @clattner (post AFTER the GitHub issue exists; paste its URL)

Yes — plain `UnsafePointer[UInt32, MutUntrackedOrigin].load[volatile=True]()`,
result discarded via `_ =`. Filed with a minimal repro + emitted IR here:
⟨GITHUB ISSUE URL⟩.

Short version: at `--emit=llvm` (before any opt pass), a `load[volatile=True]`
whose result is unused doesn't appear in the IR at all — the function lowers
to `{ ret void }`. The identical load keeps its `load volatile` the moment the
value is used (fed into a `store[volatile=True]`). Reproduces on both the
default host target and `riscv32-unknown-none-elf`, so it's in the elaborator,
not target lowering. Thanks for taking a look!
