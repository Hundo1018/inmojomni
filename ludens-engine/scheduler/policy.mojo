"""The dispatch axis: how an actor scheduler drives its per-actor work loop.

`DispatchPolicy` is a zero-state, statically-dispatched policy (never
instantiated — only its `comptime PARALLEL` marker and static `run` are used).
`run[body](n)` calls `body(i)` for every `i` in `[0, n)`:

  - `Serial`   — a plain in-order loop. Deterministic by construction.
  - `Parallel` — `std.algorithm.parallelize` across worker threads.

The actor schedulers structure each round so that `body(i)` touches only
actor `i`'s own world data (an in-place component overwrite on a disjoint dense
slot) and its own private outbox slot. Under that discipline the two policies
produce identical results — the parallel run is reproducible, so it can be parity
-checked against the serial run and against the sequential scheduler.
"""

from std.algorithm import parallelize


trait DispatchPolicy:
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
