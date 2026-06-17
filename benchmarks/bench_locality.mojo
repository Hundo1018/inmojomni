"""Crossover study: when does ECS beat OOP, and when does it not?

The first benchmark measured ECS through its *ergonomic* path (`query2 + get/set`,
which allocates and walks the entity index) on a workload that touches every
component of every entity with tiny 16-byte components — the one case where SoA
has no locality advantage. That made OOP's tight AoS loop look unbeatable. This
study fixes both: it exercises ECS through its *fast* SoA column path
(`query2_views`, `integrate2_simd`) and adds workloads that actually stress the
memory hierarchy. The result is the expected crossover — each paradigm wins where
its data layout fits the access pattern.

  W1 slim full-update : touch P+V, 16B components -> AoS competitive (no locality edge)
  W2 fat selective-read: read only Position, 512B cold payload -> SoA wins big
  W3 SIMD integrate    : column-wise pos += vel*dt -> ECS+SIMD fastest
  W4 structural churn  : add/remove a component every frame -> sparse/OOP beat archetype

Run with: `mojo run -I build benchmarks/bench_locality.mojo`.
"""

from std.benchmark import keep
from geometry.vec import Vec2, Real
from ecs.world import World
from ecs.archetype import ArchetypeBackend
from ecs.sparse_backend import SparseSetBackend
from ecs.system import integrate2_simd
from ecs.component import ComponentType
from ecs.entity import Entity
from oop.engine import Scene, FatScene
from harness.bench import BenchTable, now


@fieldwise_init
struct Pos2(ComponentType):
    comptime ID: Int = 0
    var p: Vec2


@fieldwise_init
struct Vel2(ComponentType):
    comptime ID: Int = 1
    var v: Vec2


@fieldwise_init
struct Payload(ComponentType):
    comptime ID: Int = 2
    var data: InlineArray[Int, 256]  # ~2 KB cold component (matches FatObject)


@fieldwise_init
struct Tag(ComponentType):
    comptime ID: Int = 3
    var v: Int


# ============================ W1 — slim full-update ==========================


def w1_slim_update(mut table: BenchTable, n: Int, frames: Int):
    var dt = Real(1)

    # OOP (tight AoS loop)
    var scene = Scene()
    for i in range(n):
        _ = scene.spawn(Vec2(Real(i), 0), Vec2(1, 1), Vec2(0.5, 0.5))
    var t0 = now()
    for _ in range(frames):
        scene.step(dt)
    keep(Int(scene.sum_x()))
    table.add("oop", n, "update", now() - t0, n * frames)

    # Archetype — handle path (the original, slow path)
    var wh = World[ArchetypeBackend[Pos2, Vel2]]()
    for i in range(n):
        _ = wh.spawn2(Pos2(Vec2(Real(i), 0)), Vel2(Vec2(1, 1)))
    var t1 = now()
    var sink = 0
    for _ in range(frames):
        var es = wh.query2[Pos2, Vel2]()
        for k in range(len(es)):
            var e = es[k]
            wh.set(e, Pos2(wh.get[Pos2](e).p + wh.get[Vel2](e).v * dt))
        sink += len(es)
    keep(sink)
    table.add("archetype (handle)", n, "update", now() - t1, n * frames)

    # Archetype — scalar SoA column path
    var ws = World[ArchetypeBackend[Pos2, Vel2]]()
    for i in range(n):
        _ = ws.spawn2(Pos2(Vec2(Real(i), 0)), Vel2(Vec2(1, 1)))
    var t2 = now()
    for _ in range(frames):
        var views = ws.backend.query2_views[Pos2, Vel2]()
        for vi in range(len(views)):
            var view = views[vi]
            for i in range(view.len()):
                view.set_a(i, Pos2(view.get_a(i).p + view.get_b(i).v * dt))
    keep(0)
    table.add("archetype (soa)", n, "update", now() - t2, n * frames)

    # Sparse — handle path (no aligned SoA view)
    var wsp = World[SparseSetBackend[Pos2, Vel2]]()
    for i in range(n):
        _ = wsp.spawn2(Pos2(Vec2(Real(i), 0)), Vel2(Vec2(1, 1)))
    var t3 = now()
    var sink2 = 0
    for _ in range(frames):
        var es = wsp.query2[Pos2, Vel2]()
        for k in range(len(es)):
            var e = es[k]
            wsp.set(e, Pos2(wsp.get[Pos2](e).p + wsp.get[Vel2](e).v * dt))
        sink2 += len(es)
    keep(sink2)
    table.add("sparse (handle)", n, "update", now() - t3, n * frames)


