"""Entity handle: a small value identifying an entity.

`id` indexes the storage (and is the key into the sparse sets); `gen`
(generation) is bumped when an id is recycled, so a stale `Entity` copy can be
detected as dead even after its id is reused.
"""


@fieldwise_init
struct Entity(Copyable, ImplicitlyCopyable, Movable, Writable):
    var id: Int
    var gen: Int

    def __eq__(self, other: Self) -> Bool:
        return self.id == other.id and self.gen == other.gen

    def __ne__(self, other: Self) -> Bool:
        return not (self == other)

    def write_to[W: Writer](self, mut w: W):
        w.write("Entity(", self.id, ",", self.gen, ")")
