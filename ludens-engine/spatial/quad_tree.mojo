"""QuadTree — the 2D specialisation of the loose region tree.

    var qt = QuadTree(AABB2(Vec2(0,0), Vec2(100,100)))
    qt.insert(proxy_id, box2)
    qt.query_region(region2, out_proxies)
"""

from .tree_core import LooseTree

comptime QuadTree = LooseTree[2]
