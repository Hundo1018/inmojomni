# Minimal repro: a volatile load whose result is discarded is dropped
# before LLVM IR is emitted; the identical load whose result is used
# survives. Mojo 1.0.0b3.dev2026070406.
#
#   mojo build --emit=llvm volatile_repro.mojo -o out.ll
#   # then look at @discards_result vs @uses_result in out.ll
#
# @discards_result lowers to `{ ret void }` — the `load volatile` is gone.
# @uses_result keeps `load volatile i32, ptr %_, align 4`.
# Reproduces identically on the default host target and on
# --target-triple=riscv32-unknown-none-elf.


@export("discards_result")
def discards_result() abi("C"):
    var src = UnsafePointer[UInt32, MutUntrackedOrigin](
        unsafe_from_address=0x40054028
    )
    _ = src.load[volatile=True]()          # result discarded -> load elided


@export("uses_result")
def uses_result() abi("C"):
    var src = UnsafePointer[UInt32, MutUntrackedOrigin](
        unsafe_from_address=0x40054028
    )
    var dst = UnsafePointer[UInt32, MutUntrackedOrigin](
        unsafe_from_address=0x20030000
    )
    dst.store[volatile=True](0, src.load[volatile=True]())  # result used -> load kept
