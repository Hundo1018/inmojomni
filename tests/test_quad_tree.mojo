from harness.runner import Suite
from geometry.vec import Vec2
from geometry.aabb import AABB2
from spatial.quad_tree import QuadTree


def _has(xs: List[Int], v: Int) -> Bool:
    for i in range(len(xs)):
        if xs[i] == v:
            return True
    return False


def _box(cx: Float32, cy: Float32, h: Float32) -> AABB2:
    return AABB2(Vec2(cx - h, cy - h), Vec2(cx + h, cy + h))


def main() raises:
    var s = Suite("quad_tree")

    var qt = QuadTree(AABB2(Vec2(0, 0), Vec2(100, 100)), capacity=2, max_depth=4)
    qt.insert(0, _box(5, 5, 1))
    qt.insert(1, _box(10, 10, 1))
    qt.insert(2, _box(90, 90, 1))
    qt.insert(3, _box(60, 20, 1))
    qt.insert(4, _box(8, 8, 1))

    s.check(qt.node_count() > 1, "subdivided past capacity")

    var near = List[Int]()
    qt.query_region(AABB2(Vec2(0, 0), Vec2(20, 20)), near)
    s.check(_has(near, 0) and _has(near, 1) and _has(near, 4), "bottom-left proxies found")
    s.check(not _has(near, 2), "far proxy 2 excluded")
    s.check(not _has(near, 3), "far proxy 3 excluded")

    var all = List[Int]()
    qt.query_region(AABB2(Vec2(0, 0), Vec2(100, 100)), all)
    s.eqi(len(all), 5, "full query returns all 5")

    var none = List[Int]()
    qt.query_region(AABB2(Vec2(200, 200), Vec2(210, 210)), none)
    s.eqi(len(none), 0, "outside query empty")

    # an object straddling the root split (center 50,50) is stored once and found once
    qt.insert(99, AABB2(Vec2(40, 40), Vec2(60, 60)))
    var straddle = List[Int]()
    qt.query_region(AABB2(Vec2(45, 45), Vec2(55, 55)), straddle)
    var count99 = 0
    for i in range(len(straddle)):
        if straddle[i] == 99:
            count99 += 1
    s.eqi(count99, 1, "straddling object reported exactly once")

    s.finish()
