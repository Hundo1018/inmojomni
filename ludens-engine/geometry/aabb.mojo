"""Dimension-parametric axis-aligned bounding box.

`AABB[2]` (alias `AABB2`) is used by the quadtree and 2D collision; `AABB[3]`
(`AABB3`) by the octree and 3D collision. All overlap/containment tests are
elementwise `comptime for` loops over `dim` lanes (SIMD `<=` collapses to a
scalar `Bool` in this nightly, so it can't be used as a lane mask).
"""

from .vec import WorldType, Real, lane_min, lane_max


@fieldwise_init
struct AABB[dim: Int](Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    var min: SIMD[WorldType, Self.dim]
    var max: SIMD[WorldType, Self.dim]

    @staticmethod
    def from_center(
        center: SIMD[WorldType, Self.dim], half: SIMD[WorldType, Self.dim]
    ) -> Self:
        return Self(center - half, center + half)

    def overlaps(self, o: Self) -> Bool:
        comptime for i in range(Self.dim):
            if self.min[i] > o.max[i] or o.min[i] > self.max[i]:
                return False
        return True

    def contains_point(self, p: SIMD[WorldType, Self.dim]) -> Bool:
        comptime for i in range(Self.dim):
            if p[i] < self.min[i] or p[i] > self.max[i]:
                return False
        return True

    def contains(self, o: Self) -> Bool:
        """True if `o` is fully inside `self`."""
        comptime for i in range(Self.dim):
            if o.min[i] < self.min[i] or o.max[i] > self.max[i]:
                return False
        return True

    def merge(self, o: Self) -> Self:
        return Self(lane_min(self.min, o.min), lane_max(self.max, o.max))

    def center(self) -> SIMD[WorldType, Self.dim]:
        return (self.min + self.max) / 2

    def half_extents(self) -> SIMD[WorldType, Self.dim]:
        return (self.max - self.min) / 2

    def surface_area(self) -> Real:
        """Perimeter in 2D, surface area in 3D — the SAH cost metric for BVH."""
        var d = self.max - self.min
        comptime if Self.dim == 2:
            return 2 * (d[0] + d[1])
        else:
            return 2 * (d[0] * d[1] + d[1] * d[2] + d[0] * d[2])


comptime AABB2 = AABB[2]
comptime AABB3 = AABB[3]
