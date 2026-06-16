"""Separating Axis Theorem narrowphase for 2D convex polygons.

For every edge normal of both polygons we project both shapes onto that axis. If
any axis shows a gap, the shapes are disjoint. Otherwise the axis of minimum
overlap is the contact normal and the overlap is the penetration depth. The
normal is oriented to point from `a` toward `b`.
"""

from .vec import WorldType, Real, Vec2, dot, normalize
from .shape import Polygon


@fieldwise_init
struct SATResult(Copyable, ImplicitlyCopyable, Movable):
    var hit: Bool
    var normal: Vec2  # points from a -> b
    var depth: Real

    @staticmethod
    def miss() -> Self:
        return Self(False, Vec2(0, 0), 0)


def _perp(e: Vec2) -> Vec2:
    """Left normal of a 2D edge."""
    return Vec2(-e[1], e[0])


def _centroid(p: Polygon) -> Vec2:
    var c = Vec2(0, 0)
    var n = len(p.verts)
    for i in range(n):
        c += p.verts[i]
    return c / Real(n)


def _project(p: Polygon, axis: Vec2) -> Vec2:
    """Returns (min, max) of the polygon projected onto `axis`."""
    var lo = dot(p.verts[0], axis)
    var hi = lo
    for i in range(1, len(p.verts)):
        var d = dot(p.verts[i], axis)
        if d < lo:
            lo = d
        if d > hi:
            hi = d
    return Vec2(lo, hi)


def _axes_overlap(
    a: Polygon, b: Polygon, mut best_depth: Real, mut best_axis: Vec2
) -> Bool:
    """Test every edge normal of `a`; update best (min-overlap) axis. False if a gap is found."""
    var n = len(a.verts)
    for i in range(n):
        var edge = a.verts[(i + 1) % n] - a.verts[i]
        var axis = normalize(_perp(edge))
        var pa = _project(a, axis)
        var pb = _project(b, axis)
        var overlap = min(pa[1], pb[1]) - max(pa[0], pb[0])
        if overlap <= 0:
            return False
        if overlap < best_depth:
            best_depth = overlap
            best_axis = axis
    return True


def sat_collide(a: Polygon, b: Polygon) -> SATResult:
    var best_depth = Real(1.0e30)
    var best_axis = Vec2(0, 0)
    if not _axes_overlap(a, b, best_depth, best_axis):
        return SATResult.miss()
    if not _axes_overlap(b, a, best_depth, best_axis):
        return SATResult.miss()

    # Orient the normal from a toward b.
    var d = _centroid(b) - _centroid(a)
    if dot(d, best_axis) < 0:
        best_axis = -best_axis
    return SATResult(True, best_axis, best_depth)


def sat_intersect(a: Polygon, b: Polygon) -> Bool:
    return sat_collide(a, b).hit
