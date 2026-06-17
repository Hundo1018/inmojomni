"""Bitset ECS backend (EntityX / Specs style).

Component *values* live in heap `List[Optional[C]]` columns indexed by entity id,
but component *presence* is tracked in per-component bitsets: `masks[slot]` is a
`List[UInt64]` where bit `id` means "id has this component". Liveness is its own
bitset. A multi-component query ANDs the relevant presence bitsets (and the
liveness bitset) word-by-word and walks the set bits with `count_trailing_zeros`
— skipping empty 64-id words wholesale, which is the bitset model's advantage on
sparse populations.

The value columns are heterogeneous and sit behind type-erased pointer slots, as
in the other backends; the bitsets are homogeneous `UInt64` and need no erasure.
"""

from std.bit import count_trailing_zeros
from std.memory import UnsafePointer, alloc
from .component import ComponentType
from .entity import Entity
from .storage import StorageBackend

comptime DEFAULT_CAP = 4096  # default maximum live entity id
comptime Slot = type_of(alloc[NoneType](1))


def _word(i: Int) -> Int:
    return i >> 6


def _bit(i: Int) -> UInt64:
    return UInt64(1) << UInt64(i & 63)


struct BitsetBackend[*CTs: ComponentType, cap: Int = DEFAULT_CAP](StorageBackend):
    comptime N: Int = len(Self.CTs)
    comptime WORDS: Int = (Self.cap + 63) // 64
    var slots: List[Slot]  # slot i -> heap List[Optional[CTs[i]]], indexed by id
    var masks: List[List[UInt64]]  # masks[slot][word] -> component presence bits
    var live_mask: List[UInt64]  # liveness bits
    var counter: Int
    var n_live: Int

    def __init__(out self):
        self.slots = List[Slot](capacity=Self.N)
        comptime for i in range(Self.N):
            comptime T = Self.CTs[i]
            var p = alloc[List[Optional[T]]](1)
            p.init_pointee_move(List[Optional[T]]())
            self.slots.append(p.bitcast[NoneType]())
        self.masks = List[List[UInt64]]()
        comptime for i in range(Self.N):
            var col = List[UInt64]()
            for _ in range(Self.WORDS):
                col.append(0)
            self.masks.append(col^)
        self.live_mask = List[UInt64]()
        for _ in range(Self.WORDS):
            self.live_mask.append(0)
        self.counter = 0
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

    def _set_mask(mut self, slot: Int, id: Int):
        var w = _word(id)
        self.masks[slot][w] = self.masks[slot][w] | _bit(id)

    def _clear_mask(mut self, slot: Int, id: Int):
        var w = _word(id)
        self.masks[slot][w] = self.masks[slot][w] & ~_bit(id)

    # --- lifecycle ---
    def spawn(mut self) -> Entity:
        var id = self.counter
        self.counter += 1
        var w = _word(id)
        self.live_mask[w] = self.live_mask[w] | _bit(id)
        self.n_live += 1
        comptime for i in range(Self.N):
            comptime T = Self.CTs[i]
            self._store[T]()[].append(Optional[T]())
        return Entity(id, 0)

    def despawn(mut self, e: Entity):
        if not self.is_alive(e):
            return
        var w = _word(e.id)
        self.live_mask[w] = self.live_mask[w] & ~_bit(e.id)
        self.n_live -= 1
        comptime for i in range(Self.N):
            comptime T = Self.CTs[i]
            self._store[T]()[][e.id] = Optional[T]()
            self._clear_mask(i, e.id)

    def is_alive(self, e: Entity) -> Bool:
        if e.id < 0 or e.id >= self.counter:
            return False
        return (self.live_mask[_word(e.id)] & _bit(e.id)) != 0

    def entity_count(self) -> Int:
        return self.n_live

    # --- typed component access ---
    def set[C: ComponentType](mut self, e: Entity, var value: C):
        self._store[C]()[][e.id] = Optional[C](value^)
        self._set_mask(Self._slot_of[C](), e.id)

    def has[C: ComponentType](self, e: Entity) -> Bool:
        var slot = Self._slot_of[C]()
        return (self.masks[slot][_word(e.id)] & _bit(e.id)) != 0

    def get[C: ComponentType](self, e: Entity) -> C:
        return self._store[C]()[][e.id].value()

    def remove[C: ComponentType](mut self, e: Entity):
        self._store[C]()[][e.id] = Optional[C]()
        self._clear_mask(Self._slot_of[C](), e.id)

    # --- queries: AND the presence bitsets, walk set bits ---
    def _emit(self, bits: UInt64, base: Int, mut out: List[Entity]):
        var b = bits
        while b != 0:
            out.append(Entity(base + Int(count_trailing_zeros(b)), 0))
            b &= b - 1

    def matching1[A: ComponentType](self) -> List[Entity]:
        var out = List[Entity]()
        var sa = Self._slot_of[A]()
        for w in range(Self.WORDS):
            self._emit(self.masks[sa][w] & self.live_mask[w], w * 64, out)
        return out^

    def matching2[A: ComponentType, B: ComponentType](self) -> List[Entity]:
        var out = List[Entity]()
        var sa = Self._slot_of[A]()
        var sb = Self._slot_of[B]()
        for w in range(Self.WORDS):
            var bits = self.masks[sa][w] & self.masks[sb][w] & self.live_mask[w]
            self._emit(bits, w * 64, out)
        return out^

    def matching3[
        A: ComponentType, B: ComponentType, C: ComponentType
    ](self) -> List[Entity]:
        var out = List[Entity]()
        var sa = Self._slot_of[A]()
        var sb = Self._slot_of[B]()
        var sc = Self._slot_of[C]()
        for w in range(Self.WORDS):
            var bits = (
                self.masks[sa][w]
                & self.masks[sb][w]
                & self.masks[sc][w]
                & self.live_mask[w]
            )
            self._emit(bits, w * 64, out)
        return out^
