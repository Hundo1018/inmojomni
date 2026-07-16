"""Mojo language-feature measurements on RP2350 silicon (Hazard3, rv32imac).

Answers, with mcycle numbers instead of folklore, on the pinned nightly:

  1. traits      — is a trait-bound generic call really zero-cost?
  2. struct size — does size_of report the expected layouts/padding?
  3. parameter   — comptime-materialized LUT vs computing at runtime
  4. unroll      — `comptime for` (compile-time unroll) vs a runtime loop
  5. function    — @no_inline vs @always_inline call cost
  6. struct-passing boundary — cycles/call as by-value structs grow
     (8..64 bytes, owned `var` convention) vs a TrivialRegisterPassable
     8-byte struct, and an sret-style by-value return.

Every kernel is seeded from a volatile scratch word (SEED) so nothing
constant-folds, and every pair carries a checksum the host verifies.
Results leave through the flash mailbox (see crt0_rv32.S) — same loop
as the benchmark: flash by UF2, read back over PICOBOOT, no probe.

Mailbox: magic "FEAT", state, COUNT, runs=1, lang=0, then COUNT pairs.
Pair map (value_a, value_b):
   0 (trait cycles, ck)      1 (direct cycles, ck)   ck0 == ck1
   2 (size S4, size S8)      3 (size S12, size S13pad)
   4 (LUT cycles, ck)        5 (computed cycles, ck) ck4 == ck5
   6 (unrolled cycles, ck)   7 (rolled cycles, ck)   ck6 == ck7
   8 (no_inline cycles, ck)  9 (always_inline cycles, ck)
  10..14 (pass cycles, ck) for R8-trivial, S8, S16, S32, S64
  15 (return-S16 cycles, ck)
"""

from std.ffi import external_call
from std.sys import size_of

from pico.mmio import read32, write32
from pico.pico2 import init

comptime MB: UInt32 = 0x2003_0000
comptime MAGIC: UInt32 = 0x54414546  # "FEAT" little-endian
comptime COUNT: UInt32 = 16
comptime SEED: UInt32 = 0x2002_3000  # volatile: defeats constant folding
comptime BUF: UInt32 = 0x2002_0000  # 16 u32 scratch
comptime MB_FLASH_OFF: UInt32 = 0x003F_F000
comptime N = 10_000


@always_inline
def _cyc() -> UInt32:
    return external_call["read_mcycle", UInt32]()


@always_inline
def _ram(addr: UInt32) -> UnsafePointer[UInt32, MutUntrackedOrigin]:
    return UnsafePointer[UInt32, MutUntrackedOrigin](
        unsafe_from_address=Int(addr)
    )


# --- 1. traits ------------------------------------------------------------


trait Stepper:
    def step(self, x: UInt32) -> UInt32:
        ...


struct XorStep(Stepper, Copyable):
    def __init__(out self):
        pass

    def step(self, x: UInt32) -> UInt32:
        var y = x ^ (x << 13)
        return y ^ (y >> 17)


def via_trait[T: Stepper](s: T) -> Tuple[UInt32, UInt32]:
    var x = read32(SEED)
    var t0 = _cyc()
    for _ in range(N):
        x = s.step(x)
    return (_cyc() - t0, x)


def via_direct() -> Tuple[UInt32, UInt32]:
    var s = XorStep()
    var x = read32(SEED)
    var t0 = _cyc()
    for _ in range(N):
        x = s.step(x)
    return (_cyc() - t0, x)


# --- 2. struct sizes ------------------------------------------------------


struct S4(Copyable):
    var a: UInt32


struct S8(Copyable):
    var a: UInt32
    var b: UInt32

    def __init__(out self, v: UInt32):
        self.a = v
        self.b = v + 1


struct S12(Copyable):
    var a: UInt32
    var b: UInt32
    var c: UInt32


struct S13(Copyable):  # 12 bytes of u32 + 1 byte: padding -> 16?
    var a: UInt32
    var b: UInt32
    var c: UInt32
    var d: UInt8


