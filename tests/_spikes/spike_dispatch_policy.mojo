# Spike 3+4: the Dispatch axis as a swappable policy.
#   - `DispatchPolicy` trait with a `comptime PARALLEL: Bool` marker and a static
#     `run[body](n)` that drives a closure over [0, n).
#   - `Serial` = plain loop; `Parallel` = `parallelize` (worker threads).
# The closure writes only its own disjoint arena slot `arena[i]` (no shared
# mutation), so a following serial reduce is identical for both policies.

from std.algorithm import parallelize
from std.memory import alloc


trait DispatchPolicy:
    # Pure static-dispatch policy — never instantiated, so no value supertraits.
    comptime PARALLEL: Bool

    @staticmethod
    def run[body: def (Int) capturing [_] -> None](n: Int): ...


struct Serial(DispatchPolicy):
    comptime PARALLEL = False

    @staticmethod
    def run[body: def (Int) capturing [_] -> None](n: Int):
        for i in range(n):
            body(i)


struct Parallel(DispatchPolicy):
    comptime PARALLEL = True

    @staticmethod
    def run[body: def (Int) capturing [_] -> None](n: Int):
        parallelize[body](n)


def square_sum[D: DispatchPolicy](n: Int) -> Int:
    var arena = alloc[Int](n)

    @parameter
    def worker(i: Int):
        arena[i] = i * i  # disjoint slot: worker i touches only arena[i]

    D.run[worker](n)

    var s = 0
    for i in range(n):
        s += arena[i]
    arena.free()
    return s


def main() raises:
    # sum of i*i for i in 0..9 == 285, identical for both policies
    var ser = square_sum[Serial](10)
    var par = square_sum[Parallel](10)
    if ser != 285 or par != 285:
        raise Error("FAIL: serial=" + String(ser) + " parallel=" + String(par))
    print("spike_dispatch_policy: PASS serial =", ser, "parallel =", par)
