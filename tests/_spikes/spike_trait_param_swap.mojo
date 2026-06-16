# Spike C: swap implementations via a compile-time generic parameter.
# Verifies: trait with methods, two impls, a generic consumer holding `var b: B`,
# and calling trait methods through it.


def assert_true(cond: Bool, msg: String) raises:
    if not cond:
        raise Error("ASSERT FAILED: " + msg)


trait Counter(Defaultable, Copyable, Movable, ImplicitlyDeletable):
    def bump(mut self, n: Int): ...
    def total(self) -> Int: ...


@fieldwise_init
struct DoubleCounter(Counter):
    var value: Int

    def __init__(out self):
        self.value = 0

    def bump(mut self, n: Int):
        self.value += n * 2

    def total(self) -> Int:
        return self.value


@fieldwise_init
struct PlainCounter(Counter):
    var value: Int

    def __init__(out self):
        self.value = 0

    def bump(mut self, n: Int):
        self.value += n

    def total(self) -> Int:
        return self.value


# Generic consumer that stores the swappable backend as a field.
struct Driver[C: Counter](Movable):
    var backend: Self.C

    def __init__(out self):
        self.backend = Self.C()

    def run(mut self, steps: Int):
        for _ in range(steps):
            self.backend.bump(1)

    def total(self) -> Int:
        return self.backend.total()


def main() raises:
    var d = Driver[DoubleCounter]()
    d.run(5)
    print("DoubleCounter total =", d.total())
    assert_true(d.total() == 10, "double")

    var p = Driver[PlainCounter]()
    p.run(5)
    print("PlainCounter total =", p.total())
    assert_true(p.total() == 5, "plain")

    print("spike_trait_param_swap: PASS")