# --- 3. parameter: comptime LUT vs runtime compute ------------------------


@always_inline
def _entry(i: UInt32) -> UInt32:
    return (i * 0x1081) ^ (i << 3) ^ 0x5A5A


def _mk_lut() -> InlineArray[UInt32, 16]:
    var t = InlineArray[UInt32, 16](fill=0)
    for i in range(16):
        t[i] = _entry(UInt32(i))
    return t


comptime LUT = _mk_lut()


def via_lut() -> Tuple[UInt32, UInt32]:
    var x = read32(SEED)
    var t0 = _cyc()
    for _ in range(N):
        x = (x >> 4) ^ LUT[Int(x & 15)] ^ (x << 9)
    return (_cyc() - t0, x)


def via_compute() -> Tuple[UInt32, UInt32]:
    var x = read32(SEED)
    var t0 = _cyc()
    for _ in range(N):
        x = (x >> 4) ^ _entry(x & 15) ^ (x << 9)
    return (_cyc() - t0, x)


# --- 4. unroll ------------------------------------------------------------


def via_unrolled() -> Tuple[UInt32, UInt32]:
    var buf = _ram(BUF)
    var acc = read32(SEED)
    var t0 = _cyc()
    for _ in range(N):
        comptime for i in range(16):
            acc += buf.load(i) * UInt32(i + 1)
        buf.store(0, acc)
    return (_cyc() - t0, acc)


def via_rolled() -> Tuple[UInt32, UInt32]:
    var buf = _ram(BUF)
    var acc = read32(SEED)
    var t0 = _cyc()
    for _ in range(N):
        for i in range(16):
            acc += buf.load(i) * UInt32(i + 1)
        buf.store(0, acc)
    return (_cyc() - t0, acc)


# --- 5. function call forms -----------------------------------------------


@no_inline
def add_ni(x: UInt32) -> UInt32:
    return x + 1


@always_inline
def add_ai(x: UInt32) -> UInt32:
    return x + 1


def via_no_inline() -> Tuple[UInt32, UInt32]:
    var x = read32(SEED)
    var t0 = _cyc()
    for _ in range(N):
        x = add_ni(x)
    return (_cyc() - t0, x)


def via_always_inline() -> Tuple[UInt32, UInt32]:
    var x = read32(SEED)
    var t0 = _cyc()
    for _ in range(N):
        x = add_ai(x)
    return (_cyc() - t0, x)


# --- 6. struct-passing boundary -------------------------------------------


struct R8(TrivialRegisterPassable):
    var a: UInt32
    var b: UInt32

    def __init__(out self, v: UInt32):
        self.a = v
        self.b = v + 1


struct S16(Copyable):
    var a: UInt32
    var b: UInt32
    var c: UInt32
    var d: UInt32

    def __init__(out self, v: UInt32):
        self.a = v
        self.b = v + 1
        self.c = v + 2
        self.d = v + 3


struct S32(Copyable):
    var a: UInt32
    var b: UInt32
    var c: UInt32
    var d: UInt32
    var e: UInt32
    var f: UInt32
    var g: UInt32
    var h: UInt32

    def __init__(out self, v: UInt32):
        self.a = v
        self.b = v + 1
        self.c = v + 2
        self.d = v + 3
        self.e = v + 4
        self.f = v + 5
        self.g = v + 6
        self.h = v + 7


struct S64(Copyable):
    var a: UInt32
    var b: UInt32
    var c: UInt32
    var d: UInt32
    var e: UInt32
    var f: UInt32
    var g: UInt32
    var h: UInt32
    var i: UInt32
    var j: UInt32
    var k: UInt32
    var l: UInt32
    var m: UInt32
    var n: UInt32
    var o: UInt32
    var p: UInt32

    def __init__(out self, v: UInt32):
        self.a = v
        self.b = v + 1
        self.c = v + 2
        self.d = v + 3
        self.e = v + 4
        self.f = v + 5
        self.g = v + 6
        self.h = v + 7
        self.i = v + 8
        self.j = v + 9
        self.k = v + 10
        self.l = v + 11
        self.m = v + 12
        self.n = v + 13
        self.o = v + 14
        self.p = v + 15


