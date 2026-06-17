"""EPA (Expanding Polytope Algorithm) penetration for 2D convex shapes.

GJK answers *whether* two convex shapes overlap; EPA recovers *by how much*. We
seed a polytope with GJK's terminating simplex, then repeatedly find the polytope
edge closest to the origin, push a support point outward along that edge's
normal, and insert it — until the support stops moving past the edge. The closest
edge's distance is the penetration depth and its normal the contact normal.

Only 2D is implemented (the benchmark's penetration column is 2D); `gjk_collide`
returns a boolean hit with zero penetration in 3D. The 2D helper is only ever
instantiated at `dim == 2` (guarded by `comptime if`), so its `List[Vec2]`
polytope is realloc-safe. The normal is oriented from `a` toward `b`.
"""

from .vec import WorldType, Real, Vec2, dot, normalize, length
from .gjk import ConvexPoly, Simplex, gjk_query


@fieldwise_init
struct EpaResult[dim: Int](Copyable, ImplicitlyCopyable, Movable):
    var hit: Bool
    var normal: SIMD[WorldType, Self.dim]  # points from a -> b
    var depth: Real

    @staticmethod
    def miss() -> Self:
        return Self(False, SIMD[WorldType, Self.dim](0), 0)


def _centroid[dim: Int](p: ConvexPoly[dim]) -> SIMD[WorldType, dim]:
    var c = SIMD[WorldType, dim](0)
    for i in range(len(p.points)):
        c += p.points[i].v
    return c / Real(len(p.points))


def _epa2[dim: Int](
    a: ConvexPoly[dim], b: ConvexPoly[dim], simplex: Simplex[dim]
) -> EpaResult[dim]:
    """2D EPA. Only instantiated at dim == 2, so Vec lists are realloc-safe."""
    var poly = List[SIMD[WorldType, dim]]()
    # Seed from the simplex's (up to 3) distinct points.
    poly.append(simplex.pa)
    if not _same(simplex.pb, simplex.pa):
        poly.append(simplex.pb)
    if not _same(simplex.pc, simplex.pa) and not _same(simplex.pc, simplex.pb):
        poly.append(simplex.pc)

    var ca = _centroid[dim](a)
    var cb = _centroid[dim](b)

    if len(poly) < 3:
        # Degenerate seed (shapes barely touching): fall back to centroid dir.
        var n = normalize(cb - ca)
        return EpaResult[dim](True, n, Real(1e-4))

    # Ensure CCW winding so edge right-normals point outward.
    if _signed_area[dim](poly) < 0:
        var rev = List[SIMD[WorldType, dim]]()
        for i in range(len(poly)):
            rev.append(poly[len(poly) - 1 - i])
        poly = rev^

    var result_n = SIMD[WorldType, dim](0)
    var result_d = Real(0)
    for _ in range(64):
        # Closest edge of the polytope to the origin.
        var min_dist = Real(1.0e30)
        var min_idx = 0
        var min_normal = SIMD[WorldType, dim](0)
        var m = len(poly)
        for i in range(m):
            var p0 = poly[i]
            var p1 = poly[(i + 1) % m]
            var e = p1 - p0
            var nrm = normalize(_perp_out[dim](e))
            var dist = dot(nrm, p0)
            if dist < min_dist:
                min_dist = dist
                min_idx = i
                min_normal = nrm
        # Support of the Minkowski difference along the edge normal.
        var sp = a.support(min_normal) - b.support(-min_normal)
        var d = dot(sp, min_normal)
        result_n = min_normal
        result_d = min_dist
        if d - min_dist < Real(1e-4):
            break
        # Insert the support point after min_idx and continue expanding.
        var newpoly = List[SIMD[WorldType, dim]]()
        for i in range(m):
            newpoly.append(poly[i])
            if i == min_idx:
                newpoly.append(sp)
        poly = newpoly^

    # Orient from a -> b.
    if dot(cb - ca, result_n) < 0:
        result_n = -result_n
    return EpaResult[dim](True, result_n, result_d)


def _same[dim: Int](a: SIMD[WorldType, dim], b: SIMD[WorldType, dim]) -> Bool:
    return length(a - b) < Real(1e-9)


def _perp_out[dim: Int](e: SIMD[WorldType, dim]) -> SIMD[WorldType, dim]:
    """Right-hand normal of edge `e` (outward for a CCW polygon)."""
    var r = SIMD[WorldType, dim](0)
    r[0] = e[1]
    r[1] = -e[0]
    return r


def _signed_area[dim: Int](poly: List[SIMD[WorldType, dim]]) -> Real:
    var area = Real(0)
    var n = len(poly)
    for i in range(n):
        var p0 = poly[i]
        var p1 = poly[(i + 1) % n]
        area += p0[0] * p1[1] - p1[0] * p0[1]
    return area


def gjk_collide[dim: Int](
    a: ConvexPoly[dim], b: ConvexPoly[dim]
) -> EpaResult[dim]:
    """GJK overlap test; on a hit, EPA penetration in 2D (boolean-only in 3D)."""
    var q = gjk_query[dim](a, b)
    if not q.hit:
        return EpaResult[dim].miss()
    comptime if dim == 2:
        return _epa2[dim](a, b, q.simplex)
    else:
        return EpaResult[dim](True, SIMD[WorldType, dim](0), 0)
