"""Physics body contract + a default 2D body.

`PhysicsBody` refines `ComponentType`, so a body is just an ECS component the
integrator knows how to advance. Implement it for your own body component to swap
in different motion (e.g. damping, mass), and the integrator works unchanged.
`Body2` is a ready-made 2D point-mass body advanced by semi-implicit Euler.
"""

from ecs.component import ComponentType
from geometry.vec import Vec2, Real


trait PhysicsBody(ComponentType):
    def position(self) -> Vec2: ...
    def velocity(self) -> Vec2: ...
    def step(self, dt: Real, gravity: Vec2) -> Self: ...


@fieldwise_init
struct Body2(PhysicsBody):
    comptime ID: Int = 0
    var pos: Vec2
    var vel: Vec2

    def position(self) -> Vec2:
        return self.pos

    def velocity(self) -> Vec2:
        return self.vel

    def step(self, dt: Real, gravity: Vec2) -> Self:
        # semi-implicit (symplectic) Euler: integrate velocity first, then position
        var nv = self.vel + gravity * dt
        var np = self.pos + nv * dt
        return Self(np, nv)
