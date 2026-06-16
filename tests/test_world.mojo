from harness.runner import Suite
from ecs.world import World
from ecs.sparse_backend import SparseSetBackend
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
    var s = Suite("world")
    var w = World[SparseSetBackend[Position, Velocity]]()

    var e = w.spawn()
    s.check(w.is_alive(e), "alive after spawn")
    s.eqi(w.entity_count(), 1, "count 1")

    w.set(e, Position(3, 4))
    s.check(w.has[Position](e), "has Position")
    s.check(not w.has[Velocity](e), "no Velocity yet")

    var p = w.get[Position](e)
    s.eqi(p.x, 3, "pos x")
    s.eqi(p.y, 4, "pos y")

    w.set(e, Position(5, 6))  # overwrite
    s.eqi(w.get[Position](e).x, 5, "overwrite x")

    w.set(e, Velocity(1, -1))
    s.check(w.has[Velocity](e), "has Velocity after set")

    w.remove[Position](e)
    s.check(not w.has[Position](e), "Position removed")
    s.check(w.has[Velocity](e), "Velocity still there")

    # second entity + spawn helper
    var e2 = w.spawn2(Position(9, 9), Velocity(0, 0))
    s.eqi(w.entity_count(), 2, "count 2")
    s.eqi(w.get[Position](e2).x, 9, "e2 pos x")

    w.despawn(e)
    s.check(not w.is_alive(e), "dead after despawn")
    s.eqi(w.entity_count(), 1, "count back to 1")
    s.check(w.is_alive(e2), "e2 still alive")

    s.finish()
