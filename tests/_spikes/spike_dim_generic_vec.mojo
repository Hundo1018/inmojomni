# Spike B: width-3 SIMD, AABB[dim], elementwise overlap, raise-based assert.
comptime WorldType = DType.float32


def assert_true(cond: Bool, msg: String) raises:
    if not cond:
        raise Error("ASSERT FAILED: " + msg)


@fieldwise_init
struct AABB[dim: Int](Copyable, Movable):
    var min: SIMD[WorldType, Self.dim]
    var max: SIMD[WorldType, Self.dim]

    def overlaps(self, o: Self) -> Bool:
        comptime for i in range(Self.dim):
            if self.min[i] > o.max[i]:
                return False
            if o.min[i] > self.max[i]:
                return False
        return True


def main() raises:
    var v2 = SIMD[WorldType, 2](1.0, 2.0)
    assert_true((v2 * v2).reduce_add() == 5.0, "v2 dot")

    # width-3 (non-power-of-two): reduce_add() is BROKEN (drops 3rd lane).
    # Workaround: manual elementwise reduction over lanes.
    var v3 = SIMD[WorldType, 3](1.0, 2.0, 2.0)
    var sq = v3 * v3
    var d3 = Scalar[WorldType](0)
    comptime for i in range(3):
        d3 += sq[i]
    print("width-3 manual len^2 =", d3, " (reduce_add gives wrong:", sq.reduce_add(), ")")
    assert_true(d3 == 9.0, "v3 dot")

    var box2a = AABB[2](SIMD[WorldType, 2](0, 0), SIMD[WorldType, 2](2, 2))
    var box2b = AABB[2](SIMD[WorldType, 2](1, 1), SIMD[WorldType, 2](3, 3))
    var box2c = AABB[2](SIMD[WorldType, 2](5, 5), SIMD[WorldType, 2](6, 6))
    assert_true(box2a.overlaps(box2b), "2d overlap")
    assert_true(not box2a.overlaps(box2c), "2d disjoint")

    var box3a = AABB[3](SIMD[WorldType, 3](0, 0, 0), SIMD[WorldType, 3](2, 2, 2))
    var box3b = AABB[3](SIMD[WorldType, 3](1, 1, 1), SIMD[WorldType, 3](3, 3, 3))
    assert_true(box3a.overlaps(box3b), "3d overlap")

    print("spike_dim_generic_vec: PASS")
