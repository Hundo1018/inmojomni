from harness.runner import Suite
from geometry.vec import Vec2
from geometry.shape import Polygon
from geometry.sat import sat_collide, sat_intersect


def _diamond(cx: Float32, cy: Float32) -> Polygon:
    var v = List[Vec2]()
    v.append(Vec2(cx, cy - 1))
    v.append(Vec2(cx + 1, cy))
    v.append(Vec2(cx, cy + 1))
    v.append(Vec2(cx - 1, cy))
    return Polygon(v^)


def main() raises:
    var s = Suite("sat")

    var a = Polygon.box(0, 0, 1, 1)  # [-1,1] x [-1,1]
    var b = Polygon.box(1.5, 0, 1, 1)  # [0.5,2.5] x [-1,1] -> overlaps by 0.5 in x
    var far = Polygon.box(3, 0, 1, 1)  # [2,4] -> disjoint

    var r = sat_collide(a, b)
    s.check(r.hit, "overlap hit")
    s.almost(Float64(r.depth), 0.5, "penetration depth")
    s.almost(Float64(abs(r.normal[0])), 1.0, "normal along x")
    s.almost(Float64(r.normal[1]), 0.0, "normal y zero")
    s.check(r.normal[0] > 0, "normal points a->b (+x)")

    s.check(not sat_intersect(a, far), "disjoint miss")
    s.check(sat_intersect(a, a), "self overlap")
    s.check(sat_intersect(a, _diamond(0.5, 0)), "box vs diamond overlap")
    s.check(not sat_intersect(a, _diamond(3.5, 0)), "box vs far diamond miss")

    s.finish()
