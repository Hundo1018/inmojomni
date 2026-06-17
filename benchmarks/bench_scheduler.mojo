"""Scheduler benchmark: one workload across every scheduler strategy.

The same per-tick workload — integrate every entity, and have every even-id entity
deal damage to its neighbour — is driven by the sequential baseline, the
entity-actor scheduler and the system-actor scheduler, each under serial and
parallel dispatch. The workload is deliberately message-heavy so the actor
schedulers' mailbox build / route / drain overhead is visible against the
baseline's plain in-order loop.

Read the *relative* columns: the actor schedulers carry messaging overhead the
sequential baseline does not, and the `parallel` dispatch trades thread-launch
overhead for per-entity concurrency that only pays off as N grows. Run with:
`mojo run -I build benchmarks/bench_scheduler.mojo`.
"""

from std.benchmark import keep
from ecs.world import World
from ecs.storage import StorageBackend
from ecs.sparse_backend import SparseSetBackend
from ecs.component import ComponentType
from ecs.entity import Entity
from scheduler.scheduler import Scheduler, System
from scheduler.sequential import SequentialScheduler
from scheduler.entity_actor import EntityActorScheduler, EntityHandler
from scheduler.system_actor import SystemActorScheduler, ActorSystem
from scheduler.policy import Serial, Parallel
from scheduler.message import MessageType, Envelope
from harness.bench import BenchTable, now

comptime DMG = 1
comptime APPLY_IDX = 1


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


@fieldwise_init
struct Damage(MessageType):
    comptime KIND: Int = 0
    var amount: Int


@fieldwise_init
struct DamageCmd(MessageType):
    comptime KIND: Int = 0
    var entity: Int
    var amount: Int


# --- sequential systems ---
struct MoveSystem(System):
    @staticmethod
    def apply[B: StorageBackend](mut w: World[B]):
        var movers = w.query2[Position, Velocity]()
        for i in range(len(movers)):
            var e = movers[i]
            var p = w.get[Position](e)
            var v = w.get[Velocity](e)
            w.set(e, Position(p.x + v.dx, p.y + v.dy))


struct DamageSystem(System):
    @staticmethod
    def apply[B: StorageBackend](mut w: World[B]):
        var ents = w.query1[Health]()
        var n = len(ents)
        var max_id = 0
        for i in range(n):
            if ents[i].id > max_id:
                max_id = ents[i].id
        var index_of = List[Int](capacity=max_id + 1)
        for _ in range(max_id + 1):
            index_of.append(-1)
        for i in range(n):
            index_of[ents[i].id] = i
        for i in range(n):
            var e = ents[i]
            if e.id % 2 == 0 and e.id + 1 <= max_id and index_of[e.id + 1] >= 0:
                var target = ents[index_of[e.id + 1]]
                var h = w.get[Health](target)
                w.set(target, Health(h.hp - DMG))


# --- entity-actor handler ---
struct SpreadHandler(EntityHandler):
    comptime M = Damage
    comptime Key = Health

    @staticmethod
    def update[B: StorageBackend](
        mut w: World[B], e: Entity, mut outbox: List[Envelope[Damage]]
    ):
        var p = w.get[Position](e)
        var v = w.get[Velocity](e)
        w.set(e, Position(p.x + v.dx, p.y + v.dy))
        if e.id % 2 == 0:
            outbox.append(Envelope[Damage](e.id + 1, Damage(DMG)))

    @staticmethod
    def receive[B: StorageBackend](
        mut w: World[B],
        e: Entity,
        inbox: List[Damage],
        mut outbox: List[Envelope[Damage]],
    ):
        var total = 0
        for i in range(len(inbox)):
            total += inbox[i].amount
        if total > 0:
            var h = w.get[Health](e)
            w.set(e, Health(h.hp - total))


# --- system actors ---
struct EmitSystem(ActorSystem):
    comptime M = DamageCmd

    @staticmethod
    def handle[B: StorageBackend](
        mut w: World[B], inbox: List[DamageCmd]
    ) -> List[Envelope[DamageCmd]]:
        var out = List[Envelope[DamageCmd]]()
        var movers = w.query2[Position, Velocity]()
        for i in range(len(movers)):
            var e = movers[i]
            var p = w.get[Position](e)
            var v = w.get[Velocity](e)
            w.set(e, Position(p.x + v.dx, p.y + v.dy))
            if e.id % 2 == 0:
                out.append(Envelope[DamageCmd](APPLY_IDX, DamageCmd(e.id + 1, DMG)))
        return out^


struct ApplySystem(ActorSystem):
    comptime M = DamageCmd

    @staticmethod
    def handle[B: StorageBackend](
        mut w: World[B], inbox: List[DamageCmd]
    ) -> List[Envelope[DamageCmd]]:
        var out = List[Envelope[DamageCmd]]()
        if len(inbox) == 0:
            return out^
        var ents = w.query1[Health]()
        var n = len(ents)
        var max_id = 0
        for i in range(n):
            if ents[i].id > max_id:
                max_id = ents[i].id
        var index_of = List[Int](capacity=max_id + 1)
        for _ in range(max_id + 1):
            index_of.append(-1)
        for i in range(n):
            index_of[ents[i].id] = i
        for i in range(len(inbox)):
            var cmd = inbox[i]
            if 0 <= cmd.entity <= max_id and index_of[cmd.entity] >= 0:
                var target = ents[index_of[cmd.entity]]
                var h = w.get[Health](target)
                w.set(target, Health(h.hp - cmd.amount))
        return out^


def run_sched[
    S: Scheduler
](mut table: BenchTable, variant: String, n: Int, frames: Int):
    var t0 = now()
    var w = World[S.B]()
    for i in range(n):
        var e = w.spawn()
        w.set(e, Position(i, 0))
        w.set(e, Velocity(1, 0))
        w.set(e, Health(1_000_000))
    var t1 = now()
    table.add(variant, n, "spawn", t1 - t0, n)

    var sched = S()
    var t2 = now()
    for _ in range(frames):
        sched.tick(w)
    var hsum = 0
    var hall = w.query1[Health]()
    for i in range(len(hall)):
        hsum += w.get[Health](hall[i]).hp
    keep(hsum)
    var t3 = now()
    table.add(variant, n, "tick", t3 - t2, n * frames)


def bench_all(mut table: BenchTable, n: Int, frames: Int):
    comptime B = SparseSetBackend[Position, Velocity, Health]
    run_sched[SequentialScheduler[B, MoveSystem, DamageSystem]](
        table, "sequential", n, frames
    )
    run_sched[EntityActorScheduler[B, Serial, SpreadHandler]](
        table, "entity-actor serial", n, frames
    )
    run_sched[EntityActorScheduler[B, Parallel, SpreadHandler]](
        table, "entity-actor parallel", n, frames
    )
    run_sched[SystemActorScheduler[B, Serial, EmitSystem, ApplySystem]](
        table, "system-actor serial", n, frames
    )
    run_sched[SystemActorScheduler[B, Parallel, EmitSystem, ApplySystem]](
        table, "system-actor parallel", n, frames
    )


def fill(mut table: BenchTable):
    var frames = 20
    bench_all(table, 500, frames)
    bench_all(table, 1_000, frames)
    bench_all(table, 4_000, frames)


def main() raises:
    var table = BenchTable(
        "Schedulers — integrate + damage-event workload (F=20 frames)"
    )
    fill(table)
    table.print_report()
