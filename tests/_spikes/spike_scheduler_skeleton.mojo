# Spike 2: the full scheduler skeleton in a toy, mirroring the real types:
#   - `Backend` trait + `World[B]`  (toy StorageBackend / World)
#   - `System` trait with a BACKEND-GENERIC `@staticmethod apply[B]`
#   - `Scheduler` trait with an ASSOCIATED TYPE `comptime B: Backend`,
#     so `tick(mut World[Self.B])` and a generic driver `run[S: Scheduler]()`
#     can recover the backend from the scheduler type.
# Validates the trait shape end-to-end before wiring the real engine.


# --- toy storage backend + world ---
trait Backend(Defaultable, Movable, ImplicitlyDeletable):
    def add(mut self, x: Int): ...
    def total(self) -> Int: ...


struct ListBackend(Backend):
    var xs: List[Int]

    def __init__(out self):
        self.xs = List[Int]()

    def add(mut self, x: Int):
        self.xs.append(x)

    def total(self) -> Int:
        var s = 0
        for i in range(len(self.xs)):
            s += self.xs[i]
        return s


struct World[B: Backend](Movable, ImplicitlyDeletable):
    var backend: Self.B

    def __init__(out self):
        self.backend = Self.B()

    def add(mut self, x: Int):
        self.backend.add(x)

    def total(self) -> Int:
        return self.backend.total()


# --- systems: backend-generic, like run_scenario[B] ---
trait System:
    @staticmethod
    def apply[B: Backend](mut w: World[B]): ...


struct AddOne(System):
    @staticmethod
    def apply[B: Backend](mut w: World[B]):
        w.add(1)


struct AddTwo(System):
    @staticmethod
    def apply[B: Backend](mut w: World[B]):
        w.add(2)


# --- the swap seam ---
trait Scheduler(Defaultable, Movable, ImplicitlyDeletable):
    comptime B: Backend
    def tick(mut self, mut w: World[Self.B]): ...


struct SequentialScheduler[Bk: Backend, *Systems: System](Scheduler):
    comptime B = Self.Bk  # satisfy the trait's associated backend type

    def __init__(out self):
        pass

    def tick(mut self, mut w: World[Self.B]):
        comptime for i in range(len(Self.Systems)):
            comptime Sys = Self.Systems[i]
            Sys.apply[Self.B](w)


# --- generic driver recovering the backend from S.B ---
def run_scenario[S: Scheduler]() -> Int:
    var w = World[S.B]()
    var sched = S()
    sched.tick(w)
    return w.total()


def main() raises:
    # AddOne, AddTwo, AddOne -> total 1+2+1 = 4
    var got = run_scenario[SequentialScheduler[ListBackend, AddOne, AddTwo, AddOne]]()
    if got != 4:
        raise Error("FAIL: expected 4, got " + String(got))
    print("spike_scheduler_skeleton: PASS total =", got)
