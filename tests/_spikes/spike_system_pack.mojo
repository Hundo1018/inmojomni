# Spike 1: register systems as a TYPE pack (the proven `*CTs` mechanism), where
# each system is a struct conforming to `System` with a `@staticmethod apply`.
# Dispatch is fully compile-time: `Self.Systems[i].apply(world)`. No function
# values, no boxing, no vtable. (Counter stands in for World here.)

@fieldwise_init
struct Counter(Movable):
    var n: Int


trait System:
    @staticmethod
    def apply(mut c: Counter): ...


struct Inc(System):
    @staticmethod
    def apply(mut c: Counter):
        c.n += 1


struct Dbl(System):
    @staticmethod
    def apply(mut c: Counter):
        c.n *= 2


struct Sched[*Systems: System](Movable):
    comptime K: Int = len(Self.Systems)

    def __init__(out self):
        pass

    def tick(self, mut c: Counter):
        comptime for i in range(Self.K):
            comptime Sys = Self.Systems[i]
            Sys.apply(c)


def main() raises:
    var c = Counter(1)
    # Inc -> 2, Dbl -> 4, Inc -> 5
    var s = Sched[Inc, Dbl, Inc]()
    s.tick(c)
    if c.n != 5:
        raise Error("FAIL: expected 5, got " + String(c.n))
    print("spike_system_pack: PASS n =", c.n)
