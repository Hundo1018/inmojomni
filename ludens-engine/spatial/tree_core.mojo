"""Dimension-generic loose region tree: the shared core of the quadtree (dim=2,
4 children) and octree (dim=3, 8 children).

Each node owns a bounds box and a list of (proxy, box) items. A leaf subdivides
into `2**dim` children once it holds more than `capacity` items and is shallower
than `max_depth`; an item descends only into a child that *fully* contains it,
otherwise it stays on the node (so boundary-straddling objects are stored once).
Nodes live in a flat `List` and reference children by index, so the structure is
realloc-safe (no raw pointers) — see the engine's storage notes.
"""

from std.math import floor
from geometry.aabb import AABB
from geometry.vec import WorldType, Real


@fieldwise_init
struct _Item[dim: Int](Copyable, ImplicitlyCopyable, Movable):
    var proxy: Int
    var box: AABB[Self.dim]


struct _Node[dim: Int](Movable, ImplicitlyDeletable):
    var bounds: AABB[Self.dim]
    var items: List[_Item[Self.dim]]
    var children: List[Int]  # empty => leaf; else 2**dim child node indices

    def __init__(out self, bounds: AABB[Self.dim]):
        self.bounds = bounds
        self.items = List[_Item[Self.dim]]()
        self.children = List[Int]()

    def is_leaf(self) -> Bool:
        return len(self.children) == 0


struct LooseTree[dim: Int](Movable, ImplicitlyDeletable):
    comptime CHILDREN: Int = 1 << Self.dim
    var nodes: List[_Node[Self.dim]]
    var capacity: Int
    var max_depth: Int

    def __init__(out self, bounds: AABB[Self.dim], capacity: Int = 4, max_depth: Int = 6):
        self.nodes = List[_Node[Self.dim]]()
        self.capacity = capacity
        self.max_depth = max_depth
        self.nodes.append(_Node[Self.dim](bounds))

    def clear(mut self, bounds: AABB[Self.dim]):
        self.nodes.clear()
        self.nodes.append(_Node[Self.dim](bounds))

    def _child_bounds(self, parent: AABB[Self.dim], k: Int) -> AABB[Self.dim]:
        var c = parent.center()
        var lo = parent.min
        var hi = parent.max
        comptime for a in range(Self.dim):
            if (k & (1 << a)) != 0:
                lo[a] = c[a]
            else:
                hi[a] = c[a]
        return AABB[Self.dim](lo, hi)

    def _child_for(self, node_bounds: AABB[Self.dim], box: AABB[Self.dim]) -> Int:
        """Index of the child fully containing `box`, or -1 if it straddles."""
        var c = node_bounds.center()
        var k = 0
        comptime for a in range(Self.dim):
            if box.max[a] <= c[a]:
                pass  # lower half: bit a stays 0
            elif box.min[a] >= c[a]:
                k |= 1 << a  # upper half
            else:
                return -1  # straddles axis a
        return k

    def insert(mut self, proxy: Int, box: AABB[Self.dim]):
        self._insert(0, _Item[Self.dim](proxy, box), 0)

    def _insert(mut self, node: Int, item: _Item[Self.dim], depth: Int):
        if not self.nodes[node].is_leaf():
            var ci = self._child_for(self.nodes[node].bounds, item.box)
            if ci >= 0:
                self._insert(self.nodes[node].children[ci], item, depth + 1)
                return
            self.nodes[node].items.append(item)
            return
        # leaf
        self.nodes[node].items.append(item)
        if (
            len(self.nodes[node].items) > self.capacity
            and depth < self.max_depth
        ):
            self._subdivide(node, depth)

    def _subdivide(mut self, node: Int, depth: Int):
        # create children
        var bounds = self.nodes[node].bounds
        for k in range(Self.CHILDREN):
            self.nodes.append(_Node[Self.dim](self._child_bounds(bounds, k)))
            self.nodes[node].children.append(len(self.nodes) - 1)
        # redistribute items that fit fully into a child
        var kept = List[_Item[Self.dim]]()
        var moved = List[_Item[Self.dim]]()
        for i in range(len(self.nodes[node].items)):
            var it = self.nodes[node].items[i]
            if self._child_for(bounds, it.box) >= 0:
                moved.append(it)
            else:
                kept.append(it)
        self.nodes[node].items = kept^
        for i in range(len(moved)):
            var it = moved[i]
            var ci = self._child_for(bounds, it.box)
            self._insert(self.nodes[node].children[ci], it, depth + 1)

    def query_region(self, box: AABB[Self.dim], mut out: List[Int]):
        self._query(0, box, out)

    def _query(self, node: Int, box: AABB[Self.dim], mut out: List[Int]):
        if not self.nodes[node].bounds.overlaps(box):
            return
        for i in range(len(self.nodes[node].items)):
            if self.nodes[node].items[i].box.overlaps(box):
                out.append(self.nodes[node].items[i].proxy)
        if not self.nodes[node].is_leaf():
            for k in range(Self.CHILDREN):
                self._query(self.nodes[node].children[k], box, out)

    def node_count(self) -> Int:
        return len(self.nodes)
