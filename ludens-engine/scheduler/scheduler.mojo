"""The swappable scheduler interface — the sibling of `StorageBackend`.

`World[B]` chooses *how data is stored*; a `Scheduler` chooses *how systems are
driven over it*. `tick(mut world)` advances the world by one step; whether the
registered systems run in order, as message-passing actors, serially or in
parallel, is the scheduler's strategy — picked at instantiation exactly like a
storage backend:

    var sched = SequentialScheduler[B, MoveSystem, DamageSystem]()
    sched.tick(world)            # ...swap the scheduler type, same game code...
    var sched = EntityActorScheduler[B, Damage, Parallel, SpreadHandler]()

A `System` is a backend-generic unit of per-tick work: a struct exposing a
`@staticmethod apply[B](mut world)`, registered as a compile-time *type* pack —
the same mechanism a backend uses for its `*CTs`. Systems are written once
against `World[B]`, so the identical system runs on any backend *and* any
scheduler. The scheduler exposes only `tick`; *which* systems it runs is fixed by
its type parameters (a trait method cannot carry an open system pack), and the
backend it drives is recovered from the associated `comptime B`.
"""

from ecs.world import World
from ecs.storage import StorageBackend


trait System:
    """A backend-generic unit of per-tick work, registered as a `*Systems` pack.

    The single static method keeps a system stateless and compile-time
    dispatched — there is no boxing or virtual call, just `Systems[i].apply`.
    """

    @staticmethod
    def apply[B: StorageBackend](mut world: World[B]): ...


trait Scheduler(Defaultable, Movable, ImplicitlyDeletable):
    """Runs a fixed set of registered systems against `World[Self.B]` per `tick`.

    `B` is an associated type so callers (and the parity driver) can recover the
    backend from the scheduler type alone: `World[S.B]`. Concrete schedulers bind
    it from their own backend parameter (`comptime B = Self.Bk`).
    """

    comptime B: StorageBackend
    def tick(mut self, mut world: World[Self.B]): ...
