"""Spatial-hash-grid broadphase (dimension-generic)."""

from geometry.aabb import AABB
from geometry.vec import Real
from spatial.hash_grid import SpatialHashGrid
from .broadphase import BroadPhase, Pair, BoxProxy


struct SpatialHashBroadPhase[D: Int](BroadPhase):
    comptime dim: Int = Self.D
    var grid: SpatialHashGrid[Self.D]
    var items: List[BoxProxy[Self.D]]

    def __init__(out self, cell_size: Real):
        self.grid = SpatialHashGrid[Self.D](cell_size)
        self.items = List[BoxProxy[Self.D]]()

    def rebuild(mut self, items: List[BoxProxy[Self.D]]) raises:
        self.items = items.copy()
        self.grid.clear()
        for i in range(len(items)):
            self.grid.insert(items[i].proxy, items[i].box)

    def pairs(self, mut out: List[Pair]) raises:
        for i in range(len(self.items)):
            var cands = List[Int]()
            self.grid.query_region(self.items[i].box, cands)
            for k in range(len(cands)):
                if cands[k] > self.items[i].proxy:
                    out.append(Pair(self.items[i].proxy, cands[k]))

    def query_region(self, box: AABB[Self.D], mut out: List[Int]) raises:
        self.grid.query_region(box, out)
