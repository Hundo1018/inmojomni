from std.collections import List

from .entity import EntityId
from .state_machine import StateId, StateMachine


struct World(Movable):
    var _next_entity_value: UInt
    var _alive_entities: List[Bool]
    var _machines: List[StateMachine]

    fn __init__(out self):
        self._next_entity_value = 0
        self._alive_entities = List[Bool]()
        self._machines = List[StateMachine]()

    fn spawn(mut self) -> EntityId:
        var entity = EntityId(self._next_entity_value)
        self._next_entity_value += 1
        self._alive_entities.append(True)
        self._machines.append(StateMachine())
        return entity

    fn despawn(mut self, entity: EntityId) -> None:
        if not self._is_known_entity(entity):
            return

        self._alive_entities[entity.value] = False
        self._machines[entity.value].clear()

    fn is_alive(self, entity: EntityId) -> Bool:
        if not self._is_known_entity(entity):
            return False

        return self._alive_entities[entity.value]

    fn transition_entity_to(mut self, entity: EntityId, state: StateId) -> None:
        if not self.is_alive(entity):
            return

        self._machines[entity.value].transition_to(state)

    fn entity_is_in_state(self, entity: EntityId, state: StateId) -> Bool:
        if not self.is_alive(entity):
            return False

        return self._machines[entity.value].is_in(state)

    fn _is_known_entity(self, entity: EntityId) -> Bool:
        return Int(entity.value) >= 0 and Int(entity.value) < len(
            self._alive_entities
        )
