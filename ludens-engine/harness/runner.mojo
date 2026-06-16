"""A tiny test harness for ludens-engine.

This nightly has no `mojo test` command and no `testing` stdlib module, so each
test file is a normal program: build a `Suite`, run checks, then call `finish()`.
`finish()` raises on any failure, giving a non-zero exit so a `&&`-chained pixi
`test` task stops at the first failing file.

Usage:
    from ludens_testing.runner import Suite

    def main() raises:
        var s = Suite("my_module")
        s.check(1 + 1 == 2, "arithmetic")
        s.eq(2 + 2, 4, "addition")
        s.finish()
"""


struct Suite(Movable):
    var name: String
    var passed: Int
    var failed: Int

    def __init__(out self, name: String):
        self.name = name
        self.passed = 0
        self.failed = 0

    def check(mut self, cond: Bool, label: String):
        if cond:
            self.passed += 1
        else:
            self.failed += 1
            print("  [FAIL]", self.name, "-", label)

    def eqi(mut self, got: Int, want: Int, label: String):
        if got == want:
            self.passed += 1
        else:
            self.failed += 1
            print(
                "  [FAIL]",
                self.name,
                "-",
                label,
                "(got",
                String(got),
                "want",
                String(want),
                ")",
            )

    def almost(
        mut self,
        got: Float64,
        want: Float64,
        label: String,
        tol: Float64 = 1e-5,
    ):
        var d = got - want
        if d < 0:
            d = -d
        self.check(d <= tol, label + " (got " + String(got) + " want " + String(want) + ")")

    def finish(self) raises:
        var total = self.passed + self.failed
        if self.failed == 0:
            print("[PASS]", self.name, "-", String(self.passed), "/", String(total), "checks")
        else:
            print("[FAIL]", self.name, "-", String(self.failed), "of", String(total), "checks failed")
            raise Error("test suite failed: " + self.name)
