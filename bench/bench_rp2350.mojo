"""On-target benchmarks, RP2350 / Pico 2 (Mojo side).

Same nine workloads as the RP2040 suite (bench.mojo) — kernel bodies are
copied verbatim so checksums must agree — with the platform bits swapped:

  - timing: Hazard3 `mcycle` CSR via the shared crt0_rv32.S `read_mcycle`
    symbol (every language links the same symbol). Cycle counts are
    immune to ROSC frequency drift, which makes cross-language ratios
    exact even though the RP2350 here runs from the ring oscillator.
  - ISA: rv32imac for every language (hardware mul/div — the RP2040
    suite is armv6m where both are calls).
  - result channel: the flash mailbox (sector 0x3FF000) committed by
    crt0_rv32.S flash_commit_reboot, then read back over PICOBOOT; the
    bootrom clears all SRAM on reboot so a RAM mailbox cannot exist.

Mailbox layout (staged at MB, committed as one 256-byte page):
  +0x00 magic "BENC"   +0x04 state (2=done)  +0x08 COUNT  +0x0C RUNS
  +0x10 LANG id (1=mojo 2=gcc 3=clang 4=rust)
  +0x14 (run*COUNT+i)*8: (cycles, checksum) pairs
"""

from std.ffi import external_call

from pico.mmio import read32, write32
from pico.pico2 import Pin, init

comptime MB: UInt32 = 0x2003_0000
comptime MAGIC: UInt32 = 0x42454E43  # "BENC"
comptime COUNT: UInt32 = 9
comptime RUNS: UInt32 = 3
comptime LANG: UInt32 = 1  # mojo

comptime CRC_BUF: UInt32 = 0x2002_0000  # 1024 u32 (4 KB)
comptime SORT_BUF: UInt32 = 0x2002_1000  # 512 u32
comptime MAT_A: UInt32 = 0x2002_2000  # 16x16 u32 each
comptime MAT_B: UInt32 = 0x2002_2400
comptime MAT_C: UInt32 = 0x2002_2800
comptime FIB_N: UInt32 = 0x2002_3000  # volatile: defeats constant folding

comptime MB_FLASH_OFF: UInt32 = 0x003F_F000  # last 4 KiB sector


@always_inline
def _cyc() -> UInt32:
    return external_call["read_mcycle", UInt32]()


@always_inline
def _ram(addr: UInt32) -> UnsafePointer[UInt32, MutUntrackedOrigin]:
    return UnsafePointer[UInt32, MutUntrackedOrigin](
        unsafe_from_address=Int(addr)
    )


@always_inline
def _step(x: UInt32) -> UInt32:
    var y = x
    y ^= y << 13
    y ^= y >> 17
    y ^= y << 5
    return y


@no_inline
def add_one(x: UInt32) -> UInt32:
    return x + 1


def bm_gpio_toggle() -> Tuple[UInt32, UInt32]:
    var pin = Pin[15]()
    pin.make_output()
    var t0 = _cyc()
    for _ in range(100_000):
        pin.toggle()
    var dt = _cyc() - t0
    return (dt, UInt32(0))  # no checksum for I/O


def bm_xorshift() -> Tuple[UInt32, UInt32]:
    var x: UInt32 = 0xDEADBEEF
    var t0 = _cyc()
    for _ in range(200_000):
        x = _step(x)
    var dt = _cyc() - t0
    return (dt, x)


def bm_div() -> Tuple[UInt32, UInt32]:
    var acc: UInt32 = 0
    var d: UInt32 = 1
    var t0 = _cyc()
    for i in range(50_000):
        acc += UInt32(1_000_000) // d
        d = (d + UInt32(i)) | 1
    var dt = _cyc() - t0
    return (dt, acc)


def bm_f32() -> Tuple[UInt32, UInt32]:
    var sum: Float32 = 0.0
    var a: Float32 = 1.5
    var t0 = _cyc()
    for _ in range(20_000):
        sum += a * 1.000119
        a = sum * 0.5 + a
    var dt = _cyc() - t0
    return (dt, UInt32(sum > 1.0))


def bm_call() -> Tuple[UInt32, UInt32]:
    var x: UInt32 = 0
    var t0 = _cyc()
    for _ in range(100_000):
        x = add_one(x)
    var dt = _cyc() - t0
    return (dt, x)


