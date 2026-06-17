from harness.runner import Suite
from geometry.vec import Vec2
from geometry.sdf import (
    sdf_circle,
    sdf_box,
    sdf_union,
    sdf_intersect,
    sdf_subtract,
    SdfShape,
    sdf_collide,
)


def main() raises:
    var s = Suite("sdf")

    # Primitive distances.
    s.almost(Float64(sdf_circle(Vec2(3, 0), Vec2(0, 0), 1)), 2.0, "circle outside")
    s.almost(Float64(sdf_circle(Vec2(0, 0), Vec2(0, 0), 1)), -1.0, "circle center")
    s.almost(Float64(sdf_box(Vec2(2, 0), Vec2(0, 0), Vec2(1, 1))), 1.0, "box outside +x")
    s.almost(Float64(sdf_box(Vec2(0, 0), Vec2(0, 0), Vec2(1, 1))), -1.0, "box deep inside")
    s.almost(Float64(sdf_box(Vec2(1, 0), Vec2(0, 0), Vec2(1, 1))), 0.0, "box on boundary")

    # Combinators.
    s.almost(Float64(sdf_union(0.5, -0.2)), -0.2, "union takes nearer")
    s.almost(Float64(sdf_intersect(0.5, -0.2)), 0.5, "intersect takes farther")
    s.almost(Float64(sdf_subtract(-0.5, -0.2)), 0.2, "subtract carves")

    # Circle vs circle: exact, matches the analytic overlap (depth 0.5, +x normal).
    var c0 = SdfShape.circle(Vec2(0, 0), 1)
    var c1 = SdfShape.circle(Vec2(1.5, 0), 1)
    var r = sdf_collide(c0, c1)
    s.check(r.hit, "circle-circle hit")
    s.almost(Float64(r.depth), 0.5, "circle-circle depth")
    s.check(r.normal[0] > 0.99, "circle-circle normal +x")

    var c_far = SdfShape.circle(Vec2(3, 0), 1)
    s.check(not sdf_collide(c0, c_far).hit, "circle-circle disjoint miss")

    # Circle vs box: exact (circle center to box field).
    var ci = SdfShape.circle(Vec2(0, 0), 0.6)
    var bx = SdfShape.box(Vec2(1, 0), Vec2(0.5, 0.5))
    var rb = sdf_collide(ci, bx)
    s.check(rb.hit, "circle-box hit")
    s.almost(Float64(rb.depth), 0.1, "circle-box depth", 1e-2)
    s.check(rb.normal[0] > 0, "circle-box normal toward box (+x)")

    s.finish()
