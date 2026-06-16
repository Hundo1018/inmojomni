from harness.runner import Suite
from ecs.sparse_set import SparseSet


def main() raises:
    var s = Suite("sparse_set")

    var set = SparseSet[Int, 32]()
    set.add(5, 50)
    set.add(31, 310)
    set.add(4, 40)
    set.add(0, 0)
    s.eqi(len(set), 4, "len after 4 adds")
    s.check(set.contains(5), "contains 5")
    s.check(not set.contains(7), "not contains 7")
    s.eqi(set.get(31), 310, "get 31")

    # add ignores duplicate; set overwrites
    set.add(5, 999)
    s.eqi(set.get(5), 50, "add keeps existing")
    set.set(5, 999)
    s.eqi(set.get(5), 999, "set overwrites")
    set.set(10, 100)  # set inserts new
    s.eqi(set.get(10), 100, "set inserts")
    s.eqi(len(set), 5, "len after set-insert")

    # remove middle keeps others intact
    set.remove(31)
    s.check(not set.contains(31), "31 removed")
    s.check(set.contains(4) and set.contains(0) and set.contains(5), "others intact")
    s.eqi(len(set), 4, "len after remove")

    # iterate yields all current values
    var total = 0
    for v in set:
        total += v
    s.eqi(total, 999 + 40 + 0 + 100, "iterate sum")

    set.remove(5)
    set.remove(4)
    set.remove(0)
    set.remove(10)
    s.eqi(len(set), 0, "empty after removing all")
    s.check(not set, "boolable false when empty")

    s.finish()
