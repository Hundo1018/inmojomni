"""Oriented bounding boxes (2D) with a fast OBB-OBB separating-axis test.

An `OBB` is a box of half-extents `half` rotated by `angle` (radians) about its
`center`. Unlike the general polygon SAT, OBB-OBB needs only the four box axes
(two per box): each box projects onto an axis analytically as
`center·axis ± (hx·|axis·ux| + hy·|axis·uy|)`, so we never enumerate corners on
the hot path. `to_polygon()` bridges to the general SAT for cross-checking in
tests. The contact normal is oriented from `a` toward `b`, matching `SATResult`.
"""

from std.math import cos, sin
from .vec import WorldType, Real, Vec2, dot
from .shape import Polygon
from .sat import SATResult


@fieldwise_init
struct OBB(Copyable, ImplicitlyCopyable, Movable):
    var center: Vec2
    var half: Vec2  # half-extents along the local x / y axes
    var angle: Real  # rotation in radians (CCW)

    def axis_x(self) -> Vec2:
        return Vec2(cos(self.angle), sin(self.angle))

    def axis_y(self) -> Vec2:
        return Vec2(-sin(self.angle), cos(self.angle))

    def corners(self) -> List[Vec2]:
        """Four corners CCW from the local bottom-left."""
        var ex = self.axis_x() * self.half[0]
        var ey = self.axis_y() * self.half[1]
        var v = List[Vec2]()
        v.append(self.center - ex - ey)
        v.append(self.center + ex - ey)
        v.append(self.center + ex + ey)
        v.append(self.center - ex + ey)
        return v^

    def to_polygon(self) -> Polygon:
        return Polygon(self.corners())


def _project_radius(o: OBB, axis: Vec2) -> Real:
    """Half-width of `o` projected onto `axis` (axis assumed unit length)."""
    return o.half[0] * abs(dot(axis, o.axis_x())) + o.half[1] * abs(
        dot(axis, o.axis_y())
    )


def _axis_overlap(
    a: OBB, b: OBB, axis: Vec2, mut best_depth: Real, mut best_axis: Vec2
) -> Bool:
    """Test one separating axis; update best (min-overlap) axis. False on a gap."""
    var gap = abs(dot(b.center, axis) - dot(a.center, axis))
    var overlap = (_project_radius(a, axis) + _project_radius(b, axis)) - gap
    if overlap <= 0:
        return False
    if overlap < best_depth:
        best_depth = overlap
        best_axis = axis
    return True


def obb_collide(a: OBB, b: OBB) -> SATResult:
    var best_depth = Real(1.0e30)
    var best_axis = Vec2(0, 0)
    # Box axes are already unit length, so depth is directly in world units.
    if not _axis_overlap(a, b, a.axis_x(), best_depth, best_axis):
        return SATResult.miss()
    if not _axis_overlap(a, b, a.axis_y(), best_depth, best_axis):
        return SATResult.miss()
    if not _axis_overlap(a, b, b.axis_x(), best_depth, best_axis):
        return SATResult.miss()
    if not _axis_overlap(a, b, b.axis_y(), best_depth, best_axis):
        return SATResult.miss()

    # Orient the normal from a toward b.
    var d = b.center - a.center
    if dot(d, best_axis) < 0:
        best_axis = -best_axis
    return SATResult(True, best_axis, best_depth)


def obb_overlaps(a: OBB, b: OBB) -> Bool:
    return obb_collide(a, b).hit
