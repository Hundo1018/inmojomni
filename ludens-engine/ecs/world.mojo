"""The world: entities + components over a swappable storage backend.

`World[B: StorageBackend]` is the only type game code touches. Pick the backend
at instantiation:

    var w = World[SparseSetBackend[Position, Velocity]]()
    # ...identical code...
    var w = World[ArchetypeBackend[Position, Velocity]]()

All methods forward to the backend, so swapping `B` changes the storage strategy
without touching any logic. Queries return the matching entities; iterate them
and read/write components with `get`/`set`.
"""

from .storage import StorageBackend
from .entity import Entity
from .component import ComponentType


struct World[B: StorageBackend](Movable, ImplicitlyDeletable):
    var backend: Self.B

    def __init__(out self):
        self.backend = Self.B()

    # --- lifecycle ---
    def spawn(mut self) -> Entity:
        return self.backend.spawn()

    def despawn(mut self, e: Entity):
        self.backend.despawn(e)

    def is_alive(self, e: Entity) -> Bool:
        return self.backend.is_alive(e)

    def entity_count(self) -> Int:
        return self.backend.entity_count()

    # --- components ---
    def set[C: ComponentType](mut self, e: Entity, var value: C):
        self.backend.set[C](e, value^)

    def has[C: ComponentType](self, e: Entity) -> Bool:
        return self.backend.has[C](e)

    def get[C: ComponentType](self, e: Entity) -> C:
        return self.backend.get[C](e)

    def remove[C: ComponentType](mut self, e: Entity):
        self.backend.remove[C](e)

    # --- spawn helpers ---
    def spawn1[A: ComponentType](mut self, a: A) -> Entity:
        var e = self.spawn()
        self.set[A](e, a)
        return e

    def spawn2[A: ComponentType, B2: ComponentType](mut self, a: A, b: B2) -> Entity:
        var e = self.spawn()
        self.set[A](e, a)
        self.set[B2](e, b)
        return e

    # --- queries ---
    def query1[A: ComponentType](self) -> List[Entity]:
        return self.backend.matching1[A]()

    def query2[A: ComponentType, B2: ComponentType](self) -> List[Entity]:
        return self.backend.matching2[A, B2]()

    def query3[
        A: ComponentType, B2: ComponentType, C: ComponentType
    ](self) -> List[Entity]:
        return self.backend.matching3[A, B2, C]()
