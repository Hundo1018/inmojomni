"""Example 03 — swap the broadphase with zero scene-code changes.

`demo` is generic over `BP: BroadPhase`. The same scene of boxes is fed to brute
force, a quadtree and a spatial hash grid; all report the same overlapping pairs.
Run:

    pixi run mojo run -I build examples/03_broadphase_swap.mojo
"""

from geometry.vec import Vec2
from geometry.aabb import AABB2
from collision.broadphase import BroadPhase, BruteForce, Pair, BoxProxy
from collision.bp_tree import QuadTreeBroadPhase
from collision.bp_hashgrid import SpatialHashBroadPhase


def _box(p: Int, x0: Float32, y0: Float32, x1: Float32, y1: Float32) -> BoxProxy[2]:
    return BoxProxy[2](p, AABB2(Vec2(x0, y0), Vec2(x1, y1)))


def scene() -> List[BoxProxy[2]]:
    var items = List[BoxProxy[2]]()
    items.append(_box(0, 0, 0, 2, 2))
    items.append(_box(1, 1, 1, 3, 3))  # overlaps 0
    items.append(_box(2, 1.5, 1.5, 2.5, 2.5))  # overlaps 0 and 1
    items.append(_box(3, 40, 40, 42, 42))
    items.append(_box(4, 41, 41, 43, 43))  # overlaps 3
    return items^


def demo[BP: BroadPhase](mut bp: BP, items: List[BoxProxy[BP.dim]], label: String) raises:
    bp.rebuild(items)
    var prs = List[Pair]()
    bp.pairs(prs)
    print(label, "-> candidate pairs:", len(prs))


def main() raises:
    print("Same scene, three broadphases (all should find 4 pairs):")
    var bf = BruteForce[2]()
    demo(bf, scene(), "brute force ")
    var qt = QuadTreeBroadPhase(AABB2(Vec2(0, 0), Vec2(100, 100)), capacity=2, max_depth=5)
    demo(qt, scene(), "quadtree    ")
    var hg = SpatialHashBroadPhase[2](5.0)
    demo(hg, scene(), "spatial hash")
