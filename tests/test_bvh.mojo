from harness.runner import Suite
from geometry.vec import Vec2
from geometry.aabb import AABB2
from geometry.bvh import BVH, _Leaf


def _contains(items: List[Int], v: Int) -> Bool:
    for i in range(len(items)):
        if items[i] == v:
            return True
    return False


def main() raises:
    var s = Suite("bvh")

    var leaves = List[_Leaf[2]]()
    # a grid of unit boxes with proxy ids 0..3
    leaves.append(_Leaf[2](AABB2(Vec2(0, 0), Vec2(1, 1)), 0))
    leaves.append(_Leaf[2](AABB2(Vec2(5, 0), Vec2(6, 1)), 1))
    leaves.append(_Leaf[2](AABB2(Vec2(0, 5), Vec2(1, 6)), 2))
    leaves.append(_Leaf[2](AABB2(Vec2(5, 5), Vec2(6, 6)), 3))

    var bvh = BVH[2]()
    bvh.build(leaves^)

    var hits = List[Int]()
    bvh.query_region(AABB2(Vec2(-0.5, -0.5), Vec2(0.5, 0.5)), hits)
    s.eqi(len(hits), 1, "region near origin -> 1 proxy")
    s.check(_contains(hits, 0), "proxy 0 found")

    var all = List[Int]()
    bvh.query_region(AABB2(Vec2(-1, -1), Vec2(7, 7)), all)
    s.eqi(len(all), 4, "full region -> all 4")

    var none = List[Int]()
    bvh.query_region(AABB2(Vec2(100, 100), Vec2(101, 101)), none)
    s.eqi(len(none), 0, "far region -> none")

    var corner = List[Int]()
    bvh.query_region(AABB2(Vec2(4, 4), Vec2(10, 10)), corner)
    s.eqi(len(corner), 1, "top-right region -> proxy 3")
    s.check(_contains(corner, 3), "proxy 3 found")

    s.finish()
