"""Render the benchmark results as an SVG bar chart for the README.

Reads build/bench_results.csv (written by tools/bench.mojo after an
on-hardware run) and writes docs/assets/benchmarks.svg. Pure string
generation, no dependencies; the SVG uses a solid card background so it
reads identically on GitHub light and dark themes.

Usage: pixi run chart  [in.csv out.svg]
"""

from std.subprocess import run
from std.sys import argv

comptime LANGS = 4


# bar order within each group: Mojo first, then the same-backend C
# control, then the other LLVM language, then gcc.
def _bar_label(i: Int) -> String:
    if i == 0:
        return String("Mojo")
    if i == 1:
        return String("C (clang -O2)")
    if i == 2:
        return String("Rust (-O2)")
    return String("C (gcc -O2)")


def _bar_color(i: Int) -> String:
    if i == 0:
        return String("#F74C00")
    if i == 1:
        return String("#3E7CB1")
    if i == 2:
        return String("#DEA584")
    return String("#94A3B8")


# csv column order is mojo, gcc, clang, rust
def _csv_col(i: Int) -> Int:
    if i == 0:
        return 0
    if i == 1:
        return 2
    if i == 2:
        return 3
    return 1

comptime LEFT = 250  # label column
comptime AREA = 480  # bar area width
comptime BAR_H = 12
comptime BAR_GAP = 2
comptime GROUP_PAD = 14
comptime TOP = 78


def _ratio_str(permille: UInt64) -> String:
    var centi = (permille + 5) / 10
    var s = String(centi / 100) + "."
    var frac = Int(centi % 100)
    if frac < 10:
        s += "0"
    return s + String(frac)


@fieldwise_init
struct Row(Copyable, Movable):
    var desc: String
    var us: List[UInt64]  # per csv column: mojo, gcc, clang, rust


def _parse_csv(path: String) raises -> List[Row]:
    var text = open(path, "r").read()
    var rows = List[Row]()
    var first = True
    for line_s in text.split("\n"):
        var line = String(line_s)
        if first:
            first = False
            continue
        if line.byte_length() == 0:
            continue
        var cols = line.split(",")
        if len(cols) != 6:
            raise Error("malformed CSV row: " + line)
        var us = List[UInt64]()
        for i in range(2, 6):
            us.append(UInt64(Int(String(cols[i]))))
        rows.append(Row(String(cols[1]), us^))
    if len(rows) == 0:
        raise Error("no data rows in " + path)
    return rows^


def _rect(x: Int, y: Int, w: Int, h: Int, fill: String, extra: String) -> String:
    return (
        String('<rect x="') + String(x) + '" y="' + String(y)
        + '" width="' + String(w) + '" height="' + String(h)
        + '" fill="' + fill + '" ' + extra + "/>\n"
    )


def _text(
    x: Int, y: Int, size: Int, fill: String, anchor: String,
    weight: String, body: String,
) -> String:
    return (
        String('<text x="') + String(x) + '" y="' + String(y)
        + '" font-size="' + String(size) + '" fill="' + fill
        + '" text-anchor="' + anchor + '" font-weight="' + weight
        + '">' + body + "</text>\n"
    )


def render(rows: List[Row]) -> String:
    var group_h = LANGS * (BAR_H + BAR_GAP) + GROUP_PAD
    var height = TOP + len(rows) * group_h + 34
    var width = LEFT + AREA + 130

    # x scale: permille of clang time, capped by the global maximum
    var max_pm: UInt64 = 1000
    for row in rows:
        var clang = row.us[2]
        for c in range(LANGS):
            var pm = row.us[c] * 1000 / clang
            if pm > max_pm:
                max_pm = pm

    var s = String('<svg xmlns="http://www.w3.org/2000/svg" width="')
    s += String(width) + '" height="' + String(height)
    s += '" viewBox="0 0 ' + String(width) + " " + String(height) + '" '
    s += 'font-family="ui-sans-serif, system-ui, -apple-system, '
    s += "'Segoe UI', sans-serif\">\n"
    s += _rect(0, 0, width, height, String("#ffffff"),
               String('rx="8" stroke="#d0d7de"'))
    s += _text(20, 30, 16, String("#1f2328"), String("start"),
               String("600"),
               String("Execution time relative to C (clang -O2) "
                      + "&#8212; lower is better"))
    s += _text(20, 50, 12, String("#57606a"), String("start"),
               String("400"),
               String("RP2040 @ 12 MHz &#183; medians of 3 runs &#183; "
                      + "checksums verified across all four languages"))

    # legend, right-aligned on the title rows
    var lx = width - 20
    for li in range(LANGS):
        var i = LANGS - 1 - li
        var label = _bar_label(i)
        var lw = label.byte_length() * 7 + 26
        lx -= lw
        s += _rect(lx, 22, 10, 10, _bar_color(i), String('rx="2"'))
        s += _text(lx + 14, 31, 11, String("#57606a"), String("start"),
                   String("400"), label)

    var y = TOP
    for row in rows:
        var clang = row.us[2]
        s += _text(LEFT - 12, y + 2 * (BAR_H + BAR_GAP) + 4, 12,
                   String("#1f2328"), String("end"), String("400"),
                   row.desc)
        for b in range(LANGS):
            var v = row.us[_csv_col(b)]
            var pm = v * 1000 / clang
            var w = Int(pm * UInt64(AREA) / max_pm)
            if w < 2:
                w = 2
            var by = y + b * (BAR_H + BAR_GAP)
            s += _rect(LEFT, by, w, BAR_H, _bar_color(b),
                       String('rx="2"'))
            s += _text(LEFT + w + 6, by + BAR_H - 2, 10,
                       String("#57606a"), String("start"), String("400"),
                       _ratio_str(pm) + "&#215;")
        y += group_h

    # baseline at 1.0x
    var x1 = LEFT + Int(UInt64(1000) * UInt64(AREA) / max_pm)
    s += (
        String('<line x1="') + String(x1) + '" y1="' + String(TOP - 8)
        + '" x2="' + String(x1) + '" y2="' + String(y - GROUP_PAD + 6)
        + '" stroke="#d0d7de" stroke-dasharray="3,3"/>\n'
    )
    s += _text(x1, TOP - 14, 10, String("#8b949e"), String("middle"),
               String("400"), String("1.00&#215; (clang)"))
    s += _text(20, height - 14, 10, String("#8b949e"), String("start"),
               String("400"),
               String("Generated by `pixi run chart` from "
                      + "build/bench_results.csv"))
    s += "</svg>\n"
    return s^


def main() raises:
    var in_csv = String("build/bench_results.csv")
    var out_svg = String("docs/assets/benchmarks.svg")
    var args = argv()
    if len(args) == 3:
        in_csv = String(args[1])
        out_svg = String(args[2])
    var rows = _parse_csv(in_csv)
    _ = run("mkdir -p docs/assets")
    var f = open(out_svg, "w")
    f.write(render(rows))
    f.close()
    print("wrote", out_svg, "(", len(rows), "workloads )")
