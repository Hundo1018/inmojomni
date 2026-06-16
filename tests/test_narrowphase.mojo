from harness.runner import Suite
from geometry.vec import Vec2, Vec3
from geometry.aabb import AABB2
from geometry.shape import Circle, Polygon
from geometry.gjk import ConvexPoly
from collision.narrowphase import (
    AABBNarrowPhase,
    CircleNarrowPhase,
    SATNarrowPhase,
    GJKNarrowPhase,
)


def _square(cx: Float32, cy: Float32) -> ConvexPoly[2]:
    var p = ConvexPoly[2]()
    p.add(Vec2(cx - 1, cy - 1))
    p.add(Vec2(cx + 1, cy - 1))
    p.add(Vec2(cx + 1, cy + 1))
    p.add(Vec2(cx - 1, cy + 1))
    return p^


def main() raises:
    var s = Suite("narrowphase")

    # AABB narrowphase with penetration
    var an = AABBNarrowPhase[2]()
    _ = an.add(AABB2(Vec2(0, 0), Vec2(2, 2)))  # 0
    _ = an.add(AABB2(Vec2(1.5, 0), Vec2(3.5, 2)))  # 1 overlaps by 0.5 in x
    _ = an.add(AABB2(Vec2(10, 10), Vec2(11, 11)))  # 2 far
    var c01 = an.test(0, 1)
    s.check(c01.hit, "aabb overlap hit")
    s.almost(Float64(c01.depth), 0.5, "aabb penetration depth")
    s.check(c01.normal[0] > 0, "aabb normal +x (a->b)")
    s.check(not an.test(0, 2).hit, "aabb far miss")

    # Circle narrowphase
    var cn = CircleNarrowPhase()
    _ = cn.add(Circle(Vec2(0, 0), 1))  # 0
    _ = cn.add(Circle(Vec2(1.5, 0), 1))  # 1 overlap (dist 1.5 < 2)
    _ = cn.add(Circle(Vec2(5, 0), 1))  # 2 far
    s.check(cn.test(0, 1).hit, "circle overlap")
    s.almost(Float64(cn.test(0, 1).depth), 0.5, "circle penetration (2-1.5)")
    s.check(not cn.test(0, 2).hit, "circle far miss")

    # SAT narrowphase (polygons)
    var sn = SATNarrowPhase()
    _ = sn.add(Polygon.box(0, 0, 1, 1))  # 0
    _ = sn.add(Polygon.box(1.5, 0, 1, 1))  # 1 overlap
    _ = sn.add(Polygon.box(5, 0, 1, 1))  # 2 far
    s.check(sn.test(0, 1).hit, "sat overlap")
    s.almost(Float64(sn.test(0, 1).depth), 0.5, "sat penetration depth")
    s.check(not sn.test(0, 2).hit, "sat far miss")

    # GJK narrowphase (boolean)
    var gn = GJKNarrowPhase[2]()
    _ = gn.add(_square(0, 0))  # 0
    _ = gn.add(_square(1, 0))  # 1 overlap
    _ = gn.add(_square(5, 0))  # 2 far
    s.check(gn.test(0, 1).hit, "gjk overlap")
    s.check(not gn.test(0, 2).hit, "gjk far miss")

    s.finish()
