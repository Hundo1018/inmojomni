from harness.runner import Suite
from geometry.vec import Vec2
from geometry.gjk import ConvexPoly
from geometry.epa import gjk_collide


def _box2(cx: Float32, cy: Float32, hx: Float32, hy: Float32) -> ConvexPoly[2]:
    var p = ConvexPoly[2]()
    p.add(Vec2(cx - hx, cy - hy))
    p.add(Vec2(cx + hx, cy - hy))
    p.add(Vec2(cx + hx, cy + hy))
    p.add(Vec2(cx - hx, cy + hy))
    return p^


def main() raises:
    var s = Suite("epa")

    var a = _box2(0, 0, 1, 1)  # [-1,1]^2

    # Overlap by 0.5 along +x.
    var bx = _box2(1.5, 0, 1, 1)
    var rx = gjk_collide[2](a, bx)
    s.check(rx.hit, "x-overlap hit")
    s.almost(Float64(rx.depth), 0.5, "x-overlap depth", 2e-2)
    s.check(rx.normal[0] > 0.9, "x-overlap normal +x")
    s.check(abs(Float64(rx.normal[1])) < 0.1, "x-overlap normal y ~0")

    # Overlap by 0.5 along +y.
    var by = _box2(0, 1.5, 1, 1)
    var ry = gjk_collide[2](a, by)
    s.check(ry.hit, "y-overlap hit")
    s.almost(Float64(ry.depth), 0.5, "y-overlap depth", 2e-2)
    s.check(ry.normal[1] > 0.9, "y-overlap normal +y")

    # Disjoint.
    var far = _box2(3, 0, 1, 1)
    s.check(not gjk_collide[2](a, far).hit, "disjoint miss")

    s.finish()
