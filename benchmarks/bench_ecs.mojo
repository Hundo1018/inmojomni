"""Engine benchmark: the same movement workload across every storage strategy.

One workload — spawn N entities with Position+Velocity, run F frames of a
movement system (query [P,V], integrate), then F query-only passes — is run
against all five ECS backends and the OOP engine. The output is a cross matrix
(variant x N x op) of ns/op so the strategies can be compared directly.

N is capped at a few thousand on purpose: each backend's `SparseSet` stores its
sparse index as an `InlineArray[Int, cap]` *by value*, so a large `cap` makes
codegen for the backend types explode (compile-time / memory blowup). The default
`cap=4096` keeps the whole matrix compiling in seconds — and that ceiling is
itself a maturity finding (a heap-backed sparse array is the natural next step
for million-entity scale). Run with: `mojo run -I build benchmarks/bench_ecs.mojo`.
"""

from std.benchmark import keep
from geometry.vec import Vec2, Real
from ecs.world import World
from ecs.storage import StorageBackend
from ecs.sparse_backend import SparseSetBackend
from ecs.archetype import ArchetypeBackend
from ecs.bitset_backend import BitsetBackend
from ecs.reactive_backend import ReactiveBackend
from ecs.naive_backend import NaiveBackend
from ecs.component import ComponentType
from oop.engine import Scene
from harness.bench import BenchTable, now


@fieldwise_init
struct Pos2(ComponentType):
    comptime ID: Int = 0
    var p: Vec2


@fieldwise_init
struct Vel2(ComponentType):
    comptime ID: Int = 1
    var v: Vec2


def run_movement[
    B: StorageBackend
](mut table: BenchTable, variant: String, n: Int, frames: Int):
    # --- spawn ---
    var t0 = now()
    var w = World[B]()
    for i in range(n):
        _ = w.spawn2(Pos2(Vec2(Real(i), 0)), Vel2(Vec2(1, 1)))
    var t1 = now()
    table.add(variant, n, "spawn", t1 - t0, n)

    # --- iterate + update (movement system) ---
    var sink = 0
    var t2 = now()
    for _ in range(frames):
        var movers = w.query2[Pos2, Vel2]()
        for i in range(len(movers)):
            var e = movers[i]
            var p = w.get[Pos2](e)
            var v = w.get[Vel2](e)
            w.set(e, Pos2(p.p + v.v))
        sink += len(movers)
    keep(sink)
    var t3 = now()
    table.add(variant, n, "update", t3 - t2, n * frames)

    # --- query only ---
    var qsum = 0
    var t4 = now()
    for _ in range(frames):
        qsum += len(w.query2[Pos2, Vel2]())
    keep(qsum)
    var t5 = now()
    table.add(variant, n, "query", t5 - t4, frames)


def run_archetype_soa(mut table: BenchTable, n: Int, frames: Int):
    """The archetype backend via its SoA column path (query2_views) — the fast
    path the generic `query2 + get/set` handle path leaves on the table."""
    var t0 = now()
    var w = World[ArchetypeBackend[Pos2, Vel2]]()
    for i in range(n):
        _ = w.spawn2(Pos2(Vec2(Real(i), 0)), Vel2(Vec2(1, 1)))
    var t1 = now()
    table.add("archetype (soa)", n, "spawn", t1 - t0, n)

    var t2 = now()
    for _ in range(frames):
        var views = w.backend.query2_views[Pos2, Vel2]()
        for vi in range(len(views)):
            var view = views[vi]
            for i in range(view.len()):
                view.set_a(i, Pos2(view.get_a(i).p + view.get_b(i).v))
    keep(0)
    var t3 = now()
    table.add("archetype (soa)", n, "update", t3 - t2, n * frames)

    var qsum = 0
    var t4 = now()
    for _ in range(frames):
        var views = w.backend.query2_views[Pos2, Vel2]()
        for vi in range(len(views)):
            qsum += views[vi].len()
    keep(qsum)
    var t5 = now()
    table.add("archetype (soa)", n, "query", t5 - t4, frames)


def run_oop(mut table: BenchTable, n: Int, frames: Int):
    var t0 = now()
    var scene = Scene()
    for i in range(n):
        _ = scene.spawn(Vec2(Real(i), 0), Vec2(1, 1), Vec2(0.5, 0.5))
    var t1 = now()
    table.add("oop", n, "spawn", t1 - t0, n)

    var t2 = now()
    for _ in range(frames):
        scene.step(1)
    keep(Int(scene.sum_x()))
    var t3 = now()
    table.add("oop", n, "update", t3 - t2, n * frames)


def bench_all(mut table: BenchTable, n: Int, frames: Int):
    run_movement[SparseSetBackend[Pos2, Vel2]](table, "sparse", n, frames)
    run_movement[ArchetypeBackend[Pos2, Vel2]](table, "archetype (handle)", n, frames)
    run_archetype_soa(table, n, frames)
    run_movement[BitsetBackend[Pos2, Vel2]](table, "bitset", n, frames)
    run_movement[ReactiveBackend[Pos2, Vel2]](table, "reactive", n, frames)
    run_movement[NaiveBackend[Pos2, Vel2]](table, "naive", n, frames)
    run_oop(table, n, frames)


def fill(mut table: BenchTable):
    # N is capped by the inline-array sparse store (default cap=4096).
    var frames = 20
    bench_all(table, 500, frames)
    bench_all(table, 1_000, frames)
    bench_all(table, 4_000, frames)


def main() raises:
    var table = BenchTable("ECS backends vs OOP — movement workload (F=20 frames)")
    fill(table)
    table.print_report()