# ========================= W2 — fat selective-read ==========================


def _zeros() -> InlineArray[Int, 256]:
    return InlineArray[Int, 256](fill=0)


def _shuffled(n: Int) -> List[Int]:
    """A deterministic permutation of 0..n-1 (Fisher-Yates with an LCG)."""
    var order = List[Int]()
    for i in range(n):
        order.append(i)
    var state = UInt64(0x9E3779B9)
    for i in range(n - 1, 0, -1):
        state = state * 6364136223846793005 + 1442695040888963407
        var j = Int((state >> 33) % UInt64(i + 1))
        var tmp = order[i]
        order[i] = order[j]
        order[j] = tmp
    return order^


def w2_fat_selective(mut table: BenchTable, n: Int, frames: Int):
    # Scattered (random-order) read so the prefetcher can't hide the layout cost;
    # the ~2 KB cold payload makes the AoS footprint (~8 MB) overflow L2.
    var order = _shuffled(n)

    # OOP fat — each scattered read pulls a fat object's cache line.
    var scene = FatScene()
    for i in range(n):
        _ = scene.spawn(Vec2(Real(i), 0), Vec2(1, 1))
    var s0 = Real(0)
    var t0 = now()
    for _ in range(frames):
        s0 += scene.sum_pos_x_order(order)
    keep(Int(s0))
    table.add("oop-fat", n, "sum-pos.x", now() - t0, n * frames)

    # Archetype SoA — Position column (~32 KB) stays cache-resident; Payload
    # column is never touched.
    var wa = World[ArchetypeBackend[Pos2, Vel2, Payload]]()
    for i in range(n):
        var e = wa.spawn2(Pos2(Vec2(Real(i), 0)), Vel2(Vec2(1, 1)))
        wa.set(e, Payload(_zeros()))
    var s1 = Real(0)
    var t1 = now()
    for _ in range(frames):
        var views = wa.backend.query2_views[Pos2, Vel2]()
        var view = views[0]  # one archetype: all entities share {P,V,Payload}
        for k in range(len(order)):
            s1 += view.get_a(order[k]).p[0]
    keep(Int(s1))
    table.add("archetype (soa)", n, "sum-pos.x", now() - t1, n * frames)

    # Sparse — Position lives in its own dense store (~32 KB); Payload store
    # untouched.
    var wsp = World[SparseSetBackend[Pos2, Vel2, Payload]]()
    for i in range(n):
        var e = wsp.spawn2(Pos2(Vec2(Real(i), 0)), Vel2(Vec2(1, 1)))
        wsp.set(e, Payload(_zeros()))
    var es = wsp.query1[Pos2]()
    var s2 = Real(0)
    var t2 = now()
    for _ in range(frames):
        for k in range(len(order)):
            s2 += wsp.get[Pos2](es[order[k]]).p[0]
    keep(Int(s2))
    table.add("sparse", n, "sum-pos.x", now() - t2, n * frames)


# ========================== W3 — SIMD integrate =============================


