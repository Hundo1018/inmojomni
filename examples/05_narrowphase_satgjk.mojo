"""Example 05 — narrowphase: SAT (penetration) and GJK (boolean), 2D and 3D.

Run:

    pixi run mojo run -I build examples/05_narrowphase_satgjk.mojo
"""

from geometry.vec import Vec2, Vec3
from geometry.shape import Polygon
from geometry.sat import sat_collide
from geometry.gjk import ConvexPoly, gjk_intersect


def _square2(cx: Float32, cy: Float32) -> ConvexPoly[2]:
    var p = ConvexPoly[2]()
    p.add(Vec2(cx - 1, cy - 1))
    p.add(Vec2(cx + 1, cy - 1))
    p.add(Vec2(cx + 1, cy + 1))
    p.add(Vec2(cx - 1, cy + 1))
    return p^


def _cube(cx: Float32) -> ConvexPoly[3]:
    var p = ConvexPoly[3]()
    for sx in range(2):
        for sy in range(2):
            for sz in range(2):
                p.add(
                    Vec3(
                        cx + (Float32(sx) * 2 - 1),
                        Float32(sy) * 2 - 1,
                        Float32(sz) * 2 - 1,
                    )
                )
    return p^


def main():
    print("SAT (2D polygons), reports penetration:")
    var a = Polygon.box(0, 0, 1, 1)
    var b = Polygon.box(1.5, 0, 1, 1)
    var r = sat_collide(a, b)
    print("  overlapping boxes -> hit:", r.hit, " depth:", r.depth, " normal.x:", r.normal[0])
    var c = sat_collide(a, Polygon.box(5, 0, 1, 1))
    print("  separated boxes  -> hit:", c.hit)

    print("GJK (boolean), 2D and 3D:")
    print("  squares overlap:", gjk_intersect[2](_square2(0, 0), _square2(1, 0)))
    print("  squares apart:  ", gjk_intersect[2](_square2(0, 0), _square2(5, 0)))
    print("  cubes overlap:  ", gjk_intersect[3](_cube(0), _cube(1)))
    print("  cubes apart:    ", gjk_intersect[3](_cube(0), _cube(5)))
