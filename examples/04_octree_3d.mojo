"""Example 04 — a 3D octree region query.

Populate an octree with axis-aligned boxes and query a sub-volume. Run:

    pixi run mojo run -I build examples/04_octree_3d.mojo
"""

from geometry.vec import Vec3
from geometry.aabb import AABB3
from spatial.oct_tree import Octree


def _box(p: Int, c: Float32) -> AABB3:
    return AABB3(Vec3(c - 1, c - 1, c - 1), Vec3(c + 1, c + 1, c + 1))


def main():
    var ot = Octree(AABB3(Vec3(0, 0, 0), Vec3(64, 64, 64)), capacity=2, max_depth=5)
    for i in range(8):
        ot.insert(i, _box(i, Float32(i) * 8 + 2))  # spread along the diagonal

    print("octree nodes:", ot.node_count())

    var near = List[Int]()
    ot.query_region(AABB3(Vec3(0, 0, 0), Vec3(20, 20, 20)), near)
    print("proxies in the [0,20]^3 corner:", len(near))
    for i in range(len(near)):
        print("  proxy", near[i])
