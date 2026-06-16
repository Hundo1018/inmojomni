"""A static bounding-volume hierarchy over `AABB[dim]`, dimension-generic.

Built by recursively median-splitting leaves along the widest centroid axis.
Supports region queries (all proxies whose box overlaps a query box) and
self-pair queries (all overlapping proxy pairs) — the basis of the BVH
broadphase. Nodes live in a flat `List`; children are referenced by index.
"""

from .vec import WorldType, Real
from .aabb import AABB


@fieldwise_init
struct _Leaf[dim: Int](Copyable, ImplicitlyCopyable, Movable):
    var box: AABB[Self.dim]
    var proxy: Int


@fieldwise_init
struct _Node[dim: Int](Copyable, ImplicitlyCopyable, Movable):
    var box: AABB[Self.dim]
    var left: Int  # child node index, or -1 for a leaf
    var right: Int  # child node index, or -1 for a leaf
    var proxy: Int  # proxy id for a leaf, else -1

    def is_leaf(self) -> Bool:
        return self.left < 0


struct BVH[dim: Int](Copyable, Movable):
    var nodes: List[_Node[Self.dim]]
    var root: Int

    def __init__(out self):
        self.nodes = List[_Node[Self.dim]]()
        self.root = -1

    def clear(mut self):
        self.nodes.clear()
        self.root = -1

    def build(mut self, var leaves: List[_Leaf[Self.dim]]):
        self.clear()
        if len(leaves) == 0:
            return
        self.root = self._build(leaves, 0, len(leaves))

    def _bounds(self, leaves: List[_Leaf[Self.dim]], lo: Int, hi: Int) -> AABB[Self.dim]:
        var b = leaves[lo].box
        for i in range(lo + 1, hi):
            b = b.merge(leaves[i].box)
        return b

    def _widest_axis(self, leaves: List[_Leaf[Self.dim]], lo: Int, hi: Int) -> Int:
        var cmin = leaves[lo].box.center()
        var cmax = cmin
        for i in range(lo + 1, hi):
            var c = leaves[i].box.center()
            comptime for k in range(Self.dim):
                if c[k] < cmin[k]:
                    cmin[k] = c[k]
                if c[k] > cmax[k]:
                    cmax[k] = c[k]
        var axis = 0
        var best = cmax[0] - cmin[0]
        comptime for k in range(1, Self.dim):
            var ext = cmax[k] - cmin[k]
            if ext > best:
                best = ext
                axis = k
        return axis

    def _sort_range(mut self, mut leaves: List[_Leaf[Self.dim]], lo: Int, hi: Int, axis: Int):
        # Insertion sort the [lo, hi) range by centroid along `axis`. Fine for the
        # modest leaf counts a teaching engine handles; keeps the build simple.
        for i in range(lo + 1, hi):
            var key = leaves[i]
            var kc = key.box.center()[axis]
            var j = i - 1
            while j >= lo and leaves[j].box.center()[axis] > kc:
                leaves[j + 1] = leaves[j]
                j -= 1
            leaves[j + 1] = key

    def _build(mut self, mut leaves: List[_Leaf[Self.dim]], lo: Int, hi: Int) -> Int:
        var box = self._bounds(leaves, lo, hi)
        if hi - lo == 1:
            self.nodes.append(_Node[Self.dim](box, -1, -1, leaves[lo].proxy))
            return len(self.nodes) - 1

        var axis = self._widest_axis(leaves, lo, hi)
        self._sort_range(leaves, lo, hi, axis)
        var mid = (lo + hi) // 2
        var left = self._build(leaves, lo, mid)
        var right = self._build(leaves, mid, hi)
        self.nodes.append(_Node[Self.dim](box, left, right, -1))
        return len(self.nodes) - 1

    def query_region(self, box: AABB[Self.dim], mut out: List[Int]):
        if self.root < 0:
            return
        self._query(self.root, box, out)

    def _query(self, node: Int, box: AABB[Self.dim], mut out: List[Int]):
        var n = self.nodes[node]
        if not n.box.overlaps(box):
            return
        if n.is_leaf():
            out.append(n.proxy)
            return
        self._query(n.left, box, out)
        self._query(n.right, box, out)
