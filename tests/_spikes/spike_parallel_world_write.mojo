# Spike 4 (real engine): can a `parallelize` worker capture a `mut World` and
# write disjoint entities concurrently? Each worker `i` overwrites ONLY entity
# i's already-present Health (in-place dense-slot write, no structural change),
# so the writes hit disjoint memory and parallel must equal serial.
# If this holds, the entity-actor scheduler needs no command buffer for the
# common "actor mutates only itself" case.

from std.algorithm import parallelize
from ecs.world import World
from ecs.sparse_backend import SparseSetBackend
from ecs.component import ComponentType
from ecs.entity import Entity


@fieldwise_init
struct Health(ComponentType):
    comptime ID: Int = 0
    var hp: Int


def main() raises:
    comptime N = 200
    var w = World[SparseSetBackend[Health]]()
    var ents = List[Entity]()
    for i in range(N):
        var e = w.spawn()
        w.set(e, Health(0))  # component pre-exists -> later set() is in-place
        ents.append(e)

    @parameter
    def worker(i: Int):
        w.set(ents[i], Health(i * 2))  # disjoint: worker i touches only entity i

    parallelize[worker](N)

    var bad = 0
    for i in range(N):
        if w.get[Health](ents[i]).hp != i * 2:
            bad += 1
    if bad != 0:
        raise Error("FAIL: " + String(bad) + " mismatches")
    print("spike_parallel_world_write: PASS all", N, "disjoint writes correct")
