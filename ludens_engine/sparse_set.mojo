from std.collections import List, InlineArray


struct SparseSet[capacity: Int](Movable):
    var _sparse: InlineArray[Int, Self.capacity]
    var _dense: List[Int]

    fn __init__(out self):
        self._sparse = InlineArray[Int, Self.capacity](fill=-1)
        self._dense = List[Int]()

    fn len(self) -> Int:
        return len(self._dense)

    fn contains(self, key: Int) -> Bool:
        if not self._is_valid_key(key):
            return False

        var dense_index = self._sparse[key]
        return (
            dense_index >= 0
            and dense_index < len(self._dense)
            and self._dense[dense_index] == key
        )

    fn add(mut self, key: Int) -> None:
        if not self._is_valid_key(key) or self.contains(key):
            return

        self._sparse[key] = len(self._dense)
        self._dense.append(key)

    fn remove(mut self, key: Int) -> None:
        if not self.contains(key):
            return

        var removed_index = self._sparse[key]
        var last_dense_index = len(self._dense) - 1
        var last_key = self._dense[last_dense_index]

        self._dense[removed_index] = last_key
        self._sparse[last_key] = removed_index
        _ = self._dense.pop()
        self._sparse[key] = -1

    fn value_at(self, dense_index: Int) -> Int:
        return self._dense[dense_index]

    fn _is_valid_key(self, key: Int) -> Bool:
        return key >= 0 and key < Self.capacity
