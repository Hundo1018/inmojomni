"""Broadphase swappability contract: BruteForce, QuadTree, SpatialHash and BVH
must all report the same set of true AABB-overlap pairs for a fixed scene."""

from harness.runner import Suite
from geometry.vec import Vec2
from geometry.aabb import AABB2
from collision.broadphase import BroadPhase, BruteForce, Pair, BoxProxy
from collision.bp_tree import QuadTreeBroadPhase
from collision.bp_hashgrid import SpatialHashBroadPhase
from collision.bp_bvh import BVHBroadPhase


def _sort(mut xs: List[Int]):
    for i in range(1, len(xs)):
        var key = xs[i]
        var j = i - 1
        while j >= 0 and xs[j] > key:
            xs[j + 1] = xs[j]
            j -= 1
        xs[j + 1] = key


def _keys[BP: BroadPhase](mut bp: BP, items: List[BoxProxy[BP.dim]]) raises -> List[Int]:
    bp.rebuild(items)
    var prs = List[Pair]()
    bp.pairs(prs)
    var keys = List[Int]()
    for i in range(len(prs)):
        var a = prs[i].a
        var b = prs[i].b
        if a > b:
            a, b = b, a
        keys.append(a * 1000 + b)
    _sort(keys)
    return keys^


def _same(a: List[Int], b: List[Int]) -> Bool:
    if len(a) != len(b):
        return False
    for i in range(len(a)):
        if a[i] != b[i]:
            return False
    return True


def _box(p: Int, x0: Float32, y0: Float32, x1: Float32, y1: Float32) -> BoxProxy[2]:
    return BoxProxy[2](p, AABB2(Vec2(x0, y0), Vec2(x1, y1)))


def main() raises:
    var s = Suite("broadphase")

    var items = List[BoxProxy[2]]()
    items.append(_box(0, 0, 0, 2, 2))
    items.append(_box(1, 1, 1, 3, 3))  # overlaps 0
    items.append(_box(2, 10, 10, 12, 12))
    items.append(_box(3, 11, 11, 13, 13))  # overlaps 2
    items.append(_box(4, 1.5, 1.5, 2.5, 2.5))  # overlaps 0 and 1
    items.append(_box(5, 50, 50, 51, 51))  # overlaps none

    var bounds = AABB2(Vec2(0, 0), Vec2(100, 100))
    var bf = BruteForce[2]()
    var qt = QuadTreeBroadPhase(bounds, capacity=2, max_depth=5)
    var hg = SpatialHashBroadPhase[2](5.0)
    var bv = BVHBroadPhase[2]()

    var ref_keys = _keys(bf, items)
    # true pairs: (0,1),(0,4),(1,4),(2,3)
    s.eqi(len(ref_keys), 4, "brute force finds 4 overlapping pairs")

    s.check(_same(_keys(qt, items), ref_keys), "quadtree matches brute force")
    s.check(_same(_keys(hg, items), ref_keys), "spatial hash matches brute force")
    s.check(_same(_keys(bv, items), ref_keys), "bvh matches brute force")

    s.finish()
