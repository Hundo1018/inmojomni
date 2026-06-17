from harness.runner import Suite
from geometry.vec import Vec2
from geometry.quickhull import convex_hull_2d
from geometry.pip import point_in_polygon


def _is_convex_ccw(verts: List[Vec2]) -> Bool:
    """All consecutive turns are left turns (cross >= 0) for a convex CCW poly."""
    var n = len(verts)
    for i in range(n):
        var a = verts[i]
        var b = verts[(i + 1) % n]
        var c = verts[(i + 2) % n]
        var cross = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
        if cross < -1e-4:
            return False
    return True


def main() raises:
    var s = Suite("quickhull")

    # A square's worth of points plus interior noise -> 4-vertex hull.
    var pts = List[Vec2]()
    pts.append(Vec2(0, 0))
    pts.append(Vec2(2, 0))
    pts.append(Vec2(2, 2))
    pts.append(Vec2(0, 2))
    pts.append(Vec2(1, 1))  # interior
    pts.append(Vec2(0.5, 0.5))  # interior
    pts.append(Vec2(1.5, 1.0))  # interior

    var hull = convex_hull_2d(pts)
    s.eqi(len(hull), 4, "square hull has 4 vertices")
    s.check(_is_convex_ccw(hull.verts), "hull is convex CCW")

    # Every input point lies inside or on the hull.
    for i in range(len(pts)):
        var p = pts[i]
        # nudge interior test: points strictly inside must be inside; corners on boundary
        var inside_or_corner = point_in_polygon(p, hull) or _on_any_vertex(
            p, hull.verts
        )
        s.check(inside_or_corner, "input point covered by hull")

    # Triangle with interior points -> 3-vertex hull.
    var tri = List[Vec2]()
    tri.append(Vec2(0, 0))
    tri.append(Vec2(4, 0))
    tri.append(Vec2(0, 4))
    tri.append(Vec2(1, 1))  # interior
    var th = convex_hull_2d(tri)
    s.eqi(len(th), 3, "triangle hull has 3 vertices")
    s.check(_is_convex_ccw(th.verts), "triangle hull convex CCW")

    s.finish()


def _on_any_vertex(p: Vec2, verts: List[Vec2]) -> Bool:
    for i in range(len(verts)):
        var d = p - verts[i]
        if d[0] * d[0] + d[1] * d[1] < 1e-9:
            return True
    return False
