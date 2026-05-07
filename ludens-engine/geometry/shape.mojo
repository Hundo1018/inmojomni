from std.math import pow

comptime WorldType = DType.float32
comptime Vec1 = SIMD[WorldType, 1]
comptime Vec2 = SIMD[WorldType, 2]


trait Intersectable:
    def isintersect(self, other: Self) -> Bool:
        ...


@fieldwise_init
struct Circle(Intersectable, TrivialRegisterPassable):
    var center: Vec2
    var radius: Vec1

    @always_inline
    def isintersect(self, other: Self) -> Bool:
        return pow(other.center[0] - self.center[0], 2) + pow(
            other.center[1] - self.center[1], 2
        ) <= pow(self.radius + other.radius, 2)


@fieldwise_init
struct AABB(TrivialRegisterPassable):
    var min: Vec2
    var max: Vec2


@fieldwise_init
struct Triangle(TrivialRegisterPassable):
    var vertices: SIMD[WorldType, 6]


def main():
    var c0 = Circle(Vec2(0, 0), 1)
    var c1 = Circle(Vec2(0, 0), 2)
    print(c0.isintersect(c1))
