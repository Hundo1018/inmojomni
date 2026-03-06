from collections import List
struct SparseSet[fixed_size: Int,//,*keys:Int](Sized, Boolable,ImplicitlyCopyable):
    comptime _fixed_size: Int = Self.fixed_size
    comptime _list  = VariadicParamList(Self.keys)

    var _sparse: List[Int]
    #storage the index of dense array
    var _dense: List[Int]
    #storage the keys

    var _current: Int
    #for __iter__ __next__ using

    fn __init__(out self) :
        self._sparse = List[Int](capacity=Self._fixed_size)
        self._dense = List[Int]()

        self._current = -1
        for i in range(Self._fixed_size):
            self._sparse[i] = -1
        for i in range(len(Self._list)):
            self.add(self._list[i])
    fn __len__(self) -> Int:
        return len(self._dense)

    fn __bool__(self) -> Bool:
        return len(self) > 0

    fn add(mut self, key: Int) -> None:
        #Add a key into set.
        if self.contains(key):
            return
        #makesure the number does not exist.
        self._sparse[key] = len(self._dense)
        #update sparse array
        self._dense.append(key)
        #update dense array

    fn contains(read self, key: Int) -> Bool:
        #Check the key whether or not in the set.
        index = self._sparse[key]
        return index >= 0 and self._dense[index] == key

    fn remove(mut self, key: Int):
        #Remove the key from the set.
        if not self.contains(key):
            return
        index = self._sparse[key]
        self._sparse[key] = -1
        #remove map from sparse to dense

        self._dense[index] = self._dense[-1]
        _ = self._dense.pop()
        #remove the last index of dense

    fn __copyinit__(out self, copy: Self):
        #Implement for __iter__.
        self = Self()
        for i in self._dense:
            self.add(i)

    fn __iter__(ref self) -> Self:
        return self

    fn __next__(mut self) -> Int:
        self._current += 1
        return self._dense[self._current]

    fn __has_next__(self) -> Bool:
        return self._current < len(self._dense) - 1


fn main():
    var my_set = SparseSet[fixed_size=4,2,1]()
    
    for element in my_set:
        print(element)