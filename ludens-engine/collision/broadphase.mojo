"""Broadphase: cheaply find candidate overlapping pairs so the (expensive)
narrowphase only runs on pairs that might actually touch.

`BroadPhase` is the swap point. Every implementation is fed the frame's boxes via
`rebuild`, then asked for candidate `pairs` (and supports `query_region`). All
implementations must agree on the true set of AABB-overlap pairs — only their
internal acceleration differs. Swap one for another by instantiating
`CollisionPipeline` (see pipeline.mojo) with a different broadphase type.

`BruteForce` is the O(n^2) reference implementation; the tree/grid/BVH wrappers
live in the sibling `bp_*` modules.
"""

from geometry.aabb import AABB


@fieldwise_init
struct Pair(Copyable, ImplicitlyCopyable, Movable):
    var a: Int
    var b: Int


@fieldwise_init
struct BoxProxy[dim: Int](Copyable, ImplicitlyCopyable, Movable):
    var proxy: Int
    var box: AABB[Self.dim]


trait BroadPhase(Movable, ImplicitlyDeletable):
    comptime dim: Int
    def rebuild(mut self, items: List[BoxProxy[Self.dim]]) raises: ...
    def pairs(self, mut out: List[Pair]) raises: ...
    def query_region(self, box: AABB[Self.dim], mut out: List[Int]) raises: ...


struct BruteForce[D: Int](BroadPhase):
    comptime dim: Int = Self.D
    var items: List[BoxProxy[Self.D]]

    def __init__(out self):
        self.items = List[BoxProxy[Self.D]]()

    def rebuild(mut self, items: List[BoxProxy[Self.D]]) raises:
        self.items = items.copy()

    def pairs(self, mut out: List[Pair]) raises:
        for i in range(len(self.items)):
            for j in range(i + 1, len(self.items)):
                if self.items[i].box.overlaps(self.items[j].box):
                    out.append(Pair(self.items[i].proxy, self.items[j].proxy))

    def query_region(self, box: AABB[Self.D], mut out: List[Int]) raises:
        for i in range(len(self.items)):
            if self.items[i].box.overlaps(box):
                out.append(self.items[i].proxy)
