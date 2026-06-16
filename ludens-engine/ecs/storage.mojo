"""The swappable storage interface.

`World[B: StorageBackend]` is written once against this trait; choosing
`SparseSetBackend[...]` vs `ArchetypeBackend[...]` swaps the storage strategy with
zero changes to game code. The trait deliberately uses *value*-returning
accessors (`get` returns a copy, `set` takes a value): backends keep their data
behind type-erased pointers, and leaking such a pointer across statements would
let the backend be destroyed early (see the heterogeneous-storage notes).

Queries are exposed as fixed-arity `matching1/2/3` returning the matching
entities; the caller iterates them and reads/writes components via `get`/`set`.
"""

from .entity import Entity
from .component import ComponentType


@fieldwise_init
struct Record(Copyable, ImplicitlyCopyable, Movable, ImplicitlyDeletable):
    """Where an entity lives. The archetype backend uses both fields; the
    sparse-set backend only needs liveness so it stores the generation in `row`."""

    var archetype: Int
    var row: Int


trait StorageBackend(Defaultable, Movable, ImplicitlyDeletable):
    # lifecycle
    def spawn(mut self) -> Entity: ...
    def despawn(mut self, e: Entity): ...
    def is_alive(self, e: Entity) -> Bool: ...
    def entity_count(self) -> Int: ...

    # typed component access (generic methods — the impl maps C.ID to a slot)
    def set[C: ComponentType](mut self, e: Entity, var value: C): ...
    def has[C: ComponentType](self, e: Entity) -> Bool: ...
    def get[C: ComponentType](self, e: Entity) -> C: ...
    def remove[C: ComponentType](mut self, e: Entity): ...

    # queries: entities possessing all of the given components
    def matching1[A: ComponentType](self) -> List[Entity]: ...
    def matching2[A: ComponentType, B: ComponentType](self) -> List[Entity]: ...
    def matching3[
        A: ComponentType, B: ComponentType, C: ComponentType
    ](self) -> List[Entity]: ...
