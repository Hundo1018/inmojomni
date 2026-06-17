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

## Improvements over the naive model

**Archetype graph edges**: each `Archetype` caches the index of the target
archetype reached by adding or removing one component (`add_edges[slot]` /
`remove_edges[slot]`). On a cache hit the transition costs one array read;
`_find_or_create` is only called on the first traversal of each edge. The
reverse edge is populated simultaneously so both directions warm up in one
traversal.

**Entity-ID recycling**: despawned IDs go on a `free_ids` list. The per-ID
generation counter (`_gen[id]`) is bumped on every despawn so stale `Entity`
handles are correctly detected as dead after the ID is reused.

**Column-view queries** (`query2_views`): return `ArchView2` structs that expose
the heap-allocated column `List` pointers directly, enabling contiguous SoA
iteration without per-entity `get()` overhead.
"""

from std.memory import UnsafePointer, alloc
from .component import ComponentType
from .entity import Entity
from .sparse_set import SparseSet
from .storage import StorageBackend, Record

comptime DEFAULT_CAP = 4096  # default maximum live entity id
comptime MAX_ARCH = 256  # supports up to 8 component types (2^8 signatures)
comptime Slot = type_of(alloc[NoneType](1))


struct ArchView2[A: ComponentType, B: ComponentType](Copyable, ImplicitlyCopyable, Movable):
    """Zero-copy view into one matching archetype's component columns.

    Obtained from `ArchetypeBackend.query2_views[A, B]()`. Each view covers a
    single archetype (a contiguous slice of entities sharing the same component
    signature). Iterate `range(view.len())` and use `get_a` / `set_a` / `get_b`
    / `set_b` to read and write column data directly — no per-entity `get()`
    overhead and no redundant entity-index lookups.

    Internally the column slots point to heap-allocated `List[A]` / `List[B]`
    structs owned by the archetype, so access is two dereferences (pointer →
    list → element), the same cost as the existing `_col[C](arch)[][row]` path.

    The slots are only valid while the backend that produced them is alive and
    no archetype-relocating operation (component add/remove/despawn) is performed
    on an entity in this archetype.

    Example — movement system:
        for view in backend.query2_views[Position, Velocity]():
            for i in range(view.len()):
                var p = view.get_a(i)
                var v = view.get_b(i)
                view.set_a(i, Position(p.x + v.dx, p.y + v.dy))
    """

    var _count: Int
    var _col_a: Slot  # -> heap List[A]
    var _col_b: Slot  # -> heap List[B]

    def __init__(out self, count: Int, col_a: Slot, col_b: Slot):
        self._count = count
        self._col_a = col_a
        self._col_b = col_b

    def len(self) -> Int:
        return self._count

    def get_a(self, i: Int) -> Self.A:
        return self._col_a.bitcast[List[Self.A]]()[][i]

    def get_b(self, i: Int) -> Self.B:
        return self._col_b.bitcast[List[Self.B]]()[][i]

    def set_a(self, i: Int, value: Self.A):
        self._col_a.bitcast[List[Self.A]]()[][i] = value

    def set_b(self, i: Int, value: Self.B):
        self._col_b.bitcast[List[Self.B]]()[][i] = value

    def unsafe_col_a(self) -> type_of(alloc[Self.A](1)):
        """Raw pointer to A's contiguous column buffer (for SIMD / bulk ops)."""
        return self._col_a.bitcast[List[Self.A]]()[].unsafe_ptr()

    def unsafe_col_b(self) -> type_of(alloc[Self.B](1)):
        """Raw pointer to B's contiguous column buffer (for SIMD / bulk ops)."""
        return self._col_b.bitcast[List[Self.B]]()[].unsafe_ptr()


struct Archetype[*CTs: ComponentType](Movable, ImplicitlyDeletable):
    comptime N: Int = len(Self.CTs)
    var mask: Int  # bit i set => component slot i present
    var entities: List[Int]  # row -> entity id
    var cols: List[Slot]  # slot i -> heap List[CTs[i]] (used iff bit i in mask)
    var add_edges: InlineArray[Int, Self.N]     # slot -> target archetype index on add  (-1 = unset)
    var remove_edges: InlineArray[Int, Self.N]  # slot -> target archetype index on remove (-1 = unset)

    def __init__(out self, mask: Int):
        self.mask = mask
        self.entities = List[Int]()
        self.cols = List[Slot](capacity=Self.N)
        self.add_edges = InlineArray[Int, Self.N](fill=-1)
        self.remove_edges = InlineArray[Int, Self.N](fill=-1)
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


