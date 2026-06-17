"""Sparse-set ECS backend (EnTT-style).

One `SparseSet[C, CAP]` per component type, plus a liveness sparse set mapping
`entity id -> generation`. O(1) add/remove/has; single-component iteration is
dense and cache-friendly; multi-component queries intersect the smallest set.

The N typed stores are heterogeneous, so they live on the heap behind
type-erased pointer slots indexed by the component's position in `*CTs`. Only
the *pointer* is erased — each store stays a fully typed `SparseSet[C, CAP]`.
The slot list is preallocated to exactly N (a realloc would corrupt erased
pointers) and all access goes through value-returning methods.
"""

from std.memory import UnsafePointer, alloc
from .component import ComponentType
from .entity import Entity
from .sparse_set import SparseSet
from .storage import StorageBackend

comptime DEFAULT_CAP = 4096  # default maximum live entity id
comptime Slot = type_of(alloc[NoneType](1))


struct SparseSetBackend[*CTs: ComponentType, cap: Int = DEFAULT_CAP](
    StorageBackend
):
    comptime N: Int = len(Self.CTs)
    var slots: List[Slot]  # slot i -> heap SparseSet[CTs[i], cap]
    var alive: SparseSet[Int, Self.cap]  # entity id -> generation
    var counter: Int

    def __init__(out self):
        self.slots = List[Slot](capacity=Self.N)
        comptime for i in range(Self.N):
            comptime T = Self.CTs[i]
            var p = alloc[SparseSet[T, Self.cap]](1)
            p.init_pointee_move(SparseSet[T, Self.cap]())
            self.slots.append(p.bitcast[NoneType]())
        self.alive = SparseSet[Int, Self.cap]()
        self.counter = 0

    def __del__(deinit self):
        comptime for i in range(Self.N):
            comptime T = Self.CTs[i]
            var p = self.slots[i].bitcast[SparseSet[T, Self.cap]]()
            p.destroy_pointee()
            p.free()

    @staticmethod
    def _slot_of[C: ComponentType]() -> Int:
        comptime for i in range(Self.N):
            comptime if Self.CTs[i].ID == C.ID:
                return i
        return -1

    def _store[C: ComponentType](self) -> type_of(alloc[SparseSet[C, Self.cap]](1)):
        return self.slots[Self._slot_of[C]()].bitcast[SparseSet[C, Self.cap]]()

    # --- lifecycle ---
    def spawn(mut self) -> Entity:
        var id = self.counter
        self.counter += 1
        self.alive.set(id, 0)
        return Entity(id, 0)

    def despawn(mut self, e: Entity):
        if not self.is_alive(e):
            return
        comptime for i in range(Self.N):
            comptime T = Self.CTs[i]
            self._store[T]()[].remove(e.id)
        self.alive.remove(e.id)

    def is_alive(self, e: Entity) -> Bool:
        return self.alive.contains(e.id) and self.alive.get(e.id) == e.gen

    def entity_count(self) -> Int:
        return len(self.alive)

    # --- typed component access ---
    def set[C: ComponentType](mut self, e: Entity, var value: C):
        self._store[C]()[].set(e.id, value)

    def has[C: ComponentType](self, e: Entity) -> Bool:
        return self._store[C]()[].contains(e.id)

    def get[C: ComponentType](self, e: Entity) -> C:
        return self._store[C]()[].get(e.id)

    def remove[C: ComponentType](mut self, e: Entity):
        self._store[C]()[].remove(e.id)

    # --- queries ---
    def _entity(self, id: Int) -> Entity:
        return Entity(id, self.alive.get(id))

    def matching1[A: ComponentType](self) -> List[Entity]:
        var out = List[Entity]()
        var store = self._store[A]()
        for i in range(store[].dense_len()):
            out.append(self._entity(store[].key_at(i)))
        return out^

    def matching2[A: ComponentType, B: ComponentType](self) -> List[Entity]:
        var out = List[Entity]()
        var sa = self._store[A]()
        var sb = self._store[B]()
        # iterate the smaller store, probe the larger
        if sa[].dense_len() <= sb[].dense_len():
            for i in range(sa[].dense_len()):
                var id = sa[].key_at(i)
                if sb[].contains(id):
                    out.append(self._entity(id))
        else:
            for i in range(sb[].dense_len()):
                var id = sb[].key_at(i)
                if sa[].contains(id):
                    out.append(self._entity(id))
        return out^

    def matching3[
        A: ComponentType, B: ComponentType, C: ComponentType
    ](self) -> List[Entity]:
        var out = List[Entity]()
        var sa = self._store[A]()
        for i in range(sa[].dense_len()):
            var id = sa[].key_at(i)
            if self._store[B]()[].contains(id) and self._store[C]()[].contains(id):
                out.append(self._entity(id))
        return out^
