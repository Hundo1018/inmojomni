"""Collision benchmark: broadphase x scene, and narrowphase x scene cross matrices.

Two comparisons on randomly-generated box scenes:

  * Broadphase — feed the same N boxes to every acceleration structure
    (brute force / quadtree|octree / spatial hash / BVH) and time
    rebuild + candidate-pair generation. Run in 2D and 3D.
  * Narrowphase — take one scene's broadphase candidate pairs and run each exact
    test (AABB / circle / SAT / OBB / GJK+EPA / SDF) over them, timing per pair.

Each box becomes the equivalent shape per narrowphase (circle = bounding circle,
etc.), so hit counts vary slightly; the metric of interest is per-pair cost.
Run with: `mojo run -I build benchmarks/bench_collision.mojo`.
"""

from std.benchmark import keep
from geometry.vec import Vec2, Vec3, Real
from geometry.aabb import AABB, AABB2, AABB3
from geometry.shape import Circle, Polygon
from geometry.gjk import ConvexPoly
from geometry.obb import OBB
from geometry.sdf import SdfShape
from collision.broadphase import BroadPhase, BruteForce, Pair, BoxProxy
from collision.bp_tree import QuadTreeBroadPhase, OctreeBroadPhase
from collision.bp_hashgrid import SpatialHashBroadPhase
from collision.bp_bvh import BVHBroadPhase
from collision.narrowphase import (
    NarrowPhase,
    AABBNarrowPhase,
    CircleNarrowPhase,
    SATNarrowPhase,
    OBBNarrowPhase,
    GJKNarrowPhase,
    SDFNarrowPhase,
)
from harness.bench import BenchTable, now


struct Rng(Movable):
    """A tiny LCG so scenes are deterministic across backends."""

    var state: UInt64

    def __init__(out self, seed: UInt64):
        self.state = seed

    def next_f(mut self) -> Real:
        self.state = self.state * 6364136223846793005 + 1442695040888963407
        return Real(Float64((self.state >> 16) % 1_000_000) / 1_000_000.0)


# --- scene generation --------------------------------------------------------


def scene2(n: Int, extent: Real, half: Real) -> List[BoxProxy[2]]:
    var rng = Rng(0x1234)
    var items = List[BoxProxy[2]]()
    for i in range(n):
        var cx = rng.next_f() * extent
        var cy = rng.next_f() * extent
        var lo = Vec2(cx - half, cy - half)
        var hi = Vec2(cx + half, cy + half)
        items.append(BoxProxy[2](i, AABB2(lo, hi)))
    return items^


def scene3(n: Int, extent: Real, half: Real) -> List[BoxProxy[3]]:
    var rng = Rng(0x1234)
    var items = List[BoxProxy[3]]()
    for i in range(n):
        var cx = rng.next_f() * extent
        var cy = rng.next_f() * extent
        var cz = rng.next_f() * extent
        var lo = Vec3(cx - half, cy - half, cz - half)
        var hi = Vec3(cx + half, cy + half, cz + half)
        items.append(BoxProxy[3](i, AABB3(lo, hi)))
    return items^


# --- broadphase --------------------------------------------------------------


def run_bp[
    BP: BroadPhase
](
    mut table: BenchTable,
    variant: String,
    mut bp: BP,
    items: List[BoxProxy[BP.dim]],
    n: Int,
) raises:
    var t0 = now()
    bp.rebuild(items)
    var prs = List[Pair]()
    bp.pairs(prs)
    var t1 = now()
    keep(len(prs))
    table.add(variant + " P=" + String(len(prs)), n, "rebuild+pairs", t1 - t0, n)


def bench_broadphase_2d(mut table: BenchTable, n: Int) raises:
    var extent = Real(Float64(n) ** 0.5) * 4.0  # keep density roughly constant
    var items = scene2(n, extent, 1.0)
    var bf = BruteForce[2]()
    run_bp(table, "2d brute", bf, items, n)
    var qt = QuadTreeBroadPhase(
        AABB2(Vec2(-1, -1), Vec2(extent + 1, extent + 1)), capacity=8, max_depth=8
    )
    run_bp(table, "2d quadtree", qt, items, n)
    var hg = SpatialHashBroadPhase[2](4.0)
    run_bp(table, "2d hashgrid", hg, items, n)
    var bvh = BVHBroadPhase[2]()
    run_bp(table, "2d bvh", bvh, items, n)


