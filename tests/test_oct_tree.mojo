from harness.runner import Suite
from geometry.vec import Vec3
from geometry.aabb import AABB3
from spatial.oct_tree import Octree


def _has(xs: List[Int], v: Int) -> Bool:
    for i in range(len(xs)):
        if xs[i] == v:
            return True
    return False


def _box(c: Float32, h: Float32) -> AABB3:
    return AABB3(Vec3(c - h, c - h, c - h), Vec3(c + h, c + h, c + h))


def main() raises:
    var s = Suite("oct_tree")

    var ot = Octree(AABB3(Vec3(0, 0, 0), Vec3(100, 100, 100)), capacity=2, max_depth=4)
    ot.insert(0, _box(5, 1))
    ot.insert(1, _box(10, 1))
    ot.insert(2, _box(90, 1))
    ot.insert(3, _box(50, 1))
    ot.insert(4, _box(8, 1))

    s.check(ot.node_count() > 1, "octree subdivided")

    var near = List[Int]()
    ot.query_region(AABB3(Vec3(0, 0, 0), Vec3(20, 20, 20)), near)
    s.check(_has(near, 0) and _has(near, 1) and _has(near, 4), "near-origin proxies found")
    s.check(not _has(near, 2), "far proxy 2 excluded")

    var all = List[Int]()
    ot.query_region(AABB3(Vec3(0, 0, 0), Vec3(100, 100, 100)), all)
    s.eqi(len(all), 5, "full query returns all 5")

    var none = List[Int]()
    ot.query_region(AABB3(Vec3(200, 200, 200), Vec3(210, 210, 210)), none)
    s.eqi(len(none), 0, "outside query empty")

    s.finish()
