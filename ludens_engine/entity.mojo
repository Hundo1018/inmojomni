struct EntityId(
    Boolable,
    Copyable,
    ImplicitlyCopyable,
    Movable,
):
    var value: UInt

    fn __init__(out self, value: UInt):
        self.value = value

    fn __bool__(self) -> Bool:
        return self.value != 0
