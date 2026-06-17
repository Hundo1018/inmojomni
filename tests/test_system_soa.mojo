"""The fast paths must equal the ergonomic path: running the same movement via
the handle path (query2 + get/set), the scalar SoA path (query2_views), and the
SIMD path (integrate2_simd) over identical initial state must agree."""

from harness.runner import Suite
from geometry.vec import Vec2, Real
from ecs.world import World
from ecs.archetype import ArchetypeBackend
from ecs.system import integrate2_simd
from ecs.component import ComponentType


@fieldwise_init
struct Pos2(ComponentType):
    comptime ID: Int = 0
    var p: Vec2


@fieldwise_init
struct Vel2(ComponentType):
    comptime ID: Int = 1
    var v: Vec2


comptime Backend = ArchetypeBackend[Pos2, Vel2]


def _seed(mut w: World[Backend], n: Int):
    for i in range(n):
        _ = w.spawn2(Pos2(Vec2(Real(i), Real(2 * i))), Vel2(Vec2(1, -1)))


def _sum_pos(mut w: World[Backend]) -> Float64:
    var s = Float64(0)
    var es = w.query1[Pos2]()
    for i in range(len(es)):
        var p = w.get[Pos2](es[i]).p
        s += Float64(p[0]) + Float64(p[1])
    return s


def main() raises:
    var s = Suite("system_soa")
    comptime N = 200
    var dt = Real(0.5)
    var frames = 5

    # Path A — handle path (query2 + get/set).
    var wa = World[Backend]()
    _seed(wa, N)
    for _ in range(frames):
        var es = wa.query2[Pos2, Vel2]()
        for i in range(len(es)):
            var e = es[i]
            var p = wa.get[Pos2](e)
            var v = wa.get[Vel2](e)
            wa.set(e, Pos2(p.p + v.v * dt))

    # Path B — scalar SoA via column views.
    var wb = World[Backend]()
    _seed(wb, N)
    for _ in range(frames):
        var views = wb.backend.query2_views[Pos2, Vel2]()
        for vi in range(len(views)):
            var view = views[vi]
            for i in range(view.len()):
                var p = view.get_a(i)
                var v = view.get_b(i)
                view.set_a(i, Pos2(p.p + v.v * dt))

    # Path C — SIMD column integrator (engine API).
    var wc = World[Backend]()
    _seed(wc, N)
    for _ in range(frames):
        integrate2_simd[Pos2, Vel2](wc.backend, dt)

    var sa = _sum_pos(wa)
    var sb = _sum_pos(wb)
    var sc = _sum_pos(wc)

    # Analytic check: sum over i of (i+2.5) + (2i-2.5) = sum of 3i = 3*sum(i).
    var expected = Float64(0)
    for i in range(N):
        expected += (Float64(i) + 2.5) + (2.0 * Float64(i) - 2.5)

    s.almost(sa, expected, "handle path correct", 1e-2)
    s.almost(sb, sa, "scalar SoA == handle", 1e-2)
    s.almost(sc, sa, "SIMD == handle", 1e-2)

    s.finish()
