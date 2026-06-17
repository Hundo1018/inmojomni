"""A plain object-oriented game engine — the non-ECS baseline.

This is the classic "list of game objects, each updating itself" model: every
`GameObject` owns its own data *and* behavior (position, velocity, a collider,
an `update` method), and a `Scene` holds them array-of-structs and drives them by
iterating and calling `update`. There is no separation of data and logic, no
component storage, no archetypes — the deliberate contrast with the ECS backends.

The workload (`step`: integrate position by velocity; `collide_pairs`: brute-force
AABB overlaps) mirrors the ECS movement system and the brute-force broadphase so
the two paradigms can be benchmarked on identical scenes. Math reuses
`geometry.vec` (never SIMD `reduce_*`, which is broken on width 3 in this
nightly).
"""

from geometry.vec import WorldType, Real, Vec2


@fieldwise_init
struct GameObject(Copyable, ImplicitlyCopyable, Movable):
    """A self-contained game object: its own data and its own update logic."""

    var pos: Vec2
    var vel: Vec2
    var half: Vec2  # AABB half-extents for collision
    var alive: Bool

    def update(mut self, dt: Real):
        """Integrate one step — the object advances itself (OOP, not a system)."""
        self.pos = self.pos + self.vel * dt

    def overlaps(self, other: Self) -> Bool:
        """Axis-aligned overlap of this object's box with another's."""
        if abs(self.pos[0] - other.pos[0]) > self.half[0] + other.half[0]:
            return False
        if abs(self.pos[1] - other.pos[1]) > self.half[1] + other.half[1]:
            return False
        return True


struct Scene(Movable, ImplicitlyDeletable):
    """Owns the game objects and drives the per-frame update loop."""

    var objects: List[GameObject]

    def __init__(out self):
        self.objects = List[GameObject]()

    def spawn(mut self, pos: Vec2, vel: Vec2, half: Vec2) -> Int:
        self.objects.append(GameObject(pos, vel, half, True))
        return len(self.objects) - 1

    def count(self) -> Int:
        var n = 0
        for ref o in self.objects:
            if o.alive:
                n += 1
        return n

    def kill(mut self, i: Int):
        self.objects[i].alive = False

    def step(mut self, dt: Real):
        """Advance every live object by calling its own `update`."""
        for ref o in self.objects:
            if o.alive:
                o.update(dt)

    def sum_x(self) -> Real:
        var s = Real(0)
        for ref o in self.objects:
            if o.alive:
                s += o.pos[0]
        return s

    def collide_pairs(self) -> Int:
        """Brute-force O(n^2) AABB overlap count — the OOP collision baseline."""
        var hits = 0
        var n = len(self.objects)
        for i in range(n):
            if not self.objects[i].alive:
                continue
            for j in range(i + 1, n):
                if self.objects[j].alive and self.objects[i].overlaps(
                    self.objects[j]
                ):
                    hits += 1
        return hits


comptime PAYLOAD_WORDS = 256  # 256 * 8 bytes = ~2 KB cold payload per object


@fieldwise_init
struct FatObject(Copyable, ImplicitlyCopyable, Movable):
    """A game object with a large cold payload inlined alongside its hot data.

    This is the canonical AoS cache-pressure case: a system that only touches
    `pos`/`vel` still strides over the whole ~528-byte object, dragging the cold
    `payload` through cache on every element. The ECS equivalent keeps `payload`
    in its own column, so a Position+Velocity system never loads it."""

    var pos: Vec2
    var vel: Vec2
    var payload: InlineArray[Int, PAYLOAD_WORDS]  # cold data, never read in the loop
    var alive: Bool

    def update(mut self, dt: Real):
        self.pos = self.pos + self.vel * dt


struct FatScene(Movable, ImplicitlyDeletable):
    """Array-of-structs scene of fat objects (the cache-unfriendly baseline)."""

    var objects: List[FatObject]

    def __init__(out self):
        self.objects = List[FatObject]()

    def spawn(mut self, pos: Vec2, vel: Vec2) -> Int:
        self.objects.append(
            FatObject(pos, vel, InlineArray[Int, PAYLOAD_WORDS](fill=1), True)
        )
        return len(self.objects) - 1

    def step(mut self, dt: Real):
        for ref o in self.objects:
            if o.alive:
                o.update(dt)

    def sum_pos_x(self) -> Real:
        """Selective read — touches only `pos`, but strides over fat objects."""
        var s = Real(0)
        for ref o in self.objects:
            s += o.pos[0]
        return s

    def sum_pos_x_order(self, order: List[Int]) -> Real:
        """Scattered selective read in `order` — defeats the prefetcher, so each
        access pays a cache miss into the fat object array."""
        var s = Real(0)
        for k in range(len(order)):
            s += self.objects[order[k]].pos[0]
        return s
