trait ShapeSupportable:
    def support[T: DType, size: Int](self, vec: SIMD[T, size]):
        ...


trait ShapeAABBable:
    def aabb[T: DType, size: Int](self, min: SIMD[T, size], max: SIMD[T, size]):
        ...


@fieldwise_init
struct Circle[T: DType](TrivialRegisterPassable):
    comptime Vec2 = SIMD[Self.T, 2]
    var center: Self.Vec2
    var radius: Self.Vec2


@fieldwise_init
struct AABB[T: DType](TrivialRegisterPassable):
    comptime min = SIMD[Self.T, 2]
    comptime max = SIMD[Self.T, 2]


@fieldwise_init
struct Triangle[T: DType](TrivialRegisterPassable):
    comptime vertices = InlineArray[SIMD[Self.T, 2], 3]


@fieldwise_init
struct ConvexPolygon[T: DType, size: Int](TrivialRegisterPassable):
    comptime vertices = SIMD


def main():
    var c = Circle[DType.float32](0, 2)
