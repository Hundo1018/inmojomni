"""GJK boolean intersection for convex shapes in 2D and 3D.

A convex shape is a cloud of points; its `support(dir)` is the farthest point
along `dir`. GJK walks a simplex over the Minkowski difference A-B, steering it
toward the origin; if the simplex can enclose the origin the shapes intersect.

Two nightly hazards shape the data structures here:
  * A bare `List[SIMD[_,3]]` corrupts on realloc, so points are wrapped in `_Pt`
    (a struct List reallocs cleanly) and the simplex uses explicit fields, no List.
  * `comptime if dim` does not refine `dim` to a literal in types, so every helper
    is `[dim]`-generic and dim-specific ops (cross/perp) sit behind `comptime if`.
Perpendicular search directions use the triple product tprod(a,b,c)=b*(a.c)-c*(a.b).
"""

from .vec import WorldType, Real, dot


comptime _Vec[dim: Int] = SIMD[WorldType, dim]


@fieldwise_init
struct _Pt[dim: Int](Copyable, ImplicitlyCopyable, Movable):
    var v: _Vec[Self.dim]


struct ConvexPoly[dim: Int](Copyable, Movable):
    """Convex shape as a point cloud (its convex hull is what matters).

    Build with `add()` — never hand it a bare `List[Vec3]` (width-3 realloc bug).
    """

    var points: List[_Pt[Self.dim]]

    def __init__(out self):
        self.points = List[_Pt[Self.dim]]()

    def add(mut self, p: _Vec[Self.dim]):
        self.points.append(_Pt[Self.dim](p))

    def __len__(self) -> Int:
        return len(self.points)

    def support(self, dir: _Vec[Self.dim]) -> _Vec[Self.dim]:
        var best = self.points[0].v
        var best_d = dot(best, dir)
        for i in range(1, len(self.points)):
            var d = dot(self.points[i].v, dir)
            if d > best_d:
                best_d = d
                best = self.points[i].v
        return best


@fieldwise_init
struct Simplex[dim: Int](Copyable, Movable):
    """Up to 4 points held in explicit fields (`pa` is the most recent / "A")."""

    var pa: _Vec[Self.dim]
    var pb: _Vec[Self.dim]
    var pc: _Vec[Self.dim]
    var pd: _Vec[Self.dim]
    var n: Int

    @staticmethod
    def with1(a: _Vec[Self.dim]) -> Self:
        return Self(a, a, a, a, 1)

    def push(mut self, p: _Vec[Self.dim]):
        self.pd = self.pc
        self.pc = self.pb
        self.pb = self.pa
        self.pa = p
        if self.n < 4:
            self.n += 1

    def set2(mut self, a: _Vec[Self.dim], b: _Vec[Self.dim]):
        self.pa = a
        self.pb = b
        self.n = 2

    def set3(mut self, a: _Vec[Self.dim], b: _Vec[Self.dim], c: _Vec[Self.dim]):
        self.pa = a
        self.pb = b
        self.pc = c
        self.n = 3


def _tprod[dim: Int](a: _Vec[dim], b: _Vec[dim], c: _Vec[dim]) -> _Vec[dim]:
    """Vector triple product a x (b x c) = b*(a.c) - c*(a.b)."""
    return b * dot(a, c) - c * dot(a, b)


def _perp[dim: Int](ab: _Vec[dim]) -> _Vec[dim]:
    var r = _Vec[dim](0)
    r[0] = -ab[1]
    r[1] = ab[0]
    return r


def _cross[dim: Int](a: _Vec[dim], b: _Vec[dim]) -> _Vec[dim]:
    var r = _Vec[dim](0)
    r[0] = a[1] * b[2] - a[2] * b[1]
    r[1] = a[2] * b[0] - a[0] * b[2]
    r[2] = a[0] * b[1] - a[1] * b[0]
    return r


def _mink[dim: Int](
    a: ConvexPoly[dim], b: ConvexPoly[dim], dir: _Vec[dim]
) -> _Vec[dim]:
    """Support of the Minkowski difference A-B."""
    return a.support(dir) - b.support(-dir)


