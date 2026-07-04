"""Volatile memory-mapped I/O primitives.

Everything the SDK does ultimately funnels through these two functions,
which compile to single `ldr`/`str` instructions with LLVM `volatile`
semantics (never elided, never reordered against each other).
"""

# RP2040 atomic register aliases (datasheet §2.1.2): writing to
# BASE + alias performs the bitwise op in hardware, race-free.
comptime XOR_ALIAS: UInt32 = 0x1000
comptime SET_ALIAS: UInt32 = 0x2000
comptime CLR_ALIAS: UInt32 = 0x3000


@always_inline
def read32(addr: UInt32) -> UInt32:
    var p = UnsafePointer[UInt32, MutUntrackedOrigin](
        unsafe_from_address=Int(addr)
    )
    return p.load[volatile=True]()


@always_inline
def write32(addr: UInt32, value: UInt32):
    var p = UnsafePointer[UInt32, MutUntrackedOrigin](
        unsafe_from_address=Int(addr)
    )
    p.store[volatile=True](0, value)


@always_inline
def read8(addr: UInt32) -> UInt8:
    var p = UnsafePointer[UInt8, MutUntrackedOrigin](
        unsafe_from_address=Int(addr)
    )
    return p.load[volatile=True]()


@always_inline
def write8(addr: UInt32, value: UInt8):
    var p = UnsafePointer[UInt8, MutUntrackedOrigin](
        unsafe_from_address=Int(addr)
    )
    p.store[volatile=True](0, value)


@always_inline
def write32_set(addr: UInt32, mask: UInt32):
    write32(addr + SET_ALIAS, mask)


@always_inline
def write32_clr(addr: UInt32, mask: UInt32):
    write32(addr + CLR_ALIAS, mask)


@always_inline
def write32_xor(addr: UInt32, mask: UInt32):
    write32(addr + XOR_ALIAS, mask)
