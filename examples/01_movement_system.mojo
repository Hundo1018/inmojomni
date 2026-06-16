"""Example 01 — a movement system over an ECS query.

Spawn a few entities with Position + Velocity, then each frame query the entities
that have both and advance their position. Run:

    pixi run mojo run -I build examples/01_movement_system.mojo
"""

from ecs.world import World
from ecs.sparse_backend import SparseSetBackend
from ecs.component import ComponentType


@fieldwise_init
struct Position(ComponentType):
    comptime ID: Int = 0
    var x: Float64
    var y: Float64


@fieldwise_init
struct Velocity(ComponentType):
    comptime ID: Int = 1
    var dx: Float64
    var dy: Float64


def main():
    var w = World[SparseSetBackend[Position, Velocity]]()

    _ = w.spawn2(Position(0, 0), Velocity(1, 0))
    _ = w.spawn2(Position(10, 10), Velocity(0, -2))
    _ = w.spawn1(Position(99, 99))  # no Velocity: ignored by the movement system

    print("entities:", w.entity_count())
    for frame in range(3):
        var movers = w.query2[Position, Velocity]()
        for i in range(len(movers)):
            var e = movers[i]
            var p = w.get[Position](e)
            var v = w.get[Velocity](e)
            w.set(e, Position(p.x + v.dx, p.y + v.dy))
        print("after frame", frame + 1, "moved", len(movers), "entities")

    var all = w.query1[Position]()
    for i in range(len(all)):
        var p = w.get[Position](all[i])
        print("  entity", all[i].id, "-> (", p.x, ",", p.y, ")")
