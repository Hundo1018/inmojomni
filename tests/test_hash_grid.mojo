from harness.runner import Suite
from geometry.vec import Vec2, Vec3
from geometry.aabb import AABB2, AABB3
from spatial.hash_grid import SpatialHashGrid


def _has(xs: List[Int], v: Int) -> Bool:
    for i in range(len(xs)):
        if xs[i] == v:
            return True
    return False


def main() raises:
    var s = Suite("hash_grid")

    var g = SpatialHashGrid[2](10.0)
    g.insert(0, AABB2(Vec2(1, 1), Vec2(2, 2)))  # cell (0,0)
    g.insert(1, AABB2(Vec2(15, 15), Vec2(16, 16)))  # cell (1,1)
    g.insert(2, AABB2(Vec2(95, 5), Vec2(96, 6)))  # cell (9,0)

    var near = List[Int]()
    g.query_region(AABB2(Vec2(0, 0), Vec2(5, 5)), near)
    s.check(_has(near, 0), "proxy 0 in origin cell")
    s.check(not _has(near, 1), "proxy 1 not near origin")

    # object spanning several cells is reported exactly once by a covering query
    g.insert(7, AABB2(Vec2(8, 8), Vec2(23, 23)))  # spans cells (0,0)..(2,2)
    var span = List[Int]()
    g.query_region(AABB2(Vec2(0, 0), Vec2(30, 30)), span)
    var c7 = 0
    for i in range(len(span)):
        if span[i] == 7:
            c7 += 1
    s.eqi(c7, 1, "spanning object de-duplicated")

    var far = List[Int]()
    g.query_region(AABB2(Vec2(500, 500), Vec2(510, 510)), far)
    s.eqi(len(far), 0, "empty cell query")

    # 3D grid works too
    var g3 = SpatialHashGrid[3](10.0)
    g3.insert(0, AABB3(Vec3(1, 1, 1), Vec3(2, 2, 2)))
    g3.insert(1, AABB3(Vec3(55, 55, 55), Vec3(56, 56, 56)))
    var n3 = List[Int]()
    g3.query_region(AABB3(Vec3(0, 0, 0), Vec3(5, 5, 5)), n3)
    s.check(_has(n3, 0) and not _has(n3, 1), "3d grid query")

    s.finish()
