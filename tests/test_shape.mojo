from harness.runner import Suite
from geometry.vec import Vec2, Vec3
from geometry.shape import Circle, Sphere, Polygon


def main() raises:
    var s = Suite("shape")

    var c0 = Circle(Vec2(0, 0), 1)
    var c1 = Circle(Vec2(1.5, 0), 1)  # distance 1.5 < r1+r2=2 -> hit
    var c2 = Circle(Vec2(5, 0), 1)  # far
    s.check(c0.isintersect(c1), "circles overlap")
    s.check(not c0.isintersect(c2), "circles disjoint")
    s.check(c0.isintersect(c0), "circle self overlap")

    var sp0 = Sphere(Vec3(0, 0, 0), 1)
    var sp1 = Sphere(Vec3(0, 0, 1.5), 1)
    var sp2 = Sphere(Vec3(0, 0, 5), 1)
    s.check(sp0.isintersect(sp1), "spheres overlap")
    s.check(not sp0.isintersect(sp2), "spheres disjoint")

    var box = Polygon.box(0, 0, 2, 1)
    s.eqi(len(box), 4, "box has 4 verts")
    var moved = box.translated(10, 0)
    s.almost(Float64(moved.verts[0][0]), 8.0, "translated x (-2+10)")

    s.finish()
