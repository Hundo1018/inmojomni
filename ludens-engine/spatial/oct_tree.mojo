"""Octree — the 3D specialisation of the loose region tree (8 children).

    var ot = Octree(AABB3(Vec3(0,0,0), Vec3(100,100,100)))
    ot.insert(proxy_id, box3)
    ot.query_region(region3, out_proxies)
"""

from .tree_core import LooseTree

comptime Octree = LooseTree[3]
