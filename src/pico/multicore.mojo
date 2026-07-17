"""Dual-core support: launch core 1 into a Mojo function.

After reset, core 1 sleeps in the bootrom waiting for a wake-up
sequence over the inter-core SIO FIFO (RP2040 datasheet §2.8.2, RP2350
datasheet §5.3). `launch()` performs that handshake and starts the
application's function on core 1:

    import pico.multicore as multicore


    @export("mojo_core1_main")
    def core1() abi("C"):
        while True:
            ...  # core 1 code

    multicore.launch()            # from core 0 (RP2040)
    multicore.launch[RP2350]()    # from core 0 (Pico 2)

Chip-generic: `C` supplies PSM/FIFO addresses and the protocol flavour.
The sequence is {0, 0, 1, vector_table, sp, entry} on both chips, but
on Arm `vector_table` is the VTOR value and `entry` carries the thumb
bit (published by crt0.S in `.core1_meta` at fixed flash address
0x100001C0), while on RISC-V `vector_table` is the mtvec value and
`entry` is a plain address (fetched via crt0_rv32.S `core1_meta_word`).
Timeouts count the 1 µs TIMER on the RP2040; the RP2350 port sets up no
timer, so they count mcycle ticks with a conservative ROSC upper bound.

Core 1 has its own 4 KB stack (`_core1_stack_top` in the linker script;
on the RP2350 that is scratch bank X, with core 0 topping scratch Y).
There is no scheduler and no synchronization primitive here yet:
coordinate through volatile RAM (pico.mmio) or the remaining FIFO
capacity.
"""

from std.ffi import external_call

from pico.chips import Chip, RP2040
from pico.mmio import read32, write32, write32_clr, write32_set
from pico.time import time_us

comptime _CORE1_META: UInt32 = 0x1000_01C0  # Arm: fixed link address
comptime _VECTOR_TABLE: UInt32 = 0x1000_0100  # Arm: VTOR value
comptime _ST_VLD: UInt32 = 1  # read side has data
comptime _ST_RDY: UInt32 = 2  # write side has room


def _sev():
    # Wakes core 1 out of its bootrom wait: Arm `sev`, Hazard3
    # `h3.unblock`. Mojo has no inline asm, so each crt0 provides the
    # same two-instruction helper under one name.
    external_call["pico_sev", NoneType]()


@always_inline
def _ticks[C: Chip]() -> UInt32:
    comptime if C.IS_RISCV:
        return external_call["read_mcycle", UInt32]()
    else:
        return time_us()


@always_inline
def _to_ticks[C: Chip](timeout_us: UInt32) -> UInt32:
    comptime if C.IS_RISCV:
        # mcycle runs at clk_sys (ROSC at boot, <= ~16 MHz): a generous
        # upper bound keeps "µs" timeouts meaning at-least-that-long.
        return timeout_us * 16
    else:
        return timeout_us


def _fifo_drain[C: Chip]():
    # CAUTION: `_ = read32(FIFO_RD)` gets discarded whole by the Mojo
    # elaborator — the volatile load never reaches LLVM and the drain
    # spins forever on VLD (found the hard way, verified in the IR).
    # Feeding the value into a compare whose branch has a side effect
    # keeps the pop alive.
    var junk: UInt32 = 0
    while (read32(C.SIO_FIFO_ST) & _ST_VLD) != 0:
        junk ^= read32(C.SIO_FIFO_RD)
    if junk == 0x5AFE_C0DE:  # opaque value: compiler must keep the pops
        _sev()               # harmless on the off chance it matches


def _fifo_push[C: Chip](v: UInt32, timeout_us: UInt32) -> Bool:
    var budget = _to_ticks[C](timeout_us)
    var t0 = _ticks[C]()
    while (read32(C.SIO_FIFO_ST) & _ST_RDY) == 0:
        if _ticks[C]() - t0 > budget:
            return False
    write32(C.SIO_FIFO_WR, v)
    _sev()
    return True


def _fifo_pop[C: Chip](timeout_us: UInt32) -> Tuple[Bool, UInt32]:
    var budget = _to_ticks[C](timeout_us)
    var t0 = _ticks[C]()
    while (read32(C.SIO_FIFO_ST) & _ST_VLD) == 0:
        if _ticks[C]() - t0 > budget:
            return (False, UInt32(0))
    return (True, read32(C.SIO_FIFO_RD))


def _reset_core1[C: Chip]():
    """Force core 1 off and back on through the power-on state machine,
    exactly like the SDK's multicore_reset_core1(): guarantees it is
    sitting in the bootrom wait loop no matter what ran before."""
    write32_set(C.PSM_FRCE_OFF, C.PSM_PROC1)
    while (read32(C.PSM_FRCE_OFF) & C.PSM_PROC1) == 0:
        pass
    write32_clr(C.PSM_FRCE_OFF, C.PSM_PROC1)


def halt_core1[C: Chip = RP2040]():
    """Power core 1 OFF and leave it off (PSM force-off).

    Mandatory before any flash programming (e.g. flash_commit_reboot on
    the RP2350): a core left spinning in XIP while the other core kills
    XIP to erase/program wedges the whole chip on its instruction
    fetches — no fault, no reboot, just a bus hang."""
    write32_set(C.PSM_FRCE_OFF, C.PSM_PROC1)
    while (read32(C.PSM_FRCE_OFF) & C.PSM_PROC1) == 0:
        pass


def fifo_push[C: Chip = RP2040](v: UInt32, timeout_us: UInt32) -> Bool:
    """Send one word to the other core (True on success). The FIFO is
    8 entries deep; the same channel is used by launch(), so only push
    application data after core 1 is running."""
    return _fifo_push[C](v, timeout_us)


def fifo_pop[C: Chip = RP2040](timeout_us: UInt32) -> Tuple[Bool, UInt32]:
    """Receive one word from the other core: (ok, value)."""
    return _fifo_pop[C](timeout_us)


def _cmd[C: Chip](i: UInt32) -> UInt32:
    if i == 0 or i == 1:
        return 0
    if i == 2:
        return 1
    comptime if C.IS_RISCV:
        # link-time words from crt0_rv32.S: 0=entry, 1=sp, 2=mtvec
        if i == 3:
            return external_call["core1_meta_word", UInt32](UInt32(2))
        if i == 4:
            return external_call["core1_meta_word", UInt32](UInt32(1))
        return external_call["core1_meta_word", UInt32](UInt32(0))
    else:
        if i == 3:
            return _VECTOR_TABLE
        if i == 4:
            return read32(_CORE1_META + 4)  # _core1_stack_top
        return read32(_CORE1_META)  # core1_trampoline (thumb bit set)


def launch[C: Chip = RP2040]() -> Bool:
    """Wake core 1 out of the bootrom and start `mojo_core1_main`.

    Resets core 1 first (PSM force-off/on), then runs the bootrom
    handshake, restarting on any unexpected echo. Returns False instead
    of hanging if core 1 stops answering (~50 ms budget)."""
    _reset_core1[C]()
    var i: UInt32 = 0
    var attempts: UInt32 = 0
    while i < 6:
        attempts += 1
        if attempts > 64:
            return False
        var c = _cmd[C](i)
        if c == 0:
            _fifo_drain[C]()
            _sev()
        if not _fifo_push[C](c, 1000):
            return False
        var r = _fifo_pop[C](1000)
        if r[0] and r[1] == c:
            i += 1
        else:
            i = 0
    return True