def bench_broadphase_3d(mut table: BenchTable, n: Int) raises:
    var extent = Real(Float64(n) ** (1.0 / 3.0)) * 4.0
    var items = scene3(n, extent, 1.0)
    var bf = BruteForce[3]()
    run_bp(table, "3d brute", bf, items, n)
    var oc = OctreeBroadPhase(
        AABB3(Vec3(-1, -1, -1), Vec3(extent + 1, extent + 1, extent + 1)),
        capacity=8,
        max_depth=8,
    )
    run_bp(table, "3d octree", oc, items, n)
    var hg = SpatialHashBroadPhase[3](4.0)
    run_bp(table, "3d hashgrid", hg, items, n)
    var bvh = BVHBroadPhase[3]()
    run_bp(table, "3d bvh", bvh, items, n)


# --- narrowphase -------------------------------------------------------------


def run_np[
    NP: NarrowPhase
](mut table: BenchTable, variant: String, np: NP, pairs: List[Pair], n: Int):
    var hits = 0
    var t0 = now()
    for k in range(len(pairs)):
        if np.test(pairs[k].a, pairs[k].b).hit:
            hits += 1
    keep(hits)
    var t1 = now()
    table.add(variant + " hits=" + String(hits), n, "narrow test", t1 - t0, len(pairs))


def bench_narrowphase(mut table: BenchTable, n: Int) raises:
    var extent = Real(Float64(n) ** 0.5) * 3.0
    var items = scene2(n, extent, 1.0)

    # Candidate pairs (shared by every narrowphase) from a brute-force broadphase.
    var bf = BruteForce[2]()
    bf.rebuild(items)
    var pairs = List[Pair]()
    bf.pairs(pairs)

    # Build each narrowphase with the equivalent shape per proxy (in proxy order).
    var npa = AABBNarrowPhase[2]()
    var npc = CircleNarrowPhase()
    var nps = SATNarrowPhase()
    var npo = OBBNarrowPhase()
    var npg = GJKNarrowPhase[2]()
    var npd = SDFNarrowPhase()
    for i in range(n):
        var b = items[i].box
        var c = b.center()
        var h = b.half_extents()
        _ = npa.add(b)
        _ = npc.add(Circle(c, h[0]))
        _ = nps.add(Polygon.box(c[0], c[1], h[0], h[1]))
        _ = npo.add(OBB(c, h, 0))
        var cp = ConvexPoly[2]()
        cp.add(Vec2(c[0] - h[0], c[1] - h[1]))
        cp.add(Vec2(c[0] + h[0], c[1] - h[1]))
        cp.add(Vec2(c[0] + h[0], c[1] + h[1]))
        cp.add(Vec2(c[0] - h[0], c[1] + h[1]))
        _ = npg.add(cp^)
        _ = npd.add(SdfShape.box(c, h))

    run_np(table, "aabb", npa, pairs, n)
    run_np(table, "circle", npc, pairs, n)
    run_np(table, "sat", nps, pairs, n)
    run_np(table, "obb", npo, pairs, n)
    run_np(table, "gjk+epa", npg, pairs, n)
    run_np(table, "sdf", npd, pairs, n)


def main() raises:
    var bp_table = BenchTable("Broadphase x scene (rebuild + candidate pairs)")
    bench_broadphase_2d(bp_table, 1_000)
    bench_broadphase_2d(bp_table, 4_000)
    bench_broadphase_2d(bp_table, 8_000)
    bench_broadphase_3d(bp_table, 1_000)
    bench_broadphase_3d(bp_table, 4_000)
    bp_table.print_report()

    var np_table = BenchTable("Narrowphase x scene (per-pair exact test)")
    bench_narrowphase(np_table, 500)
    bench_narrowphase(np_table, 2_000)
    np_table.print_report()
