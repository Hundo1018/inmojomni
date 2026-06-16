"""Dimension-generic vector math built on SIMD.

`WorldType` is the world's scalar dtype; `Vec2`/`Vec3` are SIMD vectors. We keep
the *actual* SIMD width equal to the dimension (2 or 3) and NEVER use SIMD
`reduce_*` for reductions — on width-3 it silently drops the third lane in this
nightly. Reductions are done with an explicit `comptime for` over the lanes.

Width-generic helpers infer the width with `[w: SIMDSize, //]` (SIMD's width
parameter is `SIMDSize`, not `Int`, so plain `Int` would not infer from a value).
"""

from std.math import sqrt

comptime WorldType = DType.float32
comptime Real = Scalar[WorldType]
comptime Vec2 = SIMD[WorldType, 2]
comptime Vec3 = SIMD[WorldType, 3]


def dot[w: SIMDSize, //](a: SIMD[WorldType, w], b: SIMD[WorldType, w]) -> Real:
    """Lane-wise multiply then sum. Manual reduction (width-3 `reduce_add` is broken)."""
    var prod = a * b
    var s = Real(0)
    comptime for i in range(Int(w)):
        s += prod[i]
    return s


def length_sq[w: SIMDSize, //](a: SIMD[WorldType, w]) -> Real:
    return dot(a, a)


def length[w: SIMDSize, //](a: SIMD[WorldType, w]) -> Real:
    return sqrt(length_sq(a))


def distance_sq[w: SIMDSize, //](a: SIMD[WorldType, w], b: SIMD[WorldType, w]) -> Real:
    return length_sq(a - b)


def normalize[w: SIMDSize, //](a: SIMD[WorldType, w]) -> SIMD[WorldType, w]:
    var n = length(a)
    if n == 0:
        return a
    return a / n


def lane_min[w: SIMDSize, //](
    a: SIMD[WorldType, w], b: SIMD[WorldType, w]
) -> SIMD[WorldType, w]:
    var r = a
    comptime for i in range(Int(w)):
        if b[i] < r[i]:
            r[i] = b[i]
    return r


def lane_max[w: SIMDSize, //](
    a: SIMD[WorldType, w], b: SIMD[WorldType, w]
) -> SIMD[WorldType, w]:
    var r = a
    comptime for i in range(Int(w)):
        if b[i] > r[i]:
            r[i] = b[i]
    return r


def splat[d: Int](v: Real) -> SIMD[WorldType, d]:
    """A vector with every lane set to `v` (width passed explicitly)."""
    var r = SIMD[WorldType, d](0)
    comptime for i in range(d):
        r[i] = v
    return r
