# Self-test for the test harness.
# Run: pixi run mojo precompile ludens-engine/harness -o build/harness.mojopkg
#      pixi run mojo run -I build tests/test_harness.mojo
from harness.runner import Suite


def main() raises:
    var s = Suite("harness")
    s.check(True, "check true")
    s.eqi(2 + 2, 4, "int eq")
    s.check(String("a") + "b" == String("ab"), "string eq")
    s.almost(0.1 + 0.2, 0.3, "float almost")
    s.finish()
