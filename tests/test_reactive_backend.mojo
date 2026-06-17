from harness.runner import Suite
from ecs.world import World
from ecs.reactive_backend import ReactiveBackend
from ecs.component import ComponentType


@fieldwise_init
struct Position(ComponentType):
    comptime ID: Int = 0
    var x: Int
    var y: Int


@fieldwise_init
struct Velocity(ComponentType):
    comptime ID: Int = 1
    var dx: Int
    var dy: Int


def main() raises:
    var s = Suite("reactive_backend")
    var w = World[ReactiveBackend[Position, Velocity]]()

    var e0 = w.spawn1(Position(0, 0))
    var e1 = w.spawn1(Position(1, 1))
    var e2 = w.spawn1(Position(2, 2))

    # First query registers and populates the Position group from live entities.
    s.eqi(len(w.query1[Position]()), 3, "position group populated lazily")
    # First [P,V] query registers an (initially empty) group.
    s.eqi(len(w.query2[Position, Velocity]()), 0, "no velocity yet")

    # Incremental growth: adding Velocity must update the cached group.
    w.set(e0, Velocity(1, 0))
    s.eqi(len(w.query2[Position, Velocity]()), 1, "group grew after set")
    w.set(e1, Velocity(0, 1))
    s.eqi(len(w.query2[Position, Velocity]()), 2, "group grew again")

    # Incremental shrink: removing the component drops the entity from the group.
    w.remove[Velocity](e0)
    s.eqi(len(w.query2[Position, Velocity]()), 1, "group shrank after remove")

    # Re-adding restores membership.
    w.set(e0, Velocity(5, 5))
    s.eqi(len(w.query2[Position, Velocity]()), 2, "group restored after re-add")

    # Despawn drops the entity from every group.
    w.despawn(e1)
    s.eqi(len(w.query2[Position, Velocity]()), 1, "despawn drops from [P,V] group")
    s.eqi(len(w.query1[Position]()), 2, "despawn drops from [P] group")
    s.eqi(w.entity_count(), 2, "two entities remain")
    _ = e2

    s.finish()
