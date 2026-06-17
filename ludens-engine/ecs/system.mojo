"""Reusable fast-path systems over the archetype backend's SoA columns.

The generic `World.query2() + get/set` path is ergonomic but slow: it allocates a
`List[Entity]` per call and every `get`/`set` walks the entity index and a
type-erased slot. The *fast* path is to iterate an archetype's component columns
directly — they are contiguous (true SoA), so a system streams them and can even
SIMD over them. This module packages that fast path as engine API so game code
gets the locality benefit without re-deriving the column plumbing.

`integrate2_simd` is the canonical example: `a += b * dt` over two `Vec2`-shaped
component columns (e.g. Position += Velocity * dt), vectorized. It treats each
8-byte component column as a flat `Float32` buffer, so it works for *any* pair of
single-`Vec2`-field components — the common physics-integration shape.

SoA aligned columns are an archetype capability, so these take an
`ArchetypeBackend` concretely (not the `StorageBackend` trait). For the scalar
SoA path, iterate `backend.query2_views[A, B]()` and use `get_a`/`set_a` directly.
"""

from std.memory import alloc
from .component import ComponentType
from .archetype import ArchetypeBackend

# The engine's world scalar type. Kept local so `ecs` stays independent of
# `geometry`; it matches `geometry.vec.WorldType` (the components are Vec2).
comptime F = DType.float32


def integrate2_simd[
    A: ComponentType, B: ComponentType, *CTs: ComponentType
](mut backend: ArchetypeBackend[*CTs], dt: Scalar[F]):
    """`A += B * dt` over every matching archetype, column-wise with SIMD.

    Both `A` and `B` must be single-`Vec2`-field components (8 bytes), so each
    column is a contiguous run of `Float32` lane pairs. Width-8 SIMD covers four
    `Vec2`s per step; a scalar tail handles the remainder.
    """
    comptime W = 8
    var views = backend.query2_views[A, B]()
    for vi in range(len(views)):
        var v = views[vi]
        var fa = v.unsafe_col_a().bitcast[Scalar[F]]()
        var fb = v.unsafe_col_b().bitcast[Scalar[F]]()
        var m = 2 * v.len()  # two floats (x, y) per component
        var i = 0
        while i + W <= m:
            fa.store(i, fa.load[width=W](i) + fb.load[width=W](i) * dt)
            i += W
        while i < m:
            fa.store(i, fa.load(i) + fb.load(i) * dt)
            i += 1
