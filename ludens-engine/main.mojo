from std.collections import List, InlineArray
from std.iter import Iterable, Iterator


struct SparseSet[
    fixed_size: Int,
    //,
    *keys: Int,
](Boolable, Defaultable, ImplicitlyCopyable, Iterable, Movable, Sized):
    comptime IteratorType = Self

    comptime _list = VariadicParamList(Self.keys)
    var _sparse: InlineArray[Int, Self.fixed_size]
    # storage the index of dense array
    var _dense: List[Int]
    # storage the keys

    # for __iter__ __next__ using

    fn __init__(out self):
        self._sparse = InlineArray[Int, Self.fixed_size](fill=-1)
        self._dense = List[Int]()

        for i in range(Self.fixed_size):
            self._sparse[i] = -1
        for i in range(len(Self._list)):
            self.add(self._list[i])

    fn __len__(self) -> Int:
        return len(self._dense)

    fn __bool__(self) -> Bool:
        return len(self) > 0

    fn add(mut self, key: Int) -> None:
        # Add a key into set.
        if self.contains(key):
            return
        # makesure the number does not exist.
        self._sparse[key] = len(self._dense)
        # update sparse array
        self._dense.append(key)
        # update dense array

    fn contains(read self, key: Int) -> Bool:
        # Check the key whether or not in the set.
        index = self._sparse[key]
        return (
            index >= 0
            and index < len(self._dense)
            and self._dense[index] == key
        )

    fn remove(mut self, key: Int):
        # Remove the key from the set.
        if not self.contains(key):
            return
        index = self._sparse[key]
        self._sparse[key] = -1
        # remove map from sparse to dense

        self._dense[index] = self._dense[-1]
        _ = self._dense.pop()
        # remove the last index of dense

    fn __copyinit__(out self, copy: Self):
        # Implement for __iter__.
        self = copy
        for i in range(Self.fixed_size):
            self._sparse[i] = copy._sparse[i]

    fn __iter__(mut self) -> Self.IteratorType:
        ...


struct SparseSetIterator(ImplicitlyCopyable, Iterable, Iterator):
    comptime Element = Int
    var _current: Int = -1

    fn __next__(mut self) -> Self.Element:
        self._current += 1
        return self._dense[self._current]

    fn __has_next__(self) -> Bool:
        return self._current < len(self._dense) - 1


fn main():
    var my_set = SparseSet[fixed_size=32, 2, 1, 3]()
    my_set.add(5)
    for element in my_set:
        print(element)
