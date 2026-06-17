from harness.runner import Suite
from ecs.world import World
from ecs.bitset_backend import BitsetBackend
from ecs.component import ComponentType
from ecs.entity import Entity


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
    var s = Suite("bitset_backend")
    var w = World[BitsetBackend[Position, Velocity]]()

    # Spawn enough entities to span several 64-bit bitset words, so the
    # word-by-word AND and the cross-word bit walking are exercised.
    var n = 130
    var ents = List[Int]()
    for i in range(n):
        var e = w.spawn1(Position(i, i))
        ents.append(e.id)
        if i % 2 == 0:
            w.set(e, Velocity(1, 1))

    s.eqi(w.entity_count(), n, "all entities live")
    s.eqi(len(w.query1[Position]()), n, "all positions")
    s.eqi(len(w.query2[Position, Velocity]()), 65, "even ids have velocity")

    # Remove velocity from id 0 (word 0) and id 128 (word 2) -> 63 remain.
    w.remove[Velocity](Entity(0, 0))
    w.remove[Velocity](Entity(128, 0))
    s.eqi(len(w.query2[Position, Velocity]()), 63, "two removed across words")

    # Despawn an odd id (no velocity) and an even id (with velocity).
    w.despawn(Entity(1, 0))
    w.despawn(Entity(64, 0))  # word 1, had velocity
    s.eqi(w.entity_count(), n - 2, "two despawned")
    s.eqi(len(w.query2[Position, Velocity]()), 62, "velocity count after despawn")

    s.finish()
