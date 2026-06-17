from harness.runner import Suite
from geometry.vec import Vec2
from geometry.shape import Polygon
from geometry.aabb import AABB
from geometry.pip import point_in_polygon, winding_number


def _l_shape() -> Polygon:
    # An L: bottom bar x in [0,2] y in [0,1] plus left bar x in [0,1] y in [1,2].
    var v = List[Vec2]()
    v.append(Vec2(0, 0))
    v.append(Vec2(2, 0))
    v.append(Vec2(2, 1))
    v.append(Vec2(1, 1))
    v.append(Vec2(1, 2))
    v.append(Vec2(0, 2))
    return Polygon(v^)


def main() raises:
    var s = Suite("pip")

    var box = Polygon.box(0, 0, 1, 1)  # [-1,1] x [-1,1]
    s.check(point_in_polygon(Vec2(0, 0), box), "center inside")
    s.check(point_in_polygon(Vec2(0.5, 0.5), box), "off-center inside")
    s.check(not point_in_polygon(Vec2(2, 2), box), "far outside")
    s.check(not point_in_polygon(Vec2(1.5, 0), box), "outside on +x")

    # Parity with AABB.contains_point on the same box.
    var ab = AABB[2](Vec2(-1, -1), Vec2(1, 1))
    var pts = List[Vec2]()
    pts.append(Vec2(0, 0))
    pts.append(Vec2(0.9, -0.9))
    pts.append(Vec2(1.2, 0.0))
    pts.append(Vec2(-2.0, 0.5))
    for i in range(len(pts)):
        s.check(
            point_in_polygon(pts[i], box) == ab.contains_point(pts[i]),
            "pip vs aabb agree",
        )

    # Concave polygon: the notch is outside.
    var l = _l_shape()
    s.check(point_in_polygon(Vec2(0.5, 0.5), l), "L bottom-left inside")
    s.check(point_in_polygon(Vec2(1.5, 0.5), l), "L bottom-right inside")
    s.check(point_in_polygon(Vec2(0.5, 1.5), l), "L upper-left inside")
    s.check(not point_in_polygon(Vec2(1.5, 1.5), l), "L notch outside")

    # Winding number: nonzero inside, zero outside.
    s.eqi(winding_number(Vec2(0, 0), box), 1, "winding inside ccw box")
    s.eqi(winding_number(Vec2(2, 2), box), 0, "winding outside box")
    s.check(winding_number(Vec2(0.5, 1.5), l) != 0, "winding inside L")
    s.eqi(winding_number(Vec2(1.5, 1.5), l), 0, "winding L notch outside")

    s.finish()
