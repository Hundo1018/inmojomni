from harness.runner import Suite
from geometry.vec import Vec2
from geometry.obb import OBB, obb_collide, obb_overlaps
from geometry.sat import sat_collide, sat_intersect


def main() raises:
    var s = Suite("obb")

    # Axis-aligned: same scene as the SAT test (overlap 0.5 in x).
    var a = OBB(Vec2(0, 0), Vec2(1, 1), 0)
    var b = OBB(Vec2(1.5, 0), Vec2(1, 1), 0)
    var far = OBB(Vec2(3, 0), Vec2(1, 1), 0)

    var r = obb_collide(a, b)
    s.check(r.hit, "aa overlap hit")
    s.almost(Float64(r.depth), 0.5, "aa penetration depth")
    s.almost(Float64(abs(r.normal[0])), 1.0, "aa normal along x")
    s.almost(Float64(r.normal[1]), 0.0, "aa normal y zero")
    s.check(r.normal[0] > 0, "aa normal points a->b (+x)")
    s.check(not obb_overlaps(a, far), "aa disjoint miss")

    # Parity with the general polygon SAT via to_polygon().
    s.check(
        obb_overlaps(a, b) == sat_intersect(a.to_polygon(), b.to_polygon()),
        "obb vs sat parity (overlap)",
    )
    s.check(
        obb_overlaps(a, far) == sat_intersect(a.to_polygon(), far.to_polygon()),
        "obb vs sat parity (disjoint)",
    )
    var rp = sat_collide(a.to_polygon(), b.to_polygon())
    s.almost(Float64(r.depth), Float64(rp.depth), "obb depth matches sat depth")

    # Rotated box: a 45-degree unit box reaches ~1.414 along the axes.
    var rot = OBB(Vec2(2.2, 0), Vec2(1, 1), 0.78539816)  # ~pi/4
    s.check(obb_overlaps(a, rot), "rotated box overlaps")
    var rot_far = OBB(Vec2(3.0, 0), Vec2(1, 1), 0.78539816)
    s.check(
        obb_overlaps(a, rot_far) == sat_intersect(
            a.to_polygon(), rot_far.to_polygon()
        ),
        "rotated parity",
    )

    s.finish()
