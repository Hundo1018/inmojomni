"""Archetype (table) ECS backend — the "ECS storage in pictures" model.

Entities are grouped into **archetypes** by their exact component signature (a
bitmask over component slots). Each archetype stores its components column-wise
(SoA): one tightly-packed array per component, all row-aligned, so iterating a
query walks contiguous memory. Adding/removing a component **moves** the entity's
row to the archetype with the new signature (copy shared columns, append the new
value, swap-remove from the old archetype). An `entity id -> {archetype, row}`
index (a `SparseSet`) makes lookup O(1).

Columns are heterogeneous, so each archetype owns one heap `List[CTs[i]]` per
component behind a type-erased pointer slot indexed by the component's position
in `*CTs` (only the pointer is erased; the list stays typed). The archetype
table is preallocated (`capacity=MAX_ARCH`) so it never reallocs and indices stay
stable; archetypes are `Movable`-not-`Copyable` so the column pointers are never
aliased.
"""

from std.memory import UnsafePointer, alloc
from .component import ComponentType
from .entity import Entity
from .sparse_set import SparseSet
from .storage import StorageBackend, Record

comptime CAP = 4096  # maximum live entity id
comptime MAX_ARCH = 256  # supports up to 8 component types (2^8 signatures)
comptime Slot = UnsafePointer[NoneType, MutUntrackedOrigin]


struct Archetype[*CTs: ComponentType](Movable, ImplicitlyDeletable):
    comptime N: Int = len(Self.CTs)
    var mask: Int  # bit i set => component slot i present
    var entities: List[Int]  # row -> entity id
    var cols: List[Slot]  # slot i -> heap List[CTs[i]] (used iff bit i in mask)

    def __init__(out self, mask: Int):
        self.mask = mask
        self.entities = List[Int]()
        self.cols = List[Slot](capacity=Self.N)
        comptime for i in range(Self.N):
            comptime T = Self.CTs[i]
            var p = alloc[List[T]](1)
            p.init_pointee_move(List[T]())
            self.cols.append(p.bitcast[NoneType]())

    def __del__(deinit self):
        comptime for i in range(Self.N):
            comptime T = Self.CTs[i]
            var p = self.cols[i].bitcast[List[T]]()
            p.destroy_pointee()
            p.free()


