# Spike A (final): heterogeneous component storage.
# One fully-typed ComponentStore[C] per component, owned on the heap and referenced
# through a type-erased pointer slot indexed by the component's pack position.
# Only the POINTER is erased — store internals stay fully typed and safe.

from std.memory import UnsafePointer, alloc

comptime Slot = type_of(alloc[NoneType](1))


trait ComponentType(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    comptime ID: Int


@fieldwise_init
struct Position(ComponentType):
    comptime ID: Int = 0
    var x: Int
    var y: Int


@fieldwise_init
struct Velocity(ComponentType):
    comptime ID: Int = 1
    var dx: Int
    var dy: Int


@fieldwise_init
struct Health(ComponentType):
    comptime ID: Int = 2
    var hp: Int


# Fully-typed per-component store (toy dense list).
struct ComponentStore[C: ComponentType](Movable, Sized):
    var data: List[Self.C]

    def __init__(out self):
        self.data = List[Self.C]()

    def push(mut self, var v: Self.C):
        self.data.append(v^)

    def __len__(self) -> Int:
        return len(self.data)


struct Backend[*CTs: ComponentType](Movable):
    comptime N: Int = len(Self.CTs)
    var slots: List[Slot]

    def __init__(out self):
        # Preallocate exact capacity: a realloc here would corrupt the erased slots.
        self.slots = List[Slot](capacity=Self.N)
        comptime for i in range(Self.N):
            comptime T = Self.CTs[i]
            var p = alloc[ComponentStore[T]](1)
            p.init_pointee_move(ComponentStore[T]())
            self.slots.append(p.bitcast[NoneType]())

    def __del__(deinit self):
        comptime for i in range(Self.N):
            comptime T = Self.CTs[i]
            var p = self.slots[i].bitcast[ComponentStore[T]]()
            p.destroy_pointee()
            p.free()

    @staticmethod
    def slot_of[C: ComponentType]() -> Int:
        var idx = -1
        comptime for i in range(Self.N):
            comptime if Self.CTs[i].ID == C.ID:
                idx = i
        return idx

    def store[C: ComponentType](self) -> type_of(alloc[ComponentStore[C]](1)):
        return self.slots[Self.slot_of[C]()].bitcast[ComponentStore[C]]()

    def push[C: ComponentType](mut self, var v: C):
        self.store[C]()[].push(v^)

    def count[C: ComponentType](self) -> Int:
        return len(self.store[C]()[])

    # Value-returning accessor: keeps `self` alive for the call (no escaping pointer).
    def get[C: ComponentType](self, i: Int) -> C:
        return self.store[C]()[].data[i]


def assert_true(cond: Bool, msg: String) raises:
    if not cond:
        raise Error("ASSERT FAILED: " + msg)


def main() raises:
    var b = Backend[Position, Velocity, Health]()
    b.push(Position(1, 2))
    b.push(Position(3, 4))
    b.push(Velocity(5, 6))
    b.push(Health(100))

    assert_true(b.count[Position]() == 2, "pos count")
    assert_true(b.count[Velocity]() == 1, "vel count")
    assert_true(b.count[Health]() == 1, "hp count")

    var p1 = b.get[Position](1)
    assert_true(p1.x == 3 and p1.y == 4, "pos[1] value")
    var h0 = b.get[Health](0)
    assert_true(h0.hp == 100, "hp[0] value")

    print("spike_variadic_storage: PASS")
