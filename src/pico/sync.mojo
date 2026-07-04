"""Dual-core synchronization: the RP2040's 32 hardware spinlocks.

SIO implements the locks in silicon: reading SPINLOCK<N> attempts the
claim (nonzero = acquired), writing releases it. No load-linked/store-
conditional needed — which is fortunate, because ARMv6-M has none.

    from pico.sync import Spinlock

    var lock = Spinlock[0]()
    lock.acquire()
    ...critical section (keep it short)...
    lock.release()

Locks are global hardware resources shared by both cores; pick distinct
N per purpose. There is no ownership tracking: releasing a lock you do
not hold frees it for everyone.
"""

from pico.mmio import read32, write32
from pico.rp2040 import SIO_SPINLOCK0, SIO_SPINLOCK_ST


struct Spinlock[N: Int](TrivialRegisterPassable):
    """Hardware spinlock N (0..31)."""

    comptime ADDR: UInt32 = SIO_SPINLOCK0 + UInt32(4 * Self.N)

    def __init__(out self):
        comptime assert 0 <= Self.N and Self.N < 32, (
            "RP2040 has spinlocks 0..31"
        )

    @always_inline
    def try_acquire(self) -> Bool:
        """One claim attempt; True if the lock is now held by this core."""
        return read32(Self.ADDR) != 0

    def acquire(self):
        while read32(Self.ADDR) == 0:
            pass

    @always_inline
    def release(self):
        write32(Self.ADDR, 1)

    def is_locked(self) -> Bool:
        """Read the claim state without acquiring (SPINLOCK_ST bitmap)."""
        return (read32(SIO_SPINLOCK_ST) & (UInt32(1) << UInt32(Self.N))) != 0
