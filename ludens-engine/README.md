# ludens-engine

A small, **test-driven**, modular ECS game-engine core written in Mojo nightly.
Everything that can be swapped is swapped behind a trait and chosen at
compile time, so you can teach/compare alternative implementations with identical
game code.

## What's inside

| Subsystem | Swappable behind | Implementations |
|---|---|---|
| ECS storage | `StorageBackend` | `SparseSetBackend` (EnTT-style), `ArchetypeBackend` (flecs/“ECS storage in pictures”) |
| Broadphase | `BroadPhase` | `BruteForce`, `QuadTree`(2D)/`Octree`(3D), `SpatialHashGrid`, `BVH` |
| Narrowphase | `NarrowPhase` | `AABB`, `Circle`, `SAT` (polygons), `GJK` (convex, 2D+3D) |
| Physics body | `PhysicsBody` | `Body2` (semi-implicit Euler) |

Geometry (`geometry/`) is dimension-generic: `Vec2`/`Vec3`, `AABB[dim]`, and
width-generic vector math. Spatial structures (`spatial/`) share one
`LooseTree[dim]` core (quadtree = dim 2, octree = dim 3).

## Swapping is the whole point

```mojo
# identical game code, two storage strategies:
var w = World[SparseSetBackend[Position, Velocity]]()
var w = World[ArchetypeBackend[Position, Velocity]]()

# identical scene, any acceleration structure:
var pipe = CollisionPipeline(QuadTreeBroadPhase(bounds), AABBNarrowPhase[2]())
var pipe = CollisionPipeline(BruteForce[2](),            SATNarrowPhase())
```

Two contract tests prove the swaps are observationally identical:
`tests/test_backend_parity.mojo` (ECS backends) and `tests/test_broadphase.mojo`
(all broadphases find the same overlap pairs).

## Package layout

```
ludens-engine/
  harness/    Suite test harness (no `mojo test` in this nightly)
  geometry/   vec, aabb, shape, sat, gjk, bvh
  spatial/    tree_core, quad_tree, oct_tree, hash_grid
  ecs/        component, entity, sparse_set, storage, sparse_backend,
              column/archetype, world, query
  collision/  broadphase (+ bp_tree/bp_hashgrid/bp_bvh), narrowphase, pipeline
  physics/    body, integrator
examples/     01..05 runnable demos
tests/        test_*.mojo (one per module) + _spikes/ (nightly-quirk probes)
```

## Build, test, run

This nightly resolves cross-file imports only through **precompiled** `.mojoc`
packages, so build first (the pixi tasks do this for you):

```sh
pixi run build      # precompile every package into build/
pixi run test       # build + run all tests (171 checks)
pixi run examples   # build + run all example programs
```

Run one thing directly after `pixi run build`:

```sh
pixi run mojo run -I build tests/test_query.mojo
pixi run mojo run -I build examples/02_swap_storage.mojo
```

## Defining a component

```mojo
@fieldwise_init
struct Position(ComponentType):
    comptime ID: Int = 0   # unique, dense from 0 within a world
    var x: Float64
    var y: Float64
```
