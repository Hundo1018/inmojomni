from ludens_engine.state_machine import StateId, StateMachine


fn test_state_machine_starts_empty() raises:
    var machine = StateMachine()

    assert not machine.has_state()


fn test_transition_replaces_current_state() raises:
    var machine = StateMachine()
    var idle = StateId(1)
    var running = StateId(2)

    machine.transition_to(idle)
    assert machine.has_state()
    assert machine.is_in(idle)

    machine.transition_to(running)

    assert not machine.is_in(idle)
    assert machine.is_in(running)


fn test_clear_removes_state() raises:
    var machine = StateMachine()
    var jumping = StateId(3)

    machine.transition_to(jumping)
    machine.clear()

    assert not machine.has_state()


fn main() raises:
    test_state_machine_starts_empty()
    test_transition_replaces_current_state()
    test_clear_removes_state()
