"""Cross-paradigm parity: the OOP engine and an ECS world, run on the same
movement workload, must agree on entity counts and aggregate positions."""

from harness.runner import Suite
from geometry.vec import Vec2, Real
from ecs.world import World
from ecs.sparse_backend import SparseSetBackend
from ecs.component import ComponentType
from oop.engine import Scene


@fieldwise_init
struct Pos2(ComponentType):
    comptime ID: Int = 0
    var p: Vec2


@fieldwise_init
struct Vel2(ComponentType):
    comptime ID: Int = 1
    var v: Vec2


def main() raises:
    var s = Suite("oop_engine")
    comptime N = 50
    var dt = Real(1)
    var frames = 8

    var w = World[SparseSetBackend[Pos2, Vel2]]()
    var scene = Scene()
    for i in range(N):
        var pos = Vec2(Real(i), 0)
        var vel = Vec2(1, 0)
        _ = w.spawn2(Pos2(pos), Vel2(vel))
        _ = scene.spawn(pos, vel, Vec2(0.5, 0.5))

    s.eqi(scene.count(), w.entity_count(), "same entity count at start")

    # Run identical movement loops in both paradigms.
    for _ in range(frames):
        var movers = w.query2[Pos2, Vel2]()
        for i in range(len(movers)):
            var e = movers[i]
            var p = w.get[Pos2](e)
            var v = w.get[Vel2](e)
            w.set(e, Pos2(p.p + v.v * dt))
        scene.step(dt)

    var ecs_sum = Real(0)
    var all = w.query1[Pos2]()
    for i in range(len(all)):
        ecs_sum += w.get[Pos2](all[i]).p[0]
    s.almost(Float64(scene.sum_x()), Float64(ecs_sum), "aggregate x matches", 1e-3)

    # Despawn / kill the same entity index in both; counts stay in lockstep.
    var victims = w.query1[Pos2]()
    w.despawn(victims[0])
    scene.kill(0)
    s.eqi(scene.count(), w.entity_count(), "same count after removal")

    # The OOP collision baseline runs (overlapping unit boxes at integer x).
    s.check(scene.collide_pairs() >= 0, "collision pass executes")

    s.finish()
