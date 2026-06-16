"""Semi-implicit Euler integrator, verified on both ECS backends."""

from harness.runner import Suite
from geometry.vec import Vec2
from ecs.world import World
from ecs.storage import StorageBackend
from ecs.sparse_backend import SparseSetBackend
from ecs.archetype import ArchetypeBackend
from physics.body import Body2
from physics.integrator import integrate


# returns (x, y) of the body after `steps` of gravity, run on backend B
def _final_pos[B: StorageBackend](steps: Int) raises -> Vec2:
    var w = World[B]()
    var e = w.spawn1(Body2(Vec2(0, 0), Vec2(1, 0)))
    for _ in range(steps):
        integrate[B, Body2](w, 1.0, Vec2(0, -10))
    return w.get[Body2](e).position()


def main() raises:
    var s = Suite("physis")

    # one step of semi-implicit Euler: v += g*dt = (1,-10); p += v*dt = (1,-10)
    var p1 = _final_pos[SparseSetBackend[Body2]](1)
    s.almost(Float64(p1[0]), 1.0, "x after 1 step")
    s.almost(Float64(p1[1]), -10.0, "y after 1 step")

    # two steps: v=(1,-20), p=(1,-10)+(1,-20)=(2,-30)
    var p2 = _final_pos[SparseSetBackend[Body2]](2)
    s.almost(Float64(p2[0]), 2.0, "x after 2 steps")
    s.almost(Float64(p2[1]), -30.0, "y after 2 steps")

    # archetype backend integrates identically
    var a2 = _final_pos[ArchetypeBackend[Body2]](2)
    s.almost(Float64(a2[0]), 2.0, "archetype x parity")
    s.almost(Float64(a2[1]), -30.0, "archetype y parity")

    s.finish()
