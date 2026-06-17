"""Signed distance fields for 2D collision queries.

Each primitive returns the signed distance from a point to a shape's surface:
negative inside, zero on the boundary, positive outside. `SdfShape` is a small
tagged shape (circle / axis-aligned box / oriented box) exposing `distance(p)`
and a numerically-estimated `gradient(p)` (the outward surface normal).

`sdf_collide` is *exact* whenever at least one shape is a circle — the canonical
distance-field test: `d = field.distance(circle.center) - radius`, hit when
`d < 0`, with normal from the field gradient and penetration `-d`. For box-vs-box
prefer SAT/OBB; this module's collide falls back to a coarse center test there
and is documented as such. The contact normal points from `a` toward `b`, like
`SATResult`.
"""

from std.math import cos, sin
from .vec import WorldType, Real, Vec2, dot, length, normalize
from .sat import SATResult


# --- primitive distance functions -------------------------------------------


def sdf_circle(p: Vec2, c: Vec2, r: Real) -> Real:
    return length(p - c) - r


def sdf_box(p: Vec2, c: Vec2, half: Vec2) -> Real:
    """Signed distance to an axis-aligned box (Inigo Quilez's 2D box SDF)."""
    var qx = abs(p[0] - c[0]) - half[0]
    var qy = abs(p[1] - c[1]) - half[1]
    var outside = length(Vec2(max(qx, Real(0)), max(qy, Real(0))))
    var inside = min(max(qx, qy), Real(0))
    return outside + inside


def sdf_obb(p: Vec2, c: Vec2, half: Vec2, angle: Real) -> Real:
    """Box SDF in the box's rotated local frame."""
    var d = p - c
    var ca = cos(angle)
    var sa = sin(angle)
    var local = Vec2(d[0] * ca + d[1] * sa, -d[0] * sa + d[1] * ca)
    return sdf_box(local, Vec2(0, 0), half)


# --- boolean combinators -----------------------------------------------------


def sdf_union(a: Real, b: Real) -> Real:
    return min(a, b)


def sdf_intersect(a: Real, b: Real) -> Real:
    return max(a, b)


def sdf_subtract(a: Real, b: Real) -> Real:
    """`a` with `b` carved out."""
    return max(a, -b)


# --- tagged shape ------------------------------------------------------------


@fieldwise_init
struct SdfShape(Copyable, ImplicitlyCopyable, Movable):
    var kind: Int  # 0 = circle, 1 = box (AABB), 2 = obb
    var center: Vec2
    var half: Vec2  # circle stores its radius in half[0]
    var angle: Real

    @staticmethod
    def circle(c: Vec2, r: Real) -> Self:
        return Self(0, c, Vec2(r, r), 0)

    @staticmethod
    def box(c: Vec2, half: Vec2) -> Self:
        return Self(1, c, half, 0)

    @staticmethod
    def obb(c: Vec2, half: Vec2, angle: Real) -> Self:
        return Self(2, c, half, angle)

    def distance(self, p: Vec2) -> Real:
        if self.kind == 0:
            return sdf_circle(p, self.center, self.half[0])
        elif self.kind == 1:
            return sdf_box(p, self.center, self.half)
        else:
            return sdf_obb(p, self.center, self.half, self.angle)

    def gradient(self, p: Vec2) -> Vec2:
        """Outward unit normal estimated by central differences of `distance`."""
        var eps = Real(1e-3)
        var dx = self.distance(Vec2(p[0] + eps, p[1])) - self.distance(
            Vec2(p[0] - eps, p[1])
        )
        var dy = self.distance(Vec2(p[0], p[1] + eps)) - self.distance(
            Vec2(p[0], p[1] - eps)
        )
        return normalize(Vec2(dx, dy))


def sdf_collide(a: SdfShape, b: SdfShape) -> SATResult:
    """Exact for (circle vs any) pairs; coarse center test otherwise."""
    if a.kind == 0:
        # a is a circle: distance of its center to b's field minus radius.
        var d = b.distance(a.center) - a.half[0]
        if d >= 0:
            return SATResult.miss()
        var n = -b.gradient(a.center)  # gradient points away from b -> flip to a->b
        return SATResult(True, n, -d)
    if b.kind == 0:
        var d = a.distance(b.center) - b.half[0]
        if d >= 0:
            return SATResult.miss()
        var n = a.gradient(b.center)  # away from a == toward b
        return SATResult(True, n, -d)
    # Coarse fallback for box/obb vs box/obb: one center inside the other.
    var da = a.distance(b.center)
    var db = b.distance(a.center)
    if da >= 0 and db >= 0:
        return SATResult.miss()
    var dir = normalize(b.center - a.center)
    var depth = -min(da, db)
    return SATResult(True, dir, depth)
