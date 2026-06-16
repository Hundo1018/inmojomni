from harness.runner import Suite
from ecs.world import World
from ecs.archetype import ArchetypeBackend
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


@fieldwise_init
struct Frozen(ComponentType):
    comptime ID: Int = 2
    var flag: Int


def main() raises:
    var s = Suite("archetype_backend")
    var w = World[ArchetypeBackend[Position, Velocity, Frozen]]()

    var e = w.spawn()  # archetype {}
    w.set(e, Position(3, 4))  # moves to archetype {P}
    s.check(w.has[Position](e), "has P after add")
    s.eqi(w.get[Position](e).x, 3, "P preserved across move to {P}")

    w.set(e, Velocity(1, 2))  # moves {P} -> {P,V}, P value must survive the move
    s.check(w.has[Velocity](e), "has V")
    s.eqi(w.get[Position](e).x, 3, "P survives move to {P,V}")
    s.eqi(w.get[Velocity](e).dy, 2, "V correct")

    # second entity straight to {P,V}
    var e2 = w.spawn2(Position(10, 20), Velocity(5, 6))
    s.eqi(w.get[Position](e2).x, 10, "e2 P")
    s.eqi(w.get[Velocity](e2).dx, 5, "e2 V")

    # removing a component moves back; remaining components must survive
    w.remove[Velocity](e)  # {P,V} -> {P}
    s.check(not w.has[Velocity](e), "V removed")
    s.eqi(w.get[Position](e).x, 3, "P survives move back to {P}")
    # e2 unaffected by e's relocation (swap-remove bookkeeping)
    s.eqi(w.get[Position](e2).x, 10, "e2 P intact after e moved")
    s.eqi(w.get[Velocity](e2).dx, 5, "e2 V intact after e moved")

    # overwrite in place (no move)
    w.set(e2, Position(11, 22))
    s.eqi(w.get[Position](e2).x, 11, "in-place overwrite")

    # queries across archetypes
    s.eqi(len(w.query1[Position]()), 2, "2 have P")
    s.eqi(len(w.query2[Position, Velocity]()), 1, "1 has P+V (only e2)")

    w.despawn(e2)
    s.eqi(w.entity_count(), 1, "count after despawn")
    s.check(w.is_alive(e) and not w.is_alive(e2), "liveness after despawn")
    s.eqi(len(w.query2[Position, Velocity]()), 0, "no P+V after despawn e2")

    s.finish()