def w3_simd(mut table: BenchTable, n: Int, frames: Int):
    var dt = Real(1)

    # OOP scalar per-object
    var scene = Scene()
    for i in range(n):
        _ = scene.spawn(Vec2(Real(i), 0), Vec2(1, 1), Vec2(0.5, 0.5))
    var t0 = now()
    for _ in range(frames):
        scene.step(dt)
    keep(Int(scene.sum_x()))
    table.add("oop (scalar)", n, "integrate", now() - t0, n * frames)

    # Archetype scalar SoA
    var ws = World[ArchetypeBackend[Pos2, Vel2]]()
    for i in range(n):
        _ = ws.spawn2(Pos2(Vec2(Real(i), 0)), Vel2(Vec2(1, 1)))
    var t1 = now()
    for _ in range(frames):
        var views = ws.backend.query2_views[Pos2, Vel2]()
        for vi in range(len(views)):
            var view = views[vi]
            for i in range(view.len()):
                view.set_a(i, Pos2(view.get_a(i).p + view.get_b(i).v * dt))
    keep(0)
    table.add("archetype (soa)", n, "integrate", now() - t1, n * frames)

    # Archetype SIMD column integrator (engine API)
    var wm = World[ArchetypeBackend[Pos2, Vel2]]()
    for i in range(n):
        _ = wm.spawn2(Pos2(Vec2(Real(i), 0)), Vel2(Vec2(1, 1)))
    var t2 = now()
    for _ in range(frames):
        integrate2_simd[Pos2, Vel2](wm.backend, dt)
    keep(0)
    table.add("archetype (simd)", n, "integrate", now() - t2, n * frames)


# ========================= W4 — structural churn ============================


def w4_churn(mut table: BenchTable, n: Int, frames: Int):
    # Archetype — add/remove forces archetype relocation (column copy + swap)
    var wa = World[ArchetypeBackend[Pos2, Tag]]()
    var ea = List[Entity]()
    for i in range(n):
        ea.append(wa.spawn1(Pos2(Vec2(Real(i), 0))))
    var t0 = now()
    for f in range(frames):
        for k in range(len(ea)):
            if f % 2 == 0:
                wa.set(ea[k], Tag(1))
            else:
                wa.remove[Tag](ea[k])
    table.add("archetype", n, "add/remove", now() - t0, n * frames)

    # Sparse — add/remove is in-place in the component's sparse set
    var wsp = World[SparseSetBackend[Pos2, Tag]]()
    var es = List[Entity]()
    for i in range(n):
        es.append(wsp.spawn1(Pos2(Vec2(Real(i), 0))))
    var t1 = now()
    for f in range(frames):
        for k in range(len(es)):
            if f % 2 == 0:
                wsp.set(es[k], Tag(1))
            else:
                wsp.remove[Tag](es[k])
    table.add("sparse", n, "add/remove", now() - t1, n * frames)

    # OOP — "adding/removing a behavior" is just toggling a field (no relocation)
    var scene = Scene()
    for i in range(n):
        _ = scene.spawn(Vec2(Real(i), 0), Vec2(1, 1), Vec2(0.5, 0.5))
    var t2 = now()
    var toggled = 0
    for f in range(frames):
        for k in range(len(scene.objects)):
            scene.objects[k].alive = (f % 2 == 0)
            toggled += 1
    keep(toggled)
    table.add("oop (flag)", n, "add/remove", now() - t2, n * frames)


def main() raises:
    var t1 = BenchTable("W1 — slim full-update (touch P+V, 16B components)")
    w1_slim_update(t1, 4000, 30)
    t1.print_report()

    var t2 = BenchTable(
        "W2 — scattered selective-read (sum Position.x; ~2KB cold payload, random order)"
    )
    w2_fat_selective(t2, 4000, 30)
    t2.print_report()

    var t3 = BenchTable("W3 — SIMD integrate (column-wise pos += vel*dt)")
    w3_simd(t3, 4000, 30)
    t3.print_report()

    var t4 = BenchTable("W4 — structural churn (add/remove a component per frame)")
    w4_churn(t4, 2000, 20)
    t4.print_report()
