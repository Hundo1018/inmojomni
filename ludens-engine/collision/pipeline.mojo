"""The collision pipeline: broadphase candidate pairs -> narrowphase contacts.

`CollisionPipeline[BP, NP]` is fully generic over the broadphase and narrowphase
types, so any combination plugs in:

    var pipe = CollisionPipeline(QuadTreeBroadPhase(bounds), AABBNarrowPhase[2]())
    var manifolds = pipe.step(boxes)   # only the truly-touching pairs

Both `BP` and `NP` must share the same dimension.
"""

from .broadphase import BroadPhase, Pair, BoxProxy
from .narrowphase import NarrowPhase, Contact


@fieldwise_init
struct Manifold[dim: Int](Copyable, ImplicitlyCopyable, Movable):
    var a: Int
    var b: Int
    var contact: Contact[Self.dim]


struct CollisionPipeline[BP: BroadPhase, NP: NarrowPhase](Movable, ImplicitlyDeletable):
    var broad: Self.BP
    var narrow: Self.NP

    def __init__(out self, var broad: Self.BP, var narrow: Self.NP):
        self.broad = broad^
        self.narrow = narrow^

    def step(
        mut self, items: List[BoxProxy[Self.BP.dim]]
    ) raises -> List[Manifold[Self.NP.dim]]:
        self.broad.rebuild(items)
        var prs = List[Pair]()
        self.broad.pairs(prs)
        var out = List[Manifold[Self.NP.dim]]()
        for i in range(len(prs)):
            var c = self.narrow.test(prs[i].a, prs[i].b)
            if c.hit:
                out.append(Manifold[Self.NP.dim](prs[i].a, prs[i].b, c))
        return out^
