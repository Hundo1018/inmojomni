"""The full pipeline returns the same contacts regardless of which broadphase
feeds the (AABB) narrowphase."""

from harness.runner import Suite
from geometry.vec import Vec2
from geometry.aabb import AABB2
from collision.broadphase import BruteForce, BoxProxy
from collision.bp_tree import QuadTreeBroadPhase
from collision.bp_hashgrid import SpatialHashBroadPhase
from collision.narrowphase import AABBNarrowPhase
from collision.pipeline import CollisionPipeline, Manifold


def _box(p: Int, x0: Float32, y0: Float32, x1: Float32, y1: Float32) -> BoxProxy[2]:
    return BoxProxy[2](p, AABB2(Vec2(x0, y0), Vec2(x1, y1)))


def _aabbs() -> AABBNarrowPhase[2]:
    # narrowphase shapes are the same boxes, added in proxy order 0..3
    var np = AABBNarrowPhase[2]()
    _ = np.add(AABB2(Vec2(0, 0), Vec2(2, 2)))
    _ = np.add(AABB2(Vec2(1, 1), Vec2(3, 3)))
    _ = np.add(AABB2(Vec2(20, 20), Vec2(22, 22)))
    _ = np.add(AABB2(Vec2(21, 21), Vec2(23, 23)))
    return np^


def _keys(manifolds: List[Manifold[2]]) -> List[Int]:
    var keys = List[Int]()
    for i in range(len(manifolds)):
        var a = manifolds[i].a
        var b = manifolds[i].b
        if a > b:
            a, b = b, a
        keys.append(a * 1000 + b)
    # tiny insertion sort
    for i in range(1, len(keys)):
        var k = keys[i]
        var j = i - 1
        while j >= 0 and keys[j] > k:
            keys[j + 1] = keys[j]
            j -= 1
        keys[j + 1] = k
    return keys^


def _same(a: List[Int], b: List[Int]) -> Bool:
    if len(a) != len(b):
        return False
    for i in range(len(a)):
        if a[i] != b[i]:
            return False
    return True


def main() raises:
    var s = Suite("pipeline")

    var items = List[BoxProxy[2]]()
    items.append(_box(0, 0, 0, 2, 2))
    items.append(_box(1, 1, 1, 3, 3))  # overlaps 0
    items.append(_box(2, 20, 20, 22, 22))
    items.append(_box(3, 21, 21, 23, 23))  # overlaps 2

    var bounds = AABB2(Vec2(0, 0), Vec2(100, 100))

    var pipe_bf = CollisionPipeline(BruteForce[2](), _aabbs())
    var m_bf = pipe_bf.step(items)
    s.eqi(len(m_bf), 2, "brute pipeline finds 2 contacts")

    var pipe_qt = CollisionPipeline(QuadTreeBroadPhase(bounds, capacity=1, max_depth=5), _aabbs())
    var m_qt = pipe_qt.step(items)

    var pipe_hg = CollisionPipeline(SpatialHashBroadPhase[2](4.0), _aabbs())
    var m_hg = pipe_hg.step(items)

    s.check(_same(_keys(m_qt), _keys(m_bf)), "quadtree pipeline == brute pipeline")
    s.check(_same(_keys(m_hg), _keys(m_bf)), "hashgrid pipeline == brute pipeline")

    # the contacts are the expected pairs (0,1) and (2,3)
    var k = _keys(m_bf)
    s.eqi(k[0], 0 * 1000 + 1, "contact (0,1)")
    s.eqi(k[1], 2 * 1000 + 3, "contact (2,3)")

    s.finish()
