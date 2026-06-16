from harness.runner import Suite
from ecs.world import World
from ecs.sparse_backend import SparseSetBackend
from ecs.component import ComponentType
from ecs.entity import Entity


@fieldwise_init
struct Position(ComponentType):
    comptime ID: Int = 0
    var x: Int
    var y: Int


@fieldwise_init
struct Velocity(ComponentType):
    comptime ID: Int = 1
    var dx: Int
    var dy: Int


@fieldwise_init
struct Frozen(ComponentType):
    comptime ID: Int = 2
    var flag: Int


def _has(es: List[Entity], e: Entity) -> Bool:
    for i in range(len(es)):
        if es[i] == e:
            return True
    return False


def main() raises:
    var s = Suite("query")
    var w = World[SparseSetBackend[Position, Velocity, Frozen]]()

    var moving = w.spawn2(Position(0, 0), Velocity(1, 1))  # P + V
    var still = w.spawn1(Position(5, 5))  # P only
    var ghost = w.spawn1(Velocity(2, 2))  # V only
    var frozen = w.spawn2(Position(1, 1), Velocity(0, 0))  # P + V
    w.set(frozen, Frozen(1))  # P + V + F

    var with_p = w.query1[Position]()
    s.eqi(len(with_p), 3, "3 have Position")
    s.check(_has(with_p, moving) and _has(with_p, still) and _has(with_p, frozen), "right P set")

    var pv = w.query2[Position, Velocity]()
    s.eqi(len(pv), 2, "2 have Position+Velocity")
    s.check(_has(pv, moving) and _has(pv, frozen), "moving+frozen have P+V")
    s.check(not _has(pv, still) and not _has(pv, ghost), "still/ghost excluded")

    var pvf = w.query3[Position, Velocity, Frozen]()
    s.eqi(len(pvf), 1, "1 has all three")
    s.check(_has(pvf, frozen), "only frozen has P+V+F")

    # mutate via query: a movement system
    var movers = w.query2[Position, Velocity]()
    for i in range(len(movers)):
        var e = movers[i]
        var p = w.get[Position](e)
        var v = w.get[Velocity](e)
        w.set(e, Position(p.x + v.dx, p.y + v.dy))
    s.eqi(w.get[Position](moving).x, 1, "moving stepped +1")
    s.eqi(w.get[Position](frozen).x, 1, "frozen velocity 0 -> unchanged")
    s.eqi(w.get[Position](still).x, 5, "still not in query -> unchanged")

    s.finish()
