"""Primitive shapes and the `Intersectable` cross-shape contract.

`Circle`/`Sphere` are the simple radial primitives; `Polygon` is a convex
polygon used by the SAT and GJK narrowphase tests. `AABB[dim]` lives in
`geometry.aabb`. Reductions go through `geometry.vec` helpers (never SIMD
`reduce_*`, which is broken on width 3 here).
"""

from .vec import WorldType, Real, Vec2, Vec3, distance_sq


trait Intersectable(Copyable, Movable, ImplicitlyDeletable):
    """Same-shape overlap test, e.g. `Circle` vs `Circle`."""

    def isintersect(self, other: Self) -> Bool:
        ...


@fieldwise_init
struct Circle(Intersectable, Copyable, ImplicitlyCopyable, Movable):
    var center: Vec2
    var radius: Real

    def isintersect(self, other: Self) -> Bool:
        var rsum = self.radius + other.radius
        return distance_sq(self.center, other.center) <= rsum * rsum


@fieldwise_init
struct Sphere(Intersectable, Copyable, ImplicitlyCopyable, Movable):
    var center: Vec3
    var radius: Real

    def isintersect(self, other: Self) -> Bool:
        var rsum = self.radius + other.radius
        return distance_sq(self.center, other.center) <= rsum * rsum


struct Polygon(Copyable, Movable, Sized):
    """A convex polygon in 2D, vertices in CCW order."""

    var verts: List[Vec2]

    def __init__(out self, var verts: List[Vec2]):
        self.verts = verts^

    def __len__(self) -> Int:
        return len(self.verts)

    @staticmethod
    def box(cx: Real, cy: Real, hx: Real, hy: Real) -> Self:
        """An axis-aligned rectangle as a polygon, CCW from bottom-left."""
        var v = List[Vec2]()
        v.append(Vec2(cx - hx, cy - hy))
        v.append(Vec2(cx + hx, cy - hy))
        v.append(Vec2(cx + hx, cy + hy))
        v.append(Vec2(cx - hx, cy + hy))
        return Self(v^)

    def translated(self, dx: Real, dy: Real) -> Self:
        var v = List[Vec2]()
        for i in range(len(self.verts)):
            v.append(self.verts[i] + Vec2(dx, dy))
        return Self(v^)
