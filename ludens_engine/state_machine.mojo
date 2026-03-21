struct StateId(
    Copyable,
    ImplicitlyCopyable,
    Movable,
):
    var value: Int

    fn __init__(out self, value: Int):
        self.value = value


struct StateMachine(Copyable, ImplicitlyCopyable, Movable):
    var _has_state: Bool
    var _current: StateId

    fn __init__(out self):
        self._has_state = False
        self._current = StateId(0)

    fn has_state(self) -> Bool:
        return self._has_state

    fn current_state(self) -> StateId:
        return self._current

    fn is_in(self, state: StateId) -> Bool:
        return self._has_state and self._current.value == state.value

    fn transition_to(mut self, state: StateId) -> None:
        self._has_state = True
        self._current = state

    fn clear(mut self) -> None:
        self._has_state = False
        self._current = StateId(0)
