from harness.runner import Suite
from ecs.world import World
from ecs.naive_backend import NaiveBackend
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
    var s = Suite("naive_backend")
    var w = World[NaiveBackend[Position, Velocity]]()

    var e0 = w.spawn2(Position(1, 2), Velocity(3, 4))
    var e1 = w.spawn1(Position(5, 6))
    var e2 = w.spawn2(Position(7, 8), Velocity(9, 10))

    s.eqi(w.entity_count(), 3, "three entities")
    s.eqi(len(w.query1[Position]()), 3, "all have position")
    s.eqi(len(w.query2[Position, Velocity]()), 2, "two have velocity")

    s.check(w.has[Velocity](e0), "e0 has velocity")
    s.check(not w.has[Velocity](e1), "e1 lacks velocity")
    s.eqi(w.get[Position](e2).x, 7, "e2 position x")

    # remove + despawn
    w.remove[Velocity](e0)
    s.check(not w.has[Velocity](e0), "velocity removed from e0")
    s.eqi(len(w.query2[Position, Velocity]()), 1, "one velocity left")

    w.despawn(e1)
    s.eqi(w.entity_count(), 2, "two after despawn")
    s.check(not w.is_alive(e1), "e1 dead")
    s.eqi(len(w.query1[Position]()), 2, "two positions after despawn")

    s.finish()