def bm_crc32() -> Tuple[UInt32, UInt32]:
    var buf = _ram(CRC_BUF)
    var x: UInt32 = 0x12345678
    for i in range(1024):
        x = _step(x)
        buf.store(i, x)
    var acc: UInt32 = 0
    var t0 = _cyc()
    for k in range(4):
        var crc = UInt32(0xFFFFFFFF) ^ UInt32(k)
        for i in range(1024):
            var w = buf.load(i)
            for b in range(4):
                crc ^= (w >> UInt32(8 * b)) & 0xFF
                for _ in range(8):
                    crc = (crc >> 1) ^ (
                        UInt32(0xEDB88320) & (UInt32(0) - (crc & 1))
                    )
        acc ^= ~crc
    var dt = _cyc() - t0
    return (dt, acc)


def _qsort(
    a: UnsafePointer[UInt32, MutUntrackedOrigin], lo: Int32, hi: Int32
):
    if lo >= hi:
        return
    var p = a.load(Int(hi))
    var i = lo
    for j in range(Int(lo), Int(hi)):
        if a.load(j) < p:
            var t = a.load(Int(i))
            a.store(Int(i), a.load(j))
            a.store(j, t)
            i += 1
    var t = a.load(Int(i))
    a.store(Int(i), a.load(Int(hi)))
    a.store(Int(hi), t)
    _qsort(a, lo, i - 1)
    _qsort(a, i + 1, hi)


def bm_sort() -> Tuple[UInt32, UInt32]:
    var a = _ram(SORT_BUF)
    var acc: UInt32 = 0
    var t0 = _cyc()
    for rep in range(20):
        var x = UInt32(0x00C0FFEE) + UInt32(rep)
        for i in range(512):
            x = _step(x)
            a.store(i, x)
        _qsort(a, 0, 511)
        acc += a.load(0) ^ a.load(255) ^ a.load(511)
    var dt = _cyc() - t0
    return (dt, acc)


def bm_mat16() -> Tuple[UInt32, UInt32]:
    var ma = _ram(MAT_A)
    var mb = _ram(MAT_B)
    var mc = _ram(MAT_C)
    var x: UInt32 = 0x600D5EED
    for i in range(256):
        x = _step(x)
        ma.store(i, x)
    for i in range(256):
        x = _step(x)
        mb.store(i, x)
    var acc: UInt32 = 0
    var t0 = _cyc()
    for rep in range(50):
        for i in range(16):
            for j in range(16):
                var s: UInt32 = 0
                for k in range(16):
                    s += ma.load(i * 16 + k) * mb.load(k * 16 + j)
                mc.store(i * 16 + j, s)
        ma.store(rep, ma.load(rep) ^ mc.load(rep))
        acc ^= mc.load(0) + mc.load(255)
    var dt = _cyc() - t0
    return (dt, acc)


def _fib(n: UInt32) -> UInt32:
    if n < 2:
        return n
    return _fib(n - 1) + _fib(n - 2)


def bm_fib() -> Tuple[UInt32, UInt32]:
    var n = read32(FIB_N)  # volatile read: n is opaque to the optimizer
    var t0 = _cyc()
    var r = _fib(n)
    var dt = _cyc() - t0
    return (dt, r)


def _report(run: UInt32, idx: UInt32, r: Tuple[UInt32, UInt32]):
    var base = MB + 0x14 + (run * COUNT + idx) * 8
    write32(base, r[0])
    write32(base + 4, r[1])


@export("mojo_main")
def start() abi("C"):
    init()
    write32(MB + 0x00, MAGIC)
    write32(MB + 0x04, 1)
    write32(MB + 0x08, COUNT)
    write32(MB + 0x0C, RUNS)
    write32(MB + 0x10, LANG)
    write32(FIB_N, 24)

    for run in range(3):
        var r = UInt32(run)
        _report(r, 0, bm_gpio_toggle())
        _report(r, 1, bm_xorshift())
        _report(r, 2, bm_div())
        _report(r, 3, bm_f32())
        _report(r, 4, bm_call())
        _report(r, 5, bm_crc32())
        _report(r, 6, bm_sort())
        _report(r, 7, bm_mat16())
        _report(r, 8, bm_fib())

    write32(MB + 0x04, 2)  # done
    external_call["flash_commit_reboot", NoneType](
        MB_FLASH_OFF, MB, UInt32(256), UInt32(0)
    )
    while True:  # unreachable
        pass
