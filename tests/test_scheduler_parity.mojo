"""Scheduler swap parity: the sequential baseline, the entity-actor scheduler
(serial dispatch) and the entity-actor scheduler (parallel dispatch) must all
produce the identical final world state on the same deterministic workload — and
they must do so on more than one storage backend, proving scheduler-swap is
orthogonal to backend-swap.

Workload: N entities, each with Position(x=id), Velocity(dx=1), Health(100).
Per tick: every entity integrates `pos += vel`; every even-id entity deals 10
damage to its id+1 neighbour. After F ticks every odd entity has lost 10*F hp and
every even entity is untouched — an order-independent result the summary checks.
"""

from harness.runner import Suite
from ecs.world import World
from ecs.storage import StorageBackend
from ecs.sparse_backend import SparseSetBackend
from ecs.archetype import ArchetypeBackend
from ecs.component import ComponentType
from ecs.entity import Entity

from scheduler.scheduler import Scheduler, System
from scheduler.sequential import SequentialScheduler
from scheduler.entity_actor import EntityActorScheduler, EntityHandler
from scheduler.system_actor import SystemActorScheduler, ActorSystem
from scheduler.policy import Serial, Parallel
from scheduler.message import MessageType, Envelope

comptime N = 12
comptime FRAMES = 3
comptime DMG = 10


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
    """Entity-actor message: amount only — the recipient is the envelope target."""

    comptime KIND: Int = 0
    var amount: Int


@fieldwise_init
struct DamageCmd(MessageType):
    """System-actor message: carries the target *entity* id, since the envelope
    target is the recipient *system*."""

    comptime KIND: Int = 0
    var entity: Int
    var amount: Int


comptime APPLY_IDX = 1  # ApplySystem's index in the SystemActorScheduler pack


# --- sequential systems: the imperative reference ---
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
        # each even-id entity damages its id+1 neighbour exactly once
        for i in range(n):
            var e = ents[i]
            if e.id % 2 == 0 and e.id + 1 <= max_id and index_of[e.id + 1] >= 0:
                var target = ents[index_of[e.id + 1]]
                var h = w.get[Health](target)
                w.set(target, Health(h.hp - DMG))


# --- entity-actor handler: the same logic as message passing ---
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


# --- system actors: the same logic as a two-stage dataflow ---
struct EmitSystem(ActorSystem):
    """Source actor: integrates every entity and emits a damage command to the
    ApplySystem for each even-id entity's neighbour. Writes only Position."""

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
    """Sink actor: applies queued damage commands. Writes only Health, and only
    in the drain round (empty inbox at kickoff) — so it never writes concurrently
    with EmitSystem's Position writes."""

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


# A fixed scenario written once against the Scheduler interface; returns an
# order-independent summary so different schedulers can be compared exactly.
def run_sched_scenario[S: Scheduler]() -> List[Int]:
    var w = World[S.B]()
    for i in range(N):
        var e = w.spawn()
        w.set(e, Position(i, 0))
        w.set(e, Velocity(1, 0))
        w.set(e, Health(100))

    var sched = S()
    for _ in range(FRAMES):
        sched.tick(w)

    var out = List[Int]()
    out.append(w.entity_count())
    var pall = w.query1[Position]()
    var sum_x = 0
    for i in range(len(pall)):
        sum_x += w.get[Position](pall[i]).x
    out.append(sum_x)
    var hall = w.query1[Health]()
    var sum_hp = 0
    for i in range(len(hall)):
        sum_hp += w.get[Health](hall[i]).hp
    out.append(sum_hp)
    out.append(len(pall))
    out.append(len(hall))
    return out^


def _compare(mut s: Suite, name: String, base: List[Int], other: List[Int]):
    var labels = List[String]()
    labels.append("entity_count")
    labels.append("sum_x")
    labels.append("sum_hp")
    labels.append("count[P]")
    labels.append("count[H]")
    s.eqi(len(other), len(base), name + ": summary length matches")
    for i in range(len(base)):
        s.eqi(other[i], base[i], name + " parity: " + labels[i])


def _run_for_backend[B: StorageBackend](mut s: Suite, tag: String):
    var seq = run_sched_scenario[SequentialScheduler[B, MoveSystem, DamageSystem]]()
    var ea_ser = run_sched_scenario[EntityActorScheduler[B, Serial, SpreadHandler]]()
    var ea_par = run_sched_scenario[EntityActorScheduler[B, Parallel, SpreadHandler]]()
    var sa_ser = run_sched_scenario[SystemActorScheduler[B, Serial, EmitSystem, ApplySystem]]()
    var sa_par = run_sched_scenario[SystemActorScheduler[B, Parallel, EmitSystem, ApplySystem]]()
    _compare(s, tag + " entity-actor serial", seq, ea_ser)
    _compare(s, tag + " entity-actor parallel", seq, ea_par)
    _compare(s, tag + " system-actor serial", seq, sa_ser)
    _compare(s, tag + " system-actor parallel", seq, sa_par)


def main() raises:
    var s = Suite("scheduler_parity")

    _run_for_backend[SparseSetBackend[Position, Velocity, Health]](s, "sparse")
    _run_for_backend[ArchetypeBackend[Position, Velocity, Health]](s, "archetype")

    # sanity: hand-computed final state for N=12, FRAMES=3
    #   sum_x   = sum(id) + N*FRAMES = 66 + 36 = 102
    #   sum_hp  = 6 even * 100 + 6 odd * (100 - 30) = 600 + 420 = 1020
    var base = run_sched_scenario[
        SequentialScheduler[SparseSetBackend[Position, Velocity, Health], MoveSystem, DamageSystem]
    ]()
    s.eqi(base[0], N, "entity count == N")
    s.eqi(base[1], 102, "sum_x hand-computed")
    s.eqi(base[2], 1020, "sum_hp hand-computed")

    s.finish()
