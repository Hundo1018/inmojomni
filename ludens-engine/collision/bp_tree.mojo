"""Loose-tree broadphase: wraps the quadtree (2D) / octree (3D) as a `BroadPhase`.

`QuadTreeBroadPhase` and `OctreeBroadPhase` are just `TreeBroadPhase[2]` and
`TreeBroadPhase[3]`. Candidate pairs are produced by region-querying each item's
box and keeping `candidate > self` (so every overlapping pair is emitted once).
"""

from geometry.aabb import AABB
from spatial.tree_core import LooseTree
from .broadphase import BroadPhase, Pair, BoxProxy


struct TreeBroadPhase[D: Int](BroadPhase):
    comptime dim: Int = Self.D
    var bounds: AABB[Self.D]
    var capacity: Int
    var max_depth: Int
    var tree: LooseTree[Self.D]
    var items: List[BoxProxy[Self.D]]

    def __init__(out self, bounds: AABB[Self.D], capacity: Int = 4, max_depth: Int = 6):
        self.bounds = bounds
        self.capacity = capacity
        self.max_depth = max_depth
        self.tree = LooseTree[Self.D](bounds, capacity, max_depth)
        self.items = List[BoxProxy[Self.D]]()

    def rebuild(mut self, items: List[BoxProxy[Self.D]]) raises:
        self.items = items.copy()
        self.tree.clear(self.bounds)
        for i in range(len(items)):
            self.tree.insert(items[i].proxy, items[i].box)

    def pairs(self, mut out: List[Pair]) raises:
        for i in range(len(self.items)):
            var cands = List[Int]()
            self.tree.query_region(self.items[i].box, cands)
            for k in range(len(cands)):
                if cands[k] > self.items[i].proxy:
                    out.append(Pair(self.items[i].proxy, cands[k]))

    def query_region(self, box: AABB[Self.D], mut out: List[Int]) raises:
        self.tree.query_region(box, out)


comptime QuadTreeBroadPhase = TreeBroadPhase[2]
comptime OctreeBroadPhase = TreeBroadPhase[3]
