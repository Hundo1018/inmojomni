"""The swappability contract: an identical scenario produces identical results
on the sparse-set backend and the archetype backend."""

from harness.runner import Suite
from ecs.world import World
from ecs.storage import StorageBackend
from ecs.sparse_backend import SparseSetBackend
from ecs.archetype import ArchetypeBackend
from ecs.bitset_backend import BitsetBackend
from ecs.reactive_backend import ReactiveBackend
from ecs.naive_backend import NaiveBackend
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


@fieldwise_init
struct Frozen(ComponentType):
    comptime ID: Int = 2
    var flag: Int


# A fixed scenario written once against the StorageBackend interface; returns an
# order-independent summary so the two backends can be compared exactly.
def run_scenario[B: StorageBackend]() -> List[Int]:
    var w = World[B]()
    var ents = List[Entity]()
    for _ in range(10):
        ents.append(w.spawn())

    # give every entity a Position; even ids also get Velocity; multiples of 3 Frozen
    for i in range(10):
        w.set(ents[i], Position(i, i * 2))
        if i % 2 == 0:
            w.set(ents[i], Velocity(1, 1))
        if i % 3 == 0:
            w.set(ents[i], Frozen(1))

    # despawn entity 4 and remove Velocity from entity 6
    w.despawn(ents[4])
    w.remove[Velocity](ents[6])

    # run a movement system: pos += vel
    var movers = w.query2[Position, Velocity]()
    for i in range(len(movers)):
        var e = movers[i]
        var p = w.get[Position](e)
        var v = w.get[Velocity](e)
        w.set(e, Position(p.x + v.dx, p.y + v.dy))

    # order-independent summary
    var sum_x = 0
    var p_all = w.query1[Position]()
    for i in range(len(p_all)):
        sum_x += w.get[Position](p_all[i]).x

    var out = List[Int]()
    out.append(w.entity_count())
    out.append(len(w.query1[Position]()))
    out.append(len(w.query2[Position, Velocity]()))
    out.append(len(w.query3[Position, Velocity, Frozen]()))
    out.append(sum_x)
    return out^


def _compare(
    mut s: Suite, name: String, sparse: List[Int], other: List[Int]
):
    var labels = List[String]()
    labels.append("entity_count")
    labels.append("count[P]")
    labels.append("count[P,V]")
    labels.append("count[P,V,F]")
    labels.append("sum_x")
    s.eqi(len(other), len(sparse), name + ": summary length matches")
    for i in range(len(sparse)):
        s.eqi(other[i], sparse[i], name + " parity: " + labels[i])


def main() raises:
    var s = Suite("backend_parity")

    # The sparse-set backend is the reference; every other backend must produce
    # the identical order-independent summary for the same scenario.
    var sparse = run_scenario[SparseSetBackend[Position, Velocity, Frozen]]()
    var arch = run_scenario[ArchetypeBackend[Position, Velocity, Frozen]]()
    var bitset = run_scenario[BitsetBackend[Position, Velocity, Frozen]]()
    var reactive = run_scenario[ReactiveBackend[Position, Velocity, Frozen]]()
    var naive = run_scenario[NaiveBackend[Position, Velocity, Frozen]]()

    _compare(s, "archetype", sparse, arch)
    _compare(s, "bitset", sparse, bitset)
    _compare(s, "reactive", sparse, reactive)
    _compare(s, "naive", sparse, naive)

    # sanity: the scenario isn't trivially empty
    s.eqi(sparse[0], 9, "9 entities remain (10 - 1 despawned)")

    s.finish()
