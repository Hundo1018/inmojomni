from ludens_engine.sparse_set import SparseSet


fn test_add_is_idempotent() raises:
    var sparse_set = SparseSet[8]()

    sparse_set.add(3)
    sparse_set.add(3)

    assert sparse_set.len() == 1
    assert sparse_set.contains(3)


fn test_remove_keeps_swapped_value_queryable() raises:
    var sparse_set = SparseSet[8]()
    sparse_set.add(2)
    sparse_set.add(1)
    sparse_set.add(3)

    sparse_set.remove(1)

    assert not sparse_set.contains(1)
    assert sparse_set.contains(2)
    assert sparse_set.contains(3)
    assert sparse_set.len() == 2


fn test_invalid_keys_are_ignored() raises:
    var sparse_set = SparseSet[4]()

    sparse_set.add(-1)
    sparse_set.add(4)
    sparse_set.remove(6)

    assert sparse_set.len() == 0


fn main() raises:
    test_add_is_idempotent()
    test_remove_keeps_swapped_value_queryable()
    test_invalid_keys_are_ignored()
