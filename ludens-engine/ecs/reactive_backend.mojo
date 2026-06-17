"""Reactive ECS backend (Entitas-style groups).

Component values live in per-type `SparseSet`s (as in the sparse-set backend),
but queries are not recomputed on demand: each distinct query signature owns a
**group** — a cached set of matching entities. Every mutation (`set` / `remove` /
`despawn`) re-evaluates the touched entity against all registered groups and
incrementally adds/removes it. A query then just reads its group's cached set, so
after warm-up queries are O(result) with no scanning; the cost moves onto writes
(O(#groups) per mutation). This is the reactive trade-off.

Groups are created lazily the first time a signature is queried. Because the
`StorageBackend` query methods take `self` immutably, the group registry lives on
the heap behind a pointer (interior mutability) so a query can register and
populate a new group without a `mut self`.
"""

from std.memory import UnsafePointer, alloc
from .component import ComponentType
from .entity import Entity
from .sparse_set import SparseSet
from .storage import StorageBackend

comptime DEFAULT_CAP = 4096  # default maximum live entity id
comptime Slot = type_of(alloc[NoneType](1))


struct _Group[cap: Int](Movable, ImplicitlyDeletable):
    """A cached query result: the entity ids matching `mask`."""

    var mask: Int  # OR of (1 << slot) for each required component
    var members: SparseSet[Int, Self.cap]  # member id -> 0 (dense keys = members)

    def __init__(out self, mask: Int):
        self.mask = mask
        self.members = SparseSet[Int, Self.cap]()


struct ReactiveBackend[*CTs: ComponentType, cap: Int = DEFAULT_CAP](
    StorageBackend
):
    comptime N: Int = len(Self.CTs)
    var slots: List[Slot]  # slot i -> heap SparseSet[CTs[i], cap]
    var alive: SparseSet[Int, Self.cap]  # entity id -> generation
    var counter: Int
    var groups: type_of(alloc[List[_Group[Self.cap]]](1))  # registry (heap)

    def __init__(out self):
        self.slots = List[Slot](capacity=Self.N)
        comptime for i in range(Self.N):
            comptime T = Self.CTs[i]
            var p = alloc[SparseSet[T, Self.cap]](1)
            p.init_pointee_move(SparseSet[T, Self.cap]())
            self.slots.append(p.bitcast[NoneType]())
        self.alive = SparseSet[Int, Self.cap]()
        self.counter = 0
        self.groups = alloc[List[_Group[Self.cap]]](1)
        self.groups.init_pointee_move(List[_Group[Self.cap]]())

    def __del__(deinit self):
        comptime for i in range(Self.N):
            comptime T = Self.CTs[i]
            var p = self.slots[i].bitcast[SparseSet[T, Self.cap]]()
            p.destroy_pointee()
            p.free()
        self.groups.destroy_pointee()
        self.groups.free()

    @staticmethod
    def _slot_of[C: ComponentType]() -> Int:
        comptime for i in range(Self.N):
            comptime if Self.CTs[i].ID == C.ID:
                return i
        return -1

    def _store[C: ComponentType](self) -> type_of(alloc[SparseSet[C, Self.cap]](1)):
        return self.slots[Self._slot_of[C]()].bitcast[SparseSet[C, Self.cap]]()

    # --- reactive group maintenance ---
    def _entity_mask(self, id: Int) -> Int:
        var m = 0
        comptime for i in range(Self.N):
            comptime T = Self.CTs[i]
            if self._store[T]()[].contains(id):
                m |= 1 << i
        return m

    def _update_groups(self, id: Int):
        """Re-evaluate entity `id` against every registered group (interior mut)."""
        var m = self._entity_mask(id)
        var gs = self.groups
        for gi in range(len(gs[])):
            var want = gs[][gi].mask
            var satisfies = (m & want) == want
            var member = gs[][gi].members.contains(id)
            if satisfies and not member:
                gs[][gi].members.set(id, 0)
            elif not satisfies and member:
                gs[][gi].members.remove(id)

    def _group_for(self, mask: Int) -> Int:
        var gs = self.groups
        for gi in range(len(gs[])):
            if gs[][gi].mask == mask:
                return gi
        # First query for this signature: register and populate from live entities.
        var g = _Group[Self.cap](mask)
        for i in range(self.alive.dense_len()):
            var id = self.alive.key_at(i)
            if (self._entity_mask(id) & mask) == mask:
                g.members.set(id, 0)
        gs[].append(g^)
        return len(gs[]) - 1

    def _collect(self, gi: Int) -> List[Entity]:
        var out = List[Entity]()
        var gs = self.groups
        var n = gs[][gi].members.dense_len()
        for i in range(n):
            var id = gs[][gi].members.key_at(i)
            out.append(Entity(id, self.alive.get(id)))
        return out^

    # --- lifecycle ---
    def spawn(mut self) -> Entity:
        var id = self.counter
        self.counter += 1
        self.alive.set(id, 0)
        return Entity(id, 0)  # no components yet -> matches no (nonzero) group

    def despawn(mut self, e: Entity):
        if not self.is_alive(e):
            return
        comptime for i in range(Self.N):
            comptime T = Self.CTs[i]
            self._store[T]()[].remove(e.id)
        self._update_groups(e.id)  # mask now 0 -> drops from all groups
        self.alive.remove(e.id)

    def is_alive(self, e: Entity) -> Bool:
        return self.alive.contains(e.id) and self.alive.get(e.id) == e.gen

    def entity_count(self) -> Int:
        return len(self.alive)

    # --- typed component access ---
    def set[C: ComponentType](mut self, e: Entity, var value: C):
        self._store[C]()[].set(e.id, value)
        self._update_groups(e.id)

    def has[C: ComponentType](self, e: Entity) -> Bool:
        return self._store[C]()[].contains(e.id)

    def get[C: ComponentType](self, e: Entity) -> C:
        return self._store[C]()[].get(e.id)

    def remove[C: ComponentType](mut self, e: Entity):
        self._store[C]()[].remove(e.id)
        self._update_groups(e.id)

    # --- queries: read cached groups ---
    def matching1[A: ComponentType](self) -> List[Entity]:
        return self._collect(self._group_for(1 << Self._slot_of[A]()))

    def matching2[A: ComponentType, B: ComponentType](self) -> List[Entity]:
        var mask = (1 << Self._slot_of[A]()) | (1 << Self._slot_of[B]())
        return self._collect(self._group_for(mask))

    def matching3[
        A: ComponentType, B: ComponentType, C: ComponentType
    ](self) -> List[Entity]:
        var mask = (
            (1 << Self._slot_of[A]())
            | (1 << Self._slot_of[B]())
            | (1 << Self._slot_of[C]())
        )
        return self._collect(self._group_for(mask))
