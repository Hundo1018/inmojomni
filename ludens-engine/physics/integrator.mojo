"""A motion system: advance every entity carrying a `PhysicsBody` by one step.

Generic over both the ECS backend and the body type, so it runs unchanged on the
sparse-set or archetype backend and with any `PhysicsBody` implementation.
"""

from ecs.world import World
from ecs.storage import StorageBackend
from geometry.vec import Vec2, Real
from .body import PhysicsBody


def integrate[B: StorageBackend, Body: PhysicsBody](
    mut w: World[B], dt: Real, gravity: Vec2
):
    var es = w.query1[Body]()
    for i in range(len(es)):
        var b = w.get[Body](es[i])
        w.set[Body](es[i], b.step(dt, gravity))
