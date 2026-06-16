from harness.runner import Suite
from geometry.vec import Vec2, Vec3
from geometry.gjk import ConvexPoly, gjk_intersect


def _square(cx: Float32, cy: Float32) -> ConvexPoly[2]:
    var p = ConvexPoly[2]()
    p.add(Vec2(cx - 1, cy - 1))
    p.add(Vec2(cx + 1, cy - 1))
    p.add(Vec2(cx + 1, cy + 1))
    p.add(Vec2(cx - 1, cy + 1))
    return p^


def _cube(cx: Float32, cy: Float32, cz: Float32) -> ConvexPoly[3]:
    var p = ConvexPoly[3]()
    for sx in range(2):
        for sy in range(2):
            for sz in range(2):
                p.add(
                    Vec3(
                        cx + (Float32(sx) * 2 - 1),
                        cy + (Float32(sy) * 2 - 1),
                        cz + (Float32(sz) * 2 - 1),
                    )
                )
    return p^


def main() raises:
    var s = Suite("gjk")

    # 2D
    s.check(gjk_intersect[2](_square(0, 0), _square(1, 0)), "2d overlap")
    s.check(gjk_intersect[2](_square(0, 0), _square(0, 0)), "2d self overlap")
    s.check(not gjk_intersect[2](_square(0, 0), _square(3, 0)), "2d disjoint x")
    s.check(not gjk_intersect[2](_square(0, 0), _square(0, 5)), "2d disjoint y")
    s.check(gjk_intersect[2](_square(0, 0), _square(1.9, 1.9)), "2d corner overlap")

    # 3D
    s.check(gjk_intersect[3](_cube(0, 0, 0), _cube(1, 0, 0)), "3d overlap")
    s.check(not gjk_intersect[3](_cube(0, 0, 0), _cube(3, 0, 0)), "3d disjoint x")
    s.check(not gjk_intersect[3](_cube(0, 0, 0), _cube(0, 0, 4)), "3d disjoint z")
    s.check(gjk_intersect[3](_cube(0, 0, 0), _cube(1.5, 1.5, 1.5)), "3d corner overlap")

    s.finish()
