"""Naive array-of-structs ECS backend — the brute-force baseline.

The simplest thing that works: each component lives in a heap `List[Optional[C]]`
indexed directly by entity id (holes are `None`), and every query is a full
linear scan over all ids that checks each required component's slot. No sparse
sets, no archetypes, no bitmasks, no smallest-set heuristic — deliberately the
slowest backend, included as the lower bound the others are measured against.

Component lists are heterogeneous, so they live behind type-erased pointer slots
exactly like `SparseSetBackend` (only the pointer is erased; each list stays a
typed `List[Optional[C]]`). `Optional` lets us pad new ids without requiring
components to be `Defaultable`.
"""

from std.memory import UnsafePointer, alloc
from .component import ComponentType
from .entity import Entity
from .storage import StorageBackend

comptime DEFAULT_CAP = 4096  # unused by storage; kept for API symmetry
comptime Slot = type_of(alloc[NoneType](1))


struct NaiveBackend[*CTs: ComponentType, cap: Int = DEFAULT_CAP](StorageBackend):
    comptime N: Int = len(Self.CTs)
    var slots: List[Slot]  # slot i -> heap List[Optional[CTs[i]]], indexed by id
    var live: List[Bool]  # live[id] -> is entity id alive
    var n_live: Int

    def __init__(out self):
        self.slots = List[Slot](capacity=Self.N)
        comptime for i in range(Self.N):
            comptime T = Self.CTs[i]
            var p = alloc[List[Optional[T]]](1)
            p.init_pointee_move(List[Optional[T]]())
            self.slots.append(p.bitcast[NoneType]())
        self.live = List[Bool]()
        self.n_live = 0

    def __del__(deinit self):
        comptime for i in range(Self.N):
            comptime T = Self.CTs[i]
            var p = self.slots[i].bitcast[List[Optional[T]]]()
            p.destroy_pointee()
            p.free()

    @staticmethod
    def _slot_of[C: ComponentType]() -> Int:
        comptime for i in range(Self.N):
            comptime if Self.CTs[i].ID == C.ID:
                return i
        return -1

    def _store[C: ComponentType](self) -> type_of(alloc[List[Optional[C]]](1)):
        return self.slots[Self._slot_of[C]()].bitcast[List[Optional[C]]]()

    # --- lifecycle ---
    def spawn(mut self) -> Entity:
        var id = len(self.live)
        self.live.append(True)
        self.n_live += 1
        # Grow every component column with an empty (None) cell for the new id.
        comptime for i in range(Self.N):
            comptime T = Self.CTs[i]
            self._store[T]()[].append(Optional[T]())
        return Entity(id, 0)

    def despawn(mut self, e: Entity):
        if not self.is_alive(e):
            return
        self.live[e.id] = False
        self.n_live -= 1
        comptime for i in range(Self.N):
            comptime T = Self.CTs[i]
            self._store[T]()[][e.id] = Optional[T]()

    def is_alive(self, e: Entity) -> Bool:
        return e.id >= 0 and e.id < len(self.live) and self.live[e.id]

    def entity_count(self) -> Int:
        return self.n_live

    # --- typed component access ---
    def set[C: ComponentType](mut self, e: Entity, var value: C):
        self._store[C]()[][e.id] = Optional[C](value^)

    def has[C: ComponentType](self, e: Entity) -> Bool:
        return Bool(self._store[C]()[][e.id])

    def get[C: ComponentType](self, e: Entity) -> C:
        return self._store[C]()[][e.id].value()

    def remove[C: ComponentType](mut self, e: Entity):
        self._store[C]()[][e.id] = Optional[C]()

    # --- queries: brute-force linear scans over every id ---
    def matching1[A: ComponentType](self) -> List[Entity]:
        var out = List[Entity]()
        var sa = self._store[A]()
        for id in range(len(self.live)):
            if self.live[id] and sa[][id]:
                out.append(Entity(id, 0))
        return out^

    def matching2[A: ComponentType, B: ComponentType](self) -> List[Entity]:
        var out = List[Entity]()
        var sa = self._store[A]()
        var sb = self._store[B]()
        for id in range(len(self.live)):
            if self.live[id] and sa[][id] and sb[][id]:
                out.append(Entity(id, 0))
        return out^

    def matching3[
        A: ComponentType, B: ComponentType, C: ComponentType
    ](self) -> List[Entity]:
        var out = List[Entity]()
        var sa = self._store[A]()
        var sb = self._store[B]()
        var sc = self._store[C]()
        for id in range(len(self.live)):
            if self.live[id] and sa[][id] and sb[][id] and sc[][id]:
                out.append(Entity(id, 0))
        return out^
