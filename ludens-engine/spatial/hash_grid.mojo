"""Uniform spatial hash grid (dimension-generic).

Space is partitioned into cells of side `cell_size`; each cell maps to a bucket
of proxy ids. An object is inserted into every cell its box overlaps, so a region
query just unions the buckets of the overlapped cells (de-duplicated). Cell
coordinates are bit-packed into a single integer key. Best when objects are
roughly uniform in size and evenly spread.
"""

from std.collections import Dict
from std.math import floor
from geometry.aabb import AABB
from geometry.vec import WorldType, Real

comptime _BITS = 21
comptime _MASK = (1 << _BITS) - 1
comptime _OFFSET = 1 << 20  # shift cell coords to be non-negative before packing


struct SpatialHashGrid[dim: Int](Movable, ImplicitlyDeletable):
    var cell_size: Real
    var buckets: Dict[Int, List[Int]]

    def __init__(out self, cell_size: Real):
        self.cell_size = cell_size
        self.buckets = Dict[Int, List[Int]]()

    def clear(mut self):
        self.buckets = Dict[Int, List[Int]]()

    def _coord(self, v: Real) -> Int:
        return Int(floor(v / self.cell_size))

    def _key(self, cells: SIMD[DType.int32, Self.dim]) -> Int:
        var key = 0
        comptime for a in range(Self.dim):
            key |= ((Int(cells[a]) + _OFFSET) & _MASK) << (a * _BITS)
        return key

    def _lo(self, box: AABB[Self.dim]) -> SIMD[DType.int32, Self.dim]:
        var c = SIMD[DType.int32, Self.dim](0)
        comptime for a in range(Self.dim):
            c[a] = Int32(self._coord(box.min[a]))
        return c

    def _hi(self, box: AABB[Self.dim]) -> SIMD[DType.int32, Self.dim]:
        var c = SIMD[DType.int32, Self.dim](0)
        comptime for a in range(Self.dim):
            c[a] = Int32(self._coord(box.max[a]))
        return c

    def _span(self, lo: SIMD[DType.int32, Self.dim], hi: SIMD[DType.int32, Self.dim]) -> Int:
        var total = 1
        comptime for a in range(Self.dim):
            total *= Int(hi[a] - lo[a]) + 1
        return total

    def _decode(
        self, t: Int, lo: SIMD[DType.int32, Self.dim], hi: SIMD[DType.int32, Self.dim]
    ) -> SIMD[DType.int32, Self.dim]:
        """Decode the t-th cell of the [lo, hi] cartesian product (odometer)."""
        var cells = SIMD[DType.int32, Self.dim](0)
        var rem = t
        comptime for a in range(Self.dim):
            var width = Int(hi[a] - lo[a]) + 1
            cells[a] = lo[a] + Int32(rem % width)
            rem //= width
        return cells

    def insert(mut self, proxy: Int, box: AABB[Self.dim]) raises:
        var lo = self._lo(box)
        var hi = self._hi(box)
        for t in range(self._span(lo, hi)):
            var key = self._key(self._decode(t, lo, hi))
            if key in self.buckets:
                self.buckets[key].append(proxy)
            else:
                var b = List[Int]()
                b.append(proxy)
                self.buckets[key] = b^

    def query_region(self, box: AABB[Self.dim], mut out: List[Int]) raises:
        var lo = self._lo(box)
        var hi = self._hi(box)
        var seen = Dict[Int, Bool]()
        for t in range(self._span(lo, hi)):
            var key = self._key(self._decode(t, lo, hi))
            if key in self.buckets:
                ref bucket = self.buckets[key]
                for i in range(len(bucket)):
                    var p = bucket[i]
                    if p not in seen:
                        seen[p] = True
                        out.append(p)
