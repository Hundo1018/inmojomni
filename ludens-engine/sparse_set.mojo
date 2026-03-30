
struct SparseSet[
    fixed_size: Int,
](Boolable, Defaultable, Iterable, Sized):
    var _sparse: InlineArray[Int, Self.fixed_size]
    # storage the index of dense array
    var _dense: List[Int]
    # storage the keys

    comptime IteratorType[
        iterable_mut: Bool, //, iterable_origin: Origin[mut=iterable_mut]
    ]: Iterator = List[Int]

    # for __iter__ __next__ using

    def __init__(out self):
        self._sparse = InlineArray[Int, Self.fixed_size](fill=-1)
        self._dense = List[Int]()

        for i in range(Self.fixed_size):
            self._sparse[i] = -1

    def __len__(self) -> Int:
        return len(self._dense)

    def __bool__(self) -> Bool:
        return len(self) > 0

    def add(mut self, key: Int) -> None:
        # Add a key into set.
        if self.contains(key):
            return
        # makesure the number does not exist.
        self._sparse[key] = len(self._dense)
        # update sparse array
        self._dense.append(key)
        # update dense array

    def contains(read self, key: Int) -> Bool:
        # Check the key whether or not in the set.
        index = self._sparse[key]
        return (
            index >= 0
            and index < len(self._dense)
            and self._dense[index] == key
        )

    def remove(mut self, key: Int):
        # Remove the key from the set.
        if not self.contains(key):
            return
        index = self._sparse[key]
        self._sparse[key] = -1
        # remove map from sparse to dense

        self._dense[index] = self._dense[-1]
        _ = self._dense.pop()
        # remove the last index of dense

    def __iter__(
        ref self,
    ) -> Self.IteratorType[origin_of(self)]:
        """
        basicly _dense
        """
        ...


def main():
    var my_set = SparseSet[32]()
    my_set.add(5)
    my_set.add(4)
    my_set.add(31)
    my_set.add(0)
    for element in my_set:
        print(element)
