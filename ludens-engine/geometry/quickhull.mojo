"""Quickhull convex hull in 2D.

Given a cloud of 2D points, `convex_hull_2d` returns the convex hull as a
`Polygon` in CCW order — the input shape that SAT/GJK assume. The classic
quickhull divide-and-conquer: split the cloud by the line through the leftmost
and rightmost points, then recursively keep the farthest outside point and
subdivide. Collinear interior points are dropped (strict `> 0` side tests).

2D `List[Vec2]` is realloc-safe in this nightly (only width-3 SIMD lists
corrupt), so the hull is built directly as `List[Vec2]`.
"""

from .vec import WorldType, Real, Vec2
from .shape import Polygon


def _cross(o: Vec2, a: Vec2, b: Vec2) -> Real:
    """Signed area x2 of triangle (o, a, b); >0 if b is left of o->a... here
    used as the left test of point relative to directed line o->a."""
    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])


def _hull_side(
    points: List[Vec2], a: Vec2, b: Vec2, mut hull: List[Vec2]
) raises:
    """Append hull vertices strictly between `a` and `b` (exclusive), in order,
    for the points lying to the left of the directed line a->b."""
    if len(points) == 0:
        return
    # Farthest point from the line a->b (largest positive cross == leftmost).
    var idx = -1
    var best = Real(0)
    for i in range(len(points)):
        var d = _cross(a, b, points[i])
        if d > best:
            best = d
            idx = i
    if idx == -1:
        return
    var c = points[idx]
    var left_ac = List[Vec2]()
    var left_cb = List[Vec2]()
    for i in range(len(points)):
        if _cross(a, c, points[i]) > 0:
            left_ac.append(points[i])
        elif _cross(c, b, points[i]) > 0:
            left_cb.append(points[i])
    _hull_side(left_ac, a, c, hull)
    hull.append(c)
    _hull_side(left_cb, c, b, hull)


def _signed_area(verts: List[Vec2]) -> Real:
    var area = Real(0)
    var n = len(verts)
    for i in range(n):
        var p0 = verts[i]
        var p1 = verts[(i + 1) % n]
        area += p0[0] * p1[1] - p1[0] * p0[1]
    return area


def convex_hull_2d(points: List[Vec2]) raises -> Polygon:
    var n = len(points)
    if n < 3:
        # Degenerate: return the points as-is.
        var v = List[Vec2]()
        for i in range(n):
            v.append(points[i])
        return Polygon(v^)

    # Leftmost (min x, then min y) and rightmost (max x, then max y).
    var a = points[0]
    var b = points[0]
    for i in range(1, n):
        var p = points[i]
        if p[0] < a[0] or (p[0] == a[0] and p[1] < a[1]):
            a = p
        if p[0] > b[0] or (p[0] == b[0] and p[1] > b[1]):
            b = p

    var upper = List[Vec2]()  # left of a->b
    var lower = List[Vec2]()  # left of b->a (right of a->b)
    for i in range(n):
        var s = _cross(a, b, points[i])
        if s > 0:
            upper.append(points[i])
        elif s < 0:
            lower.append(points[i])

    var hull = List[Vec2]()
    hull.append(a)
    _hull_side(upper, a, b, hull)
    hull.append(b)
    _hull_side(lower, b, a, hull)

    # Enforce CCW orientation (Polygon's contract).
    if _signed_area(hull) < 0:
        var rev = List[Vec2]()
        for i in range(len(hull)):
            rev.append(hull[len(hull) - 1 - i])
        return Polygon(rev^)
    return Polygon(hull^)
