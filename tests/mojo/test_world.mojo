from ludens_engine.state_machine import StateId
from ludens_engine.world import World


fn test_spawn_creates_unique_entities() raises:
    var world = World()

    var first = world.spawn()
    var second = world.spawn()

    assert first.value != second.value
    assert world.is_alive(first)
    assert world.is_alive(second)


fn test_despawn_marks_entity_as_not_alive() raises:
    var world = World()
    var entity = world.spawn()

    world.despawn(entity)

    assert not world.is_alive(entity)


fn test_world_manages_entity_state_machine() raises:
    var world = World()
    var entity = world.spawn()
    var idle = StateId(1)
    var running = StateId(2)

    world.transition_entity_to(entity, idle)
    assert world.entity_is_in_state(entity, idle)

    world.transition_entity_to(entity, running)
    assert not world.entity_is_in_state(entity, idle)
    assert world.entity_is_in_state(entity, running)


fn main() raises:
    test_spawn_creates_unique_entities()
    test_despawn_marks_entity_as_not_alive()
    test_world_manages_entity_state_machine()
