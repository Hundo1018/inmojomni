from harness.runner import Suite
from geometry.aabb import AABB, AABB2, AABB3
from geometry.vec import Vec2, Vec3


def main() raises:
    var s = Suite("aabb")

    var a = AABB2(Vec2(0, 0), Vec2(2, 2))
    var b = AABB2(Vec2(1, 1), Vec2(3, 3))
    var c = AABB2(Vec2(5, 5), Vec2(6, 6))
    var t = AABB2(Vec2(2, 2), Vec2(4, 4))  # touches a at corner

    s.check(a.overlaps(b), "overlap a-b")
    s.check(not a.overlaps(c), "disjoint a-c")
    s.check(a.overlaps(t), "touching counts as overlap")
    s.check(b.overlaps(a), "overlap symmetric")

    s.check(a.contains_point(Vec2(1, 1)), "contains inside point")
    s.check(not a.contains_point(Vec2(3, 1)), "excludes outside point")

    var big = AABB2(Vec2(0, 0), Vec2(10, 10))
    s.check(big.contains(a), "big contains a")
    s.check(not a.contains(big), "a does not contain big")

    var m = a.merge(c)
    s.almost(Float64(m.min[0]), 0.0, "merge min")
    s.almost(Float64(m.max[0]), 6.0, "merge max")

    s.almost(Float64(a.center()[0]), 1.0, "center x")
    s.almost(Float64(a.half_extents()[0]), 1.0, "half extents")
    s.almost(Float64(a.surface_area()), 8.0, "2d perimeter 2*(2+2)")

    var fc = AABB2.from_center(Vec2(5, 5), Vec2(1, 1))
    s.almost(Float64(fc.min[0]), 4.0, "from_center min")

    # 3D
    var box3 = AABB3(Vec3(0, 0, 0), Vec3(2, 2, 2))
    var box3b = AABB3(Vec3(1, 1, 1), Vec3(3, 3, 3))
    var box3c = AABB3(Vec3(5, 5, 5), Vec3(6, 6, 6))
    s.check(box3.overlaps(box3b), "3d overlap")
    s.check(not box3.overlaps(box3c), "3d disjoint")
    s.check(box3.contains_point(Vec3(1, 1, 1)), "3d contains point")
    s.almost(Float64(box3.surface_area()), 24.0, "3d surface area 2*(4+4+4)")

    s.finish()
