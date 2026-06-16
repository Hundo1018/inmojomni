"""Example 02 — swap the ECS storage backend with zero game-code changes.

`run_game` is written once against `World[B: StorageBackend]`. We run the exact
same logic on the sparse-set backend and the archetype backend and print the
identical result. Run:

    pixi run mojo run -I build examples/02_swap_storage.mojo
"""

from ecs.world import World
from ecs.storage import StorageBackend
from ecs.sparse_backend import SparseSetBackend
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


def run_game[B: StorageBackend](label: String):
    var w = World[B]()
    for i in range(5):
        _ = w.spawn2(Position(i, 0), Velocity(2, 0))
    # one movement step
    var movers = w.query2[Position, Velocity]()
    for i in range(len(movers)):
        var e = movers[i]
        var p = w.get[Position](e)
        var v = w.get[Velocity](e)
        w.set(e, Position(p.x + v.dx, p.y + v.dy))
    var total_x = 0
    var all = w.query1[Position]()
    for i in range(len(all)):
        total_x += w.get[Position](all[i]).x
    print(label, "-> entities:", w.entity_count(), " sum(x):", total_x)


def main():
    print("Same game logic, two storage backends:")
    run_game[SparseSetBackend[Position, Velocity]]("sparse-set")
    run_game[ArchetypeBackend[Position, Velocity]]("archetype ")
    print("(both lines should match)")
