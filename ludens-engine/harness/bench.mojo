"""A tiny benchmarking harness: collect timed rows, render a Markdown table.

Callers time their own workloads with `perf_counter_ns` (and `keep()` from
`std.benchmark` to stop the optimizer deleting the work), then record a row with
`BenchTable.add(...)`. `BenchTable.report()` produces a GitHub-flavored Markdown
table — readable in a terminal and writable to a report file with `save()`.

This pairs with `harness.runner.Suite`: tests assert correctness, benchmarks
record timings. There is no `mojo test`/bench CLI in this nightly, so bench files
are plain programs run with `mojo run -I build`.
"""

from std.time import perf_counter_ns


def now() -> Int:
    """Monotonic timestamp in nanoseconds as an `Int` (perf_counter returns UInt)."""
    return Int(perf_counter_ns())


def _fmt2(x: Float64) -> String:
    """Round to two decimals as a string (no float formatting in this nightly)."""
    var neg = x < 0
    var v = -x if neg else x
    var scaled = Int(v * 100.0 + 0.5)
    var whole = scaled // 100
    var frac = scaled % 100
    var fs = String(frac)
    if frac < 10:
        fs = "0" + fs
    var sign = "-" if neg else ""
    return sign + String(whole) + "." + fs


def _round_i(x: Float64) -> String:
    return String(Int(x + 0.5))


@fieldwise_init
struct BenchRow(Copyable, Movable):
    var variant: String
    var n: Int
    var op: String
    var total_ns: Int
    var iters: Int

    def ns_per_op(self) -> Float64:
        if self.iters == 0:
            return 0
        return Float64(self.total_ns) / Float64(self.iters)

    def mops(self) -> Float64:
        var npo = self.ns_per_op()
        if npo == 0:
            return 0
        return 1000.0 / npo  # ops per ns * 1e9 / 1e6 = Mops/s


struct BenchTable(Movable):
    var title: String
    var rows: List[BenchRow]

    def __init__(out self, var title: String):
        self.title = title^
        self.rows = List[BenchRow]()

    def add(
        mut self,
        variant: String,
        n: Int,
        op: String,
        total_ns: Int,
        iters: Int,
    ):
        self.rows.append(BenchRow(variant, n, op, total_ns, iters))

    def report(self) -> String:
        var out = String("### ") + self.title + "\n\n"
        out += "| variant | N | op | ns/op | Mops/s | total ms |\n"
        out += "|---|---:|---|---:|---:|---:|\n"
        for ref r in self.rows:
            out += "| " + r.variant + " | " + String(r.n) + " | " + r.op
            out += " | " + _round_i(r.ns_per_op())
            out += " | " + _fmt2(r.mops())
            out += " | " + _fmt2(Float64(r.total_ns) / 1.0e6) + " |\n"
        out += "\n"
        return out^

    def print_report(self):
        print(self.report())
