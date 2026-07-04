"""Dual-core support: launch core 1 into a Mojo function.

After reset, core 1 sleeps in the bootrom waiting for a wake-up
sequence over the inter-core SIO FIFO (datasheet §2.8.2). `launch()`
performs that handshake with the entry point and stack that crt0.S
published in `.core1_meta` (fixed flash address 0x100001C0). The
trampoline calls `mojo_core1_main`, which the application provides:

    import pico.multicore as multicore


    @export("mojo_core1_main")
    def core1() abi("C"):
        while True:
            ...  # core 1 code

    multicore.launch()   # from core 0

Core 1 has its own 4 KB stack (`_core1_stack_top` in link.ld). There is
no scheduler and no synchronization primitive here yet: coordinate
through volatile RAM (pico.mmio) or the remaining FIFO capacity.
"""

from std.ffi import external_call

from pico.mmio import read32, write32, write32_clr, write32_set
from pico.rp2040 import (
    PSM_FRCE_OFF,
    PSM_PROC1,
    SIO_FIFO_RD,
    SIO_FIFO_ST,
    SIO_FIFO_WR,
)
from pico.time import time_us

comptime _CORE1_META: UInt32 = 0x1000_01C0
comptime _VECTOR_TABLE: UInt32 = 0x1000_0100
comptime _ST_VLD: UInt32 = 1  # read side has data
comptime _ST_RDY: UInt32 = 2  # write side has room


def _sev():
    # `sev` wakes core 1 from its bootrom `wfe`; Mojo has no inline
    # asm, so crt0.S provides the two-instruction helper.
    external_call["pico_sev", NoneType]()


def _fifo_drain():
    # CAUTION: `_ = read32(FIFO_RD)` gets discarded whole by the Mojo
    # elaborator — the volatile load never reaches LLVM and the drain
    # spins forever on VLD (found the hard way, verified in the IR).
    # Feeding the value into a compare whose branch has a side effect
    # keeps the pop alive.
    var junk: UInt32 = 0
    while (read32(SIO_FIFO_ST) & _ST_VLD) != 0:
        junk ^= read32(SIO_FIFO_RD)
    if junk == 0x5AFE_C0DE:  # opaque value: compiler must keep the pops
        _sev()               # harmless on the off chance it matches


def _fifo_push(v: UInt32, timeout_us: UInt32) -> Bool:
    var t0 = time_us()
    while (read32(SIO_FIFO_ST) & _ST_RDY) == 0:
        if time_us() - t0 > timeout_us:
            return False
    write32(SIO_FIFO_WR, v)
    _sev()
    return True


def _fifo_pop(timeout_us: UInt32) -> Tuple[Bool, UInt32]:
    var t0 = time_us()
    while (read32(SIO_FIFO_ST) & _ST_VLD) == 0:
        if time_us() - t0 > timeout_us:
            return (False, UInt32(0))
    return (True, read32(SIO_FIFO_RD))


def _reset_core1():
    """Force core 1 off and back on through the power-on state machine,
    exactly like the SDK's multicore_reset_core1(): guarantees it is
    sitting in the bootrom wait loop no matter what ran before."""
    write32_set(PSM_FRCE_OFF, PSM_PROC1)
    while (read32(PSM_FRCE_OFF) & PSM_PROC1) == 0:
        pass
    write32_clr(PSM_FRCE_OFF, PSM_PROC1)


def fifo_push(v: UInt32, timeout_us: UInt32) -> Bool:
    """Send one word to the other core (True on success). The FIFO is
    8 entries deep; the same channel is used by launch(), so only push
    application data after core 1 is running."""
    return _fifo_push(v, timeout_us)


def fifo_pop(timeout_us: UInt32) -> Tuple[Bool, UInt32]:
    """Receive one word from the other core: (ok, value)."""
    return _fifo_pop(timeout_us)


def _cmd(i: UInt32) -> UInt32:
    if i == 0 or i == 1:
        return 0
    if i == 2:
        return 1
    if i == 3:
        return _VECTOR_TABLE
    if i == 4:
        return read32(_CORE1_META + 4)  # _core1_stack_top
    return read32(_CORE1_META)  # core1_trampoline (thumb bit set)


def launch() -> Bool:
    """Wake core 1 out of the bootrom and start `mojo_core1_main`.

    Resets core 1 first (PSM force-off/on), then runs the bootrom
    handshake, restarting on any unexpected echo. Returns False instead
    of hanging if core 1 stops answering (~50 ms budget)."""
    _reset_core1()
    var i: UInt32 = 0
    var attempts: UInt32 = 0
    while i < 6:
        attempts += 1
        if attempts > 64:
            return False
        var c = _cmd(i)
        if c == 0:
            _fifo_drain()
            _sev()
        if not _fifo_push(c, 1000):
            return False
        var r = _fifo_pop(1000)
        if r[0] and r[1] == c:
            i += 1
        else:
            i = 0
    return True