@fieldwise_init
struct GjkHit[dim: Int](Copyable, Movable):
    """Result of `gjk_query`: whether the shapes intersect plus the terminating
    simplex (used as EPA's seed polytope when there is a hit)."""

    var hit: Bool
    var simplex: Simplex[Self.dim]


def gjk_query[dim: Int](a: ConvexPoly[dim], b: ConvexPoly[dim]) -> GjkHit[dim]:
    """GJK that also returns the final simplex (see `gjk_intersect` for the test)."""
    var d = _Vec[dim](0)
    d[0] = 1  # arbitrary initial direction
    var s = Simplex[dim].with1(_mink(a, b, d))
    d = -s.pa

    for _ in range(64):
        if dot(d, d) == 0:
            return GjkHit[dim](True, s.copy())  # origin already on the simplex
        var p = _mink(a, b, d)
        if dot(p, d) < 0:
            return GjkHit[dim](False, s.copy())  # no support past origin -> separated
        s.push(p)
        if _do_simplex[dim](s, d):
            return GjkHit[dim](True, s.copy())
    return GjkHit[dim](False, s.copy())


def gjk_intersect[dim: Int](a: ConvexPoly[dim], b: ConvexPoly[dim]) -> Bool:
    return gjk_query[dim](a, b).hit


def _do_simplex[dim: Int](mut s: Simplex[dim], mut d: _Vec[dim]) -> Bool:
    if s.n == 2:
        return _line[dim](s, d)
    comptime if dim == 2:
        return _triangle2[dim](s, d)
    else:
        if s.n == 3:
            return _triangle3[dim](s, d)
        return _tetra3[dim](s, d)


def _line[dim: Int](mut s: Simplex[dim], mut d: _Vec[dim]) -> Bool:
    var a = s.pa
    var b = s.pb
    var ab = b - a
    var ao = -a
    d = _tprod[dim](ab, ao, ab)
    if dot(d, d) == 0:
        d = _perp[dim](ab)  # origin on the segment: pick a perpendicular
    return False


def _triangle2[dim: Int](mut s: Simplex[dim], mut d: _Vec[dim]) -> Bool:
    var a = s.pa
    var b = s.pb
    var c = s.pc
    var ao = -a
    var ab = b - a
    var ac = c - a
    var ab_perp = _tprod[dim](ac, ab, ab)
    var ac_perp = _tprod[dim](ab, ac, ac)
    if dot(ab_perp, ao) > 0:
        s.set2(a, b)
        d = ab_perp
        return False
    if dot(ac_perp, ao) > 0:
        s.set2(a, c)
        d = ac_perp
        return False
    return True  # origin inside the triangle


def _triangle3[dim: Int](mut s: Simplex[dim], mut d: _Vec[dim]) -> Bool:
    var a = s.pa
    var b = s.pb
    var c = s.pc
    var ao = -a
    var ab = b - a
    var ac = c - a
    var abc = _cross[dim](ab, ac)

    if dot(_cross[dim](abc, ac), ao) > 0:
        if dot(ac, ao) > 0:
            s.set2(a, c)
            d = _tprod[dim](ac, ao, ac)
            return False
        s.set2(a, b)
        return _line[dim](s, d)
    if dot(_cross[dim](ab, abc), ao) > 0:
        s.set2(a, b)
        return _line[dim](s, d)
    if dot(abc, ao) > 0:
        s.set3(a, b, c)
        d = abc
    else:
        s.set3(a, c, b)
        d = -abc
    return False


def _tetra3[dim: Int](mut s: Simplex[dim], mut d: _Vec[dim]) -> Bool:
    var a = s.pa
    var b = s.pb
    var c = s.pc
    var dd = s.pd
    var ao = -a
    var ab = b - a
    var ac = c - a
    var ad = dd - a
    var abc = _cross[dim](ab, ac)
    var acd = _cross[dim](ac, ad)
    var adb = _cross[dim](ad, ab)

    if dot(abc, ao) > 0:
        s.set3(a, b, c)
        return _triangle3[dim](s, d)
    if dot(acd, ao) > 0:
        s.set3(a, c, dd)
        return _triangle3[dim](s, d)
    if dot(adb, ao) > 0:
        s.set3(a, dd, b)
        return _triangle3[dim](s, d)
    return True  # origin enclosed by the tetrahedron