struct ArchetypeBackend[*CTs: ComponentType](StorageBackend):
    comptime N: Int = len(Self.CTs)
    var archetypes: List[Archetype[*Self.CTs]]
    var arch_mask_index: List[Int]  # parallel: mask of archetypes[k]
    var entity_index: SparseSet[Record, CAP]  # entity id -> {archetype, row}
    var alive: SparseSet[Int, CAP]  # entity id -> generation
    var counter: Int

    def __init__(out self):
        self.archetypes = List[Archetype[*Self.CTs]](capacity=MAX_ARCH)
        self.arch_mask_index = List[Int](capacity=MAX_ARCH)
        self.entity_index = SparseSet[Record, CAP]()
        self.alive = SparseSet[Int, CAP]()
        self.counter = 0
        # archetype 0 is always the empty signature (newly spawned entities)
        self.archetypes.append(Archetype[*Self.CTs](0))
        self.arch_mask_index.append(0)

    @staticmethod
    def _slot_of[C: ComponentType]() -> Int:
        comptime for i in range(Self.N):
            comptime if Self.CTs[i].ID == C.ID:
                return i
        return -1

    def _find_or_create(mut self, mask: Int) -> Int:
        for k in range(len(self.arch_mask_index)):
            if self.arch_mask_index[k] == mask:
                return k
        self.archetypes.append(Archetype[*Self.CTs](mask))
        self.arch_mask_index.append(mask)
        return len(self.archetypes) - 1

    def _col[C: ComponentType](self, arch: Int) -> UnsafePointer[List[C], MutUntrackedOrigin]:
        return self.archetypes[arch].cols[Self._slot_of[C]()].bitcast[List[C]]()

    def _swap_remove(mut self, arch: Int, row: Int):
        """Remove `row` from `arch`, moving the last row into the hole."""
        var mask = self.archetypes[arch].mask
        var last = len(self.archetypes[arch].entities) - 1
        comptime for i in range(Self.N):
            if (mask & (1 << i)) != 0:
                comptime T = Self.CTs[i]
                var col = self.archetypes[arch].cols[i].bitcast[List[T]]()
                col[][row] = col[][last]
                _ = col[].pop()
        var moved_id = self.archetypes[arch].entities[last]
        self.archetypes[arch].entities[row] = moved_id
        _ = self.archetypes[arch].entities.pop()
        if row != last:
            self.entity_index.set(moved_id, Record(arch, row))

    # --- lifecycle ---
    def spawn(mut self) -> Entity:
        var id = self.counter
        self.counter += 1
        self.alive.set(id, 0)
        var row = len(self.archetypes[0].entities)
        self.archetypes[0].entities.append(id)
        self.entity_index.set(id, Record(0, row))
        return Entity(id, 0)

    def despawn(mut self, e: Entity):
        if not self.is_alive(e):
            return
        var rec = self.entity_index.get(e.id)
        self._swap_remove(rec.archetype, rec.row)
        self.entity_index.remove(e.id)
        self.alive.remove(e.id)

    def is_alive(self, e: Entity) -> Bool:
        return self.alive.contains(e.id) and self.alive.get(e.id) == e.gen

    def entity_count(self) -> Int:
        return len(self.alive)

    # --- typed component access ---
    def set[C: ComponentType](mut self, e: Entity, var value: C):
        var rec = self.entity_index.get(e.id)
        var slot = Self._slot_of[C]()
        var old_mask = self.archetypes[rec.archetype].mask
        if (old_mask & (1 << slot)) != 0:
            # already present: overwrite in place
            self._col[C](rec.archetype)[][rec.row] = value
            return
        # relocate to the archetype with C added
        var new_mask = old_mask | (1 << slot)
        var target = self._find_or_create(new_mask)
        var old_arch = rec.archetype
        var old_row = rec.row
        comptime for i in range(Self.N):
            if (old_mask & (1 << i)) != 0:
                comptime T = Self.CTs[i]
                var ov = self.archetypes[old_arch].cols[i].bitcast[List[T]]()[][old_row]
                self.archetypes[target].cols[i].bitcast[List[T]]()[].append(ov)
        var new_row = len(self.archetypes[target].entities)
        self.archetypes[target].entities.append(e.id)
        self._col[C](target)[].append(value)
        self._swap_remove(old_arch, old_row)
        self.entity_index.set(e.id, Record(target, new_row))

    def has[C: ComponentType](self, e: Entity) -> Bool:
        var rec = self.entity_index.get(e.id)
        return (self.archetypes[rec.archetype].mask & (1 << Self._slot_of[C]())) != 0

    def get[C: ComponentType](self, e: Entity) -> C:
        var rec = self.entity_index.get(e.id)
        return self._col[C](rec.archetype)[][rec.row]

    def remove[C: ComponentType](mut self, e: Entity):
        var rec = self.entity_index.get(e.id)
        var slot = Self._slot_of[C]()
        var old_mask = self.archetypes[rec.archetype].mask
        if (old_mask & (1 << slot)) == 0:
            return
        var new_mask = old_mask & ~(1 << slot)
        var target = self._find_or_create(new_mask)
        var old_arch = rec.archetype
        var old_row = rec.row
        comptime for i in range(Self.N):
            if (new_mask & (1 << i)) != 0:
                comptime T = Self.CTs[i]
                var ov = self.archetypes[old_arch].cols[i].bitcast[List[T]]()[][old_row]
                self.archetypes[target].cols[i].bitcast[List[T]]()[].append(ov)
        var new_row = len(self.archetypes[target].entities)
        self.archetypes[target].entities.append(e.id)
        self._swap_remove(old_arch, old_row)
        self.entity_index.set(e.id, Record(target, new_row))

    # --- queries ---
    def _collect(self, bits: Int, mut out: List[Entity]):
        for k in range(len(self.archetypes)):
            if (self.archetypes[k].mask & bits) == bits:
                for r in range(len(self.archetypes[k].entities)):
                    var id = self.archetypes[k].entities[r]
                    out.append(Entity(id, self.alive.get(id)))

    def matching1[A: ComponentType](self) -> List[Entity]:
        var out = List[Entity]()
        self._collect(1 << Self._slot_of[A](), out)
        return out^

    def matching2[A: ComponentType, B: ComponentType](self) -> List[Entity]:
        var out = List[Entity]()
        self._collect((1 << Self._slot_of[A]()) | (1 << Self._slot_of[B]()), out)
        return out^

    def matching3[
        A: ComponentType, B: ComponentType, C: ComponentType
    ](self) -> List[Entity]:
        var out = List[Entity]()
        var bits = (1 << Self._slot_of[A]()) | (1 << Self._slot_of[B]()) | (
            1 << Self._slot_of[C]()
        )
        self._collect(bits, out)
        return out^
