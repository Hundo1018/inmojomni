from std.runtime.asyncrt import create_task


async def co_sub(a: Int) -> Int:
    print(a)
    return a


async def co_func() -> Int:
    res = 0

    # without comptime for, it will crash when using F5 / mojo run --no-optimization ./repro.mojo
    comptime for i in range(2):
        res += await co_sub(i)
    return res


comptime BaseTraits = Copyable


@fieldwise_init
struct Wrapper[T: BaseTraits](Writable where conforms_to(T, Writable)):
    var value: Self.T


@explicit_destroy
trait Consumable:
    def consume(deinit self):
        ...


@explicit_destroy
trait Fallbackable:
    def fallback(deinit self):
        pass


@explicit_destroy("Must call consume() or fallback()")
@fieldwise_init
struct TransactionModel(Consumable, Fallbackable):
    def consume(deinit self):
        print("consume")


@fieldwise_init
struct NotWritable[T: BaseTraits](
    ImplicitlyDestructible where not conforms_to(T, ImplicitlyDestructible)
):
    def fallback(deinit self):
        pass


def main():
    var model: TransactionModel = TransactionModel()
    model^.consume()
    # or model^.fallback()
    print("done")
    # var task = create_task(co_func())
    # _ = task.wait()
    var w_int = Wrapper[Int](1)
    print(w_int)

    var w_str = Wrapper[String]("Hello")
    print(w_str)

    var w_not_writable = NotWritable[Int]()
    print(w_not_writable)