struct ArchetypeBackend[*CTs: ComponentType, cap: Int = DEFAULT_CAP](
    StorageBackend
):
    comptime N: Int = len(Self.CTs)
    var archetypes: List[Archetype[*Self.CTs]]
    var arch_mask_index: List[Int]  # parallel: mask of archetypes[k]
    var entity_index: SparseSet[Record, Self.cap]  # entity id -> {archetype, row}
    var alive: SparseSet[Int, Self.cap]  # entity id -> generation
    var counter: Int
    var free_ids: List[Int]          # recycled entity IDs waiting for reuse
    var _gen: InlineArray[Int, Self.cap]  # per-id generation; bumped on despawn

    def __init__(out self):
        self.archetypes = List[Archetype[*Self.CTs]](capacity=MAX_ARCH)
        self.arch_mask_index = List[Int](capacity=MAX_ARCH)
        self.entity_index = SparseSet[Record, Self.cap]()
        self.alive = SparseSet[Int, Self.cap]()
        self.counter = 0
        self.free_ids = List[Int]()
        self._gen = InlineArray[Int, Self.cap](fill=0)
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

    def _transition_add(mut self, arch: Int, slot: Int) -> Int:
        """Return the archetype reached from `arch` by adding component `slot`.
        On a cache miss, finds or creates the target and caches both directions."""
        var cached = self.archetypes[arch].add_edges[slot]
        if cached != -1:
            return cached
        var new_mask = self.archetypes[arch].mask | (1 << slot)
        var target = self._find_or_create(new_mask)
        self.archetypes[arch].add_edges[slot] = target
        self.archetypes[target].remove_edges[slot] = arch
        return target

    def _transition_remove(mut self, arch: Int, slot: Int) -> Int:
        """Return the archetype reached from `arch` by removing component `slot`.
        On a cache miss, finds or creates the target and caches both directions."""
        var cached = self.archetypes[arch].remove_edges[slot]
        if cached != -1:
            return cached
        var new_mask = self.archetypes[arch].mask & ~(1 << slot)
        var target = self._find_or_create(new_mask)
        self.archetypes[arch].remove_edges[slot] = target
        self.archetypes[target].add_edges[slot] = arch
        return target

    def _col[C: ComponentType](self, arch: Int) -> type_of(alloc[List[C]](1)):
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
        var id: Int
        if len(self.free_ids) > 0:
            id = self.free_ids.pop()
        else:
            id = self.counter
            self.counter += 1
        var gen = self._gen[id]
        self.alive.set(id, gen)
        var row = len(self.archetypes[0].entities)
        self.archetypes[0].entities.append(id)
        self.entity_index.set(id, Record(0, row))
        return Entity(id, gen)

    def despawn(mut self, e: Entity):
        if not self.is_alive(e):
            return
        var rec = self.entity_index.get(e.id)
        self._swap_remove(rec.archetype, rec.row)
        self.entity_index.remove(e.id)
        self.alive.remove(e.id)
        self._gen[e.id] = e.gen + 1
        self.free_ids.append(e.id)

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
        var target = self._transition_add(rec.archetype, slot)
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
        var target = self._transition_remove(rec.archetype, slot)
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

    def query2_views[A: ComponentType, B: ComponentType](mut self) -> List[ArchView2[A, B]]:
        """Return zero-copy column views for all archetypes matching A+B.

        Each `ArchView2` exposes the heap-allocated column lists directly.
        Iterate `range(v.len())` and call `get_a` / `set_a` / `get_b` / `set_b`
        to read/write component data without per-entity `get()` overhead.
        """
        var bits = (1 << Self._slot_of[A]()) | (1 << Self._slot_of[B]())
        var out = List[ArchView2[A, B]]()
        for k in range(len(self.archetypes)):
            if (self.archetypes[k].mask & bits) == bits and len(self.archetypes[k].entities) > 0:
                out.append(ArchView2[A, B](
                    len(self.archetypes[k].entities),
                    self._col[A](k).bitcast[NoneType](),
                    self._col[B](k).bitcast[NoneType](),
                ))
        return out^
