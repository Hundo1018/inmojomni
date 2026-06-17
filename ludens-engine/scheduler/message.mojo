"""Messages and mailboxes for the actor schedulers.

An actor scheduler is parameterized over a single message type `M` (one type
keeps mailboxes a plain `List[Envelope[M]]` — no type erasure — and keeps the
serial/parallel parity tractable). A richer protocol can pack a discriminator in
`KIND` and a union payload in `M`.

`Envelope.target` names the recipient: an *entity id* for the entity-actor
scheduler, or a *system index* for the system-actor scheduler. The structure is
shared; only the routing interpretation differs per topology.
"""

from ecs.entity import Entity


trait MessageType(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    """A message payload. `KIND` is an optional discriminator for protocols that
    fold several logical messages into one struct."""

    comptime KIND: Int


@fieldwise_init
struct Envelope[M: MessageType](
    Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable
):
    """A message addressed to a recipient. `target` is an entity id (entity
    actors) or a system index (system actors)."""

    var target: Int
    var payload: Self.M


# --- shared mailbox helpers (used by both actor schedulers) ---


def empty_envelopes[M: MessageType](n: Int) -> List[List[Envelope[M]]]:
    """`n` empty per-actor outboxes, pre-sized so the parallel phase only writes
    existing, disjoint slots."""
    var out = List[List[Envelope[M]]]()
    for _ in range(n):
        out.append(List[Envelope[M]]())
    return out^


def empty_inboxes[M: MessageType](n: Int) -> List[List[M]]:
    """`n` empty per-actor inboxes."""
    var out = List[List[M]]()
    for _ in range(n):
        out.append(List[M]())
    return out^


def has_messages[M: MessageType](inboxes: List[List[M]]) -> Bool:
    for i in range(len(inboxes)):
        if len(inboxes[i]) > 0:
            return True
    return False
