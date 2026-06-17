"""Narrowphase: the exact contact test run on each broadphase candidate pair.

`NarrowPhase` is the swap point. Each implementation owns a per-proxy registry of
its shape kind (populate it with `add(...)`, which returns the proxy id) and
answers `test(a, b) -> Contact`. Swap implementations by instantiating
`CollisionPipeline` with a different narrowphase type.

  * `AABBNarrowPhase[dim]` — box overlap with minimum-translation penetration.
  * `CircleNarrowPhase`    — 2D circles (reuses `Circle.isintersect`).
  * `SATNarrowPhase`       — 2D convex polygons (separating axis theorem).
  * `GJKNarrowPhase[dim]`  — convex shapes in 2D/3D (boolean GJK).
"""

from geometry.vec import WorldType, Real, Vec2, distance_sq, length, normalize
from geometry.aabb import AABB
from geometry.shape import Circle, Polygon
from geometry.sat import sat_collide
from geometry.gjk import ConvexPoly
from geometry.epa import gjk_collide
from geometry.obb import OBB, obb_collide
from geometry.sdf import SdfShape, sdf_collide


@fieldwise_init
struct Contact[dim: Int](Copyable, ImplicitlyCopyable, Movable):
    var hit: Bool
    var normal: SIMD[WorldType, Self.dim]  # points from a -> b
    var depth: Real

    @staticmethod
    def miss() -> Self:
        return Self(False, SIMD[WorldType, Self.dim](0), 0)


trait NarrowPhase(Movable, ImplicitlyDeletable):
    comptime dim: Int
    def test(self, a: Int, b: Int) -> Contact[Self.dim]: ...


struct AABBNarrowPhase[D: Int](NarrowPhase):
    comptime dim: Int = Self.D
    var boxes: List[AABB[Self.D]]

    def __init__(out self):
        self.boxes = List[AABB[Self.D]]()

    def add(mut self, box: AABB[Self.D]) -> Int:
        self.boxes.append(box)
        return len(self.boxes) - 1

    def test(self, a: Int, b: Int) -> Contact[Self.D]:
        var ba = self.boxes[a]
        var bb = self.boxes[b]
        var best_depth = Real(1.0e30)
        var best_axis = 0
        comptime for k in range(Self.D):
            var lo = max(ba.min[k], bb.min[k])
            var hi = min(ba.max[k], bb.max[k])
            var overlap = hi - lo
            if overlap <= 0:
                return Contact[Self.D].miss()
            if overlap < best_depth:
                best_depth = overlap
                best_axis = k
        var n = SIMD[WorldType, Self.D](0)
        var dir = bb.center()[best_axis] - ba.center()[best_axis]
        n[best_axis] = 1 if dir >= 0 else -1
        return Contact[Self.D](True, n, best_depth)


struct CircleNarrowPhase(NarrowPhase):
    comptime dim: Int = 2
    var circles: List[Circle]

    def __init__(out self):
        self.circles = List[Circle]()

    def add(mut self, c: Circle) -> Int:
        self.circles.append(c)
        return len(self.circles) - 1

    def test(self, a: Int, b: Int) -> Contact[2]:
        var ca = self.circles[a]
        var cb = self.circles[b]
        var rsum = ca.radius + cb.radius
        if distance_sq(ca.center, cb.center) > rsum * rsum:
            return Contact[2].miss()
        var delta = cb.center - ca.center
        var dist = length(delta)
        var n = normalize(delta) if dist > 0 else Vec2(1, 0)
        return Contact[2](True, n, rsum - dist)


struct SATNarrowPhase(NarrowPhase):
    comptime dim: Int = 2
    var polys: List[Polygon]

    def __init__(out self):
        self.polys = List[Polygon]()

    def add(mut self, var p: Polygon) -> Int:
        self.polys.append(p^)
        return len(self.polys) - 1

    def test(self, a: Int, b: Int) -> Contact[2]:
        var r = sat_collide(self.polys[a], self.polys[b])
        return Contact[2](r.hit, r.normal, r.depth)


struct GJKNarrowPhase[D: Int](NarrowPhase):
    comptime dim: Int = Self.D
    var shapes: List[ConvexPoly[Self.D]]

    def __init__(out self):
        self.shapes = List[ConvexPoly[Self.D]]()

    def add(mut self, var s: ConvexPoly[Self.D]) -> Int:
        self.shapes.append(s^)
        return len(self.shapes) - 1

    def test(self, a: Int, b: Int) -> Contact[Self.D]:
        # GJK + EPA: hit plus penetration (depth/normal exact in 2D, zero in 3D).
        var r = gjk_collide[Self.D](self.shapes[a], self.shapes[b])
        return Contact[Self.D](r.hit, r.normal, r.depth)


struct OBBNarrowPhase(NarrowPhase):
    comptime dim: Int = 2
    var boxes: List[OBB]

    def __init__(out self):
        self.boxes = List[OBB]()

    def add(mut self, box: OBB) -> Int:
        self.boxes.append(box)
        return len(self.boxes) - 1

    def test(self, a: Int, b: Int) -> Contact[2]:
        var r = obb_collide(self.boxes[a], self.boxes[b])
        return Contact[2](r.hit, r.normal, r.depth)


struct SDFNarrowPhase(NarrowPhase):
    comptime dim: Int = 2
    var shapes: List[SdfShape]

    def __init__(out self):
        self.shapes = List[SdfShape]()

    def add(mut self, shape: SdfShape) -> Int:
        self.shapes.append(shape)
        return len(self.shapes) - 1

    def test(self, a: Int, b: Int) -> Contact[2]:
        var r = sdf_collide(self.shapes[a], self.shapes[b])
        return Contact[2](r.hit, r.normal, r.depth)
