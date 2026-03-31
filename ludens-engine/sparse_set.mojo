from std.collections import List


@fieldwise_init
struct _MyStructIter[
    mut: Bool,
    //,
    T: Copyable & ImplicitlyCopyable,
    origin: Origin[mut=mut],
](ImplicitlyCopyable, Iterator):
    comptime Element = Self.T  # Required by the Iterator trait

    var index: Int
    var src: Pointer[MyStruct[Self.T], Self.origin]

    def __has_next__(self) -> Bool:
        return self.index < len(self.src[].data)

    def __next__(mut self) -> Self.T:
        var val = self.src[].data[self.index]
        self.index += 1
        return val


struct MyStruct[T: Copyable & ImplicitlyCopyable](Iterable):
    comptime IteratorType[
        iterable_mut: Bool, //, iterable_origin: Origin[mut=iterable_mut]
    ]: Iterator = _MyStructIter[Self.T, iterable_origin]

    var data: List[Self.T]

    def __iter__(ref self) -> Self.IteratorType[origin_of(self)]:
        return {0, Pointer(to=self)}


# ==
# ==
# ==


@fieldwise_init
struct _SparseSetIter[
    mut: Bool,
    //,
    fixed_size: Int,
    origin: Origin[mut=mut],
](Iterator):
    comptime Element = Int  # Required by the Iterator trait

    var index: Int
    var src: Pointer[SparseSet[Self.fixed_size], Self.origin]

    def __has_next__(self) -> Bool:
        return self.index < len(self.src[])

    def __next__(mut self) -> Int:
        var val = self.src[]._dense[self.index]
        self.index += 1
        return val


struct SparseSet[
    fixed_size: Int,
](Boolable, Defaultable, Iterable, Sized):
    var _sparse: InlineArray[Int, Self.fixed_size]
    # storage the index of dense array
    var _dense: List[Int]
    # storage the keys

    # for __iter__ __next__ using
    comptime IteratorType[
        iterable_mut: Bool, //, iterable_origin: Origin[mut=iterable_mut]
    ]: Iterator = _SparseSetIter[Self.fixed_size, iterable_origin]

    def __iter__(ref self) -> Self.IteratorType[origin_of(self)]:
        return {0, Pointer(to=self)}

    def __init__(out self):
        self._sparse = InlineArray[Int, Self.fixed_size](fill=-1)
        self._dense = List[Int]()

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
        if not self.contains(key):
            return

        index = self._sparse[key]
        last_key = self._dense[-1]

        # 將末端元素移動至被刪除的位置
        self._dense[index] = last_key

        # 同步更新被移動元素的稀疏映射
        self._sparse[last_key] = index

        # 清除被刪除元素的舊映射並縮減密集陣列
        self._sparse[key] = -1
        _ = self._dense.pop()




def main():
    var my_set = SparseSet[32]()
    my_set.add(5)
    my_set.add(31)
    my_set.add(4)
    my_set.add(0)
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
