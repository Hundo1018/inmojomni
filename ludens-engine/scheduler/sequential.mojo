"""The baseline scheduler: run each registered system once, in order.

No messaging, no parallelism — this is the reference every other scheduler is
checked against for parity. Each system runs in registration order and mutates
the world directly, which is exactly the inline `query + get/set` loop game code
writes today, now packaged behind the `Scheduler` seam so it can be swapped for
an actor scheduler with zero change to the systems themselves.
"""

from ecs.world import World
from ecs.storage import StorageBackend
from .scheduler import Scheduler, System


struct SequentialScheduler[Bk: StorageBackend, *Systems: System](Scheduler):
    comptime B = Self.Bk  # satisfy the trait's associated backend type

    def __init__(out self):
        pass

    def tick(mut self, mut world: World[Self.B]):
        comptime for i in range(len(Self.Systems)):
            comptime Sys = Self.Systems[i]
            Sys.apply[Self.B](world)
