from std.collections import List


@fieldwise_init
struct _SparseSetIter[
    mut: Bool,
    //,
    fixed_size: Int,
    T: Copyable & ImplicitlyCopyable,
    origin: Origin[mut=mut],
](Iterator):
    comptime Element = Self.T  # Required by the Iterator trait

    var index: Int
    var src: Pointer[SparseSet[Self.T, Self.fixed_size], Self.origin]

    def __has_next__(self) -> Bool:
        return self.index < len(self.src[])

    def __next__(mut self) -> Self.T:
        var val = self.src[]._data[self.index]
        self.index += 1
        return val


struct SparseSet[T: Copyable & ImplicitlyCopyable, fixed_size: Int](
    Boolable, Defaultable, Iterable, Sized
):
    var _sparse: InlineArray[Int, Self.fixed_size]
    # storage the index of dense array
    var _dense: List[Int]
    # storage the keys
    var _data: List[Self.T]

    # for __iter__ __next__ using
    comptime IteratorType[
        iterable_mut: Bool, //, iterable_origin: Origin[mut=iterable_mut]
    ]: Iterator = _SparseSetIter[Self.fixed_size, Self.T, iterable_origin]

    def __iter__(ref self) -> Self.IteratorType[origin_of(self)]:
        return {0, Pointer(to=self)}

    def __init__(out self):
        self._sparse = InlineArray[Int, Self.fixed_size](fill=-1)
        self._dense = List[Int]()
        self._data = List[Self.T]()

    def __len__(self) -> Int:
        return len(self._dense)

    def __bool__(self) -> Bool:
        return len(self) > 0

    def add(mut self, key: Int, value: Self.T) -> None:
        # Add a key into set.
        if self.contains(key):
            return
        # makesure the number does not exist.
        self._sparse[key] = len(self._dense)
        # update sparse array
        self._dense.append(key)
        # update dense array
        self._data.append(value)

    def contains(read self, key: Int) -> Bool:
        # Check the key whether or not in the set.
        index = self._sparse[key]
        return (
            index >= 0
            and index < len(self._dense)
            and self._dense[index] == key
        )

    def remove(mut self, key: Int):
        if not self.contains(key):
            return

        var index = self._sparse[key]
        var last_idx = len(self._dense) - 1
        var last_key = self._dense[last_idx]

        # 同步移動密集陣列與資料陣列的末端元素
        self._dense[index] = last_key
        self._data[index] = self._data[last_idx]

        # 更新被移動元素在稀疏陣列中的位置資訊
        self._sparse[last_key] = index

        # 清除移除目標的資訊並縮減空間
        self._sparse[key] = -1
        _ = self._dense.pop()
        _ = self._data.pop()


def main():
    var my_set = SparseSet[Int, 32]()
    my_set.add(5, 9)
    my_set.add(31, 9)
    my_set.add(4, 9)
    my_set.add(0, 9)
    print("len", len(my_set))
    for element in my_set:
        print(element)
    print("---")
    print(my_set._sparse)
    print(my_set._dense)
    print("===")
    my_set.remove(5)
    my_set.remove(31)
    my_set.remove(4)
    my_set.remove(0)
    for element in my_set:
        print(element)
    print("len", len(my_set))
    print(my_set._sparse)
    print(my_set._dense)