@no_inline
def eat_r8(s: R8) -> UInt32:
    return s.a + s.b


@no_inline
def eat_s8(var s: S8) -> UInt32:
    return s.a + s.b


@no_inline
def eat_s16(var s: S16) -> UInt32:
    return s.a + s.d


@no_inline
def eat_s32(var s: S32) -> UInt32:
    return s.a + s.h


@no_inline
def eat_s64(var s: S64) -> UInt32:
    return s.a + s.p


@no_inline
def make_s16(x: UInt32) -> S16:
    return S16(x)


def via_pass_r8() -> Tuple[UInt32, UInt32]:
    var v = read32(SEED)
    var s = R8(v)
    var t0 = _cyc()
    for _ in range(N):
        s = R8(eat_r8(s))
    return (_cyc() - t0, s.a)


def via_pass_s8() -> Tuple[UInt32, UInt32]:
    var v = read32(SEED)
    var s = S8(v)
    var t0 = _cyc()
    for _ in range(N):
        var r = eat_s8(s.copy())
        s.a = r
        s.b += 1
    return (_cyc() - t0, s.a)


def via_pass_s16() -> Tuple[UInt32, UInt32]:
    var v = read32(SEED)
    var s = S16(v)
    var t0 = _cyc()
    for _ in range(N):
        var r = eat_s16(s.copy())
        s.a = r
        s.d += 1
    return (_cyc() - t0, s.a)


def via_pass_s32() -> Tuple[UInt32, UInt32]:
    var v = read32(SEED)
    var s = S32(v)
    var t0 = _cyc()
    for _ in range(N):
        var r = eat_s32(s.copy())
        s.a = r
        s.h += 1
    return (_cyc() - t0, s.a)


def via_pass_s64() -> Tuple[UInt32, UInt32]:
    var v = read32(SEED)
    var s = S64(v)
    var t0 = _cyc()
    for _ in range(N):
        var r = eat_s64(s.copy())
        s.a = r
        s.p += 1
    return (_cyc() - t0, s.a)


def via_ret_s16() -> Tuple[UInt32, UInt32]:
    var acc = read32(SEED)
    var t0 = _cyc()
    for _ in range(N):
        var s = make_s16(acc)
        acc = s.a + s.d
    return (_cyc() - t0, acc)


# --- reporting -------------------------------------------------------------


def _report(idx: UInt32, r: Tuple[UInt32, UInt32]):
    var base = MB + 0x14 + idx * 8
    write32(base, r[0])
    write32(base + 4, r[1])


@export("mojo_main")
def start() abi("C"):
    init()
    write32(MB + 0x00, MAGIC)
    write32(MB + 0x04, 1)
    write32(MB + 0x08, COUNT)
    write32(MB + 0x0C, 1)
    write32(MB + 0x10, 0)
    write32(SEED, 0xC0DE1234)

    var st = XorStep()
    _report(0, via_trait(st))
    _report(1, via_direct())
    _report(
        2, (UInt32(size_of[S4]()), UInt32(size_of[S8]()))
    )
    _report(
        3, (UInt32(size_of[S12]()), UInt32(size_of[S13]()))
    )
    _report(4, via_lut())
    _report(5, via_compute())
    _report(6, via_unrolled())
    _report(7, via_rolled())
    _report(8, via_no_inline())
    _report(9, via_always_inline())
    _report(10, via_pass_r8())
    _report(11, via_pass_s8())
    _report(12, via_pass_s16())
    _report(13, via_pass_s32())
    _report(14, via_pass_s64())
    _report(15, via_ret_s16())

    write32(MB + 0x04, 2)  # done
    external_call["flash_commit_reboot", NoneType](
        MB_FLASH_OFF, MB, UInt32(256), UInt32(0)
    )
    while True:  # unreachable
        pass
