"""Entity-as-actor scheduler: every entity is an actor with a mailbox.

Each tick has two stages, both driven by the swappable `DispatchPolicy`:

  1. **Wake** — every actor in the population runs `update` once: it advances its
     own state (e.g. integrates its position) and may *send* messages addressed to
     other entities. An actor mutates **only its own entity's already-present
     components** (an in-place overwrite on a disjoint storage slot), so the wake
     loop is safe to run in parallel and is bit-identical to the serial order.
  2. **Drain** — sent messages are routed (serially, in ascending actor order) into
     recipient inboxes; every actor with mail runs `receive`, which may send more.
     This repeats until no messages remain (or `MAX_ROUNDS`), so an effect emitted
     this tick is fully applied this tick — matching what an imperative system
     would compute, which is what makes the parity test hold.

The actor population is the set of entities carrying the handler's `Key`
component (`world.query1[H.Key]()`); messages are routed by entity id.
"""

from ecs.world import World
from ecs.storage import StorageBackend
from ecs.component import ComponentType
from ecs.entity import Entity
from .scheduler import Scheduler
from .policy import DispatchPolicy
from .message import (
    MessageType,
    Envelope,
    empty_envelopes,
    empty_inboxes,
    has_messages,
)

comptime MAX_ROUNDS = 16  # safety cap on per-tick message cascades


trait EntityHandler:
    """One entity's behavior. `Key` selects the actor population (entities that
    carry this component); `M` is the message type these actors exchange."""

    comptime M: MessageType
    comptime Key: ComponentType

    @staticmethod
    def update[B: StorageBackend](
        mut world: World[B], e: Entity, mut outbox: List[Envelope[Self.M]]
    ): ...

    @staticmethod
    def receive[B: StorageBackend](
        mut world: World[B],
        e: Entity,
        inbox: List[Self.M],
        mut outbox: List[Envelope[Self.M]],
    ): ...


def _route[M: MessageType](
    outboxes: List[List[Envelope[M]]],
    mut inboxes: List[List[M]],
    slot_of: List[Int],
    max_id: Int,
):
    """Deliver each envelope to its recipient's inbox, in ascending sender order
    (deterministic regardless of how the wake/drain loop was dispatched)."""
    for i in range(len(outboxes)):
        for j in range(len(outboxes[i])):
            var env = outboxes[i][j]
            if 0 <= env.target <= max_id:
                var s = slot_of[env.target]
                if s >= 0:
                    inboxes[s].append(env.payload)


struct EntityActorScheduler[
    Bk: StorageBackend, D: DispatchPolicy, H: EntityHandler
](Scheduler):
    comptime B = Self.Bk  # satisfy the trait's associated backend type

    def __init__(out self):
        pass

    def tick(mut self, mut world: World[Self.B]):
        comptime M = Self.H.M
        var actors = world.query1[Self.H.Key]()
        var n = len(actors)
        if n == 0:
            return

        # entity id -> slot in `actors`, for routing messages addressed by id
        var max_id = 0
        for i in range(n):
            if actors[i].id > max_id:
                max_id = actors[i].id
        var slot_of = List[Int](capacity=max_id + 1)
        for _ in range(max_id + 1):
            slot_of.append(-1)
        for i in range(n):
            slot_of[actors[i].id] = i

        # --- stage 1: wake every actor once (own-entity mutation + initial sends) ---
        var outboxes = empty_envelopes[M](n)

        @parameter
        def wake(i: Int):
            Self.H.update[Self.B](world, actors[i], outboxes[i])

        Self.D.run[wake](n)

        var inboxes = empty_inboxes[M](n)
        _route[M](outboxes, inboxes, slot_of, max_id)

        # --- stage 2: drain message cascades until quiescent ---
        var rounds = 0
        while rounds < MAX_ROUNDS and has_messages[M](inboxes):
            var next_out = empty_envelopes[M](n)

            @parameter
            def deliver(i: Int):
                if len(inboxes[i]) > 0:
                    Self.H.receive[Self.B](
                        world, actors[i], inboxes[i], next_out[i]
                    )

            Self.D.run[deliver](n)

            var next_in = empty_inboxes[M](n)
            _route[M](next_out, next_in, slot_of, max_id)
            inboxes = next_in^
            rounds += 1
