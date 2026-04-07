#!/usr/bin/env bash
set -euo pipefail

# Run shape rendering repeatedly and verify border invariants.
RUNS="${1:-40}"
OUT_DIR="/tmp/inmojomni-render-check"
mkdir -p "$OUT_DIR"

for i in $(seq 1 "$RUNS"); do
  pixi run mojo run moth/shape.mojo > "$OUT_DIR/out_$i.txt"
done

python3 tests/geometry_consistency_check.py

python3 - <<'PY'
import glob
import re
import sys

ansi = re.compile(r'\x1b\[[0-9;]*m')
out_files = sorted(glob.glob('/tmp/inmojomni-render-check/out_*.txt'))

ok = True
for p in out_files:
    raw = open(p, 'rb').read().decode('utf-8', 'replace')
    all_lines = [ansi.sub('', ln.rstrip('\n')) for ln in raw.splitlines()]
    all_lines = [ln for ln in all_lines if ln != '']

    top_idx = -1
    bot_idx = -1
    for i, ln in enumerate(all_lines):
        if ln.startswith('┌') and ln.endswith('┐'):
            top_idx = i
            break
    if top_idx >= 0:
        for i in range(len(all_lines) - 1, top_idx, -1):
            ln = all_lines[i]
            if ln.startswith('└') and ln.endswith('┘'):
                bot_idx = i
                break

    if top_idx < 0 or bot_idx < 0 or bot_idx <= top_idx:
        print('FAIL cannot locate frame block:', p)
        ok = False
        continue

    lines = all_lines[top_idx : bot_idx + 1]
    legend_lines = all_lines[bot_idx + 1 :]

    if not lines:
        print('FAIL empty output:', p)
        ok = False
        continue

    w = len(lines[0])
    if any(len(ln) != w for ln in lines):
        print('FAIL ragged width:', p)
        ok = False

    if lines[0][0] != '┌' or lines[0][-1] != '┐':
        print('FAIL top corner mismatch:', p)
        ok = False

    if lines[-1][0] != '└' or lines[-1][-1] != '┘':
        print('FAIL bottom corner mismatch:', p)
        ok = False

    if any(ch != '─' for ch in lines[0][1:-1]):
        print('FAIL top border mismatch:', p)
        ok = False

    if any(ch != '─' for ch in lines[-1][1:-1]):
        print('FAIL bottom border mismatch:', p)
        ok = False

    for ln in lines[1:-1]:
        if ln[0] != '│' or ln[-1] != '│':
            print('FAIL side border mismatch:', p)
            ok = False

    # Axis sanity: for current scene bounds in moth/shape.mojo,
    # origin should map to (x=21, y=11) inside the frame.
    if len(lines) <= 11 or len(lines[0]) <= 21:
        print('FAIL canvas too small for axis check:', p)
        ok = False
    else:
        c = lines[11][21]
        if c not in {'┼', '├', '┤', '┬', '┴', '│', '─'}:
            print('FAIL missing center axis marker:', p, 'found=', repr(c))
            ok = False

    legend_text = '\n'.join(legend_lines)
    if 'x-scale (unit=1): -20 -15 -10 -5 0 5 10 15 20' not in legend_text:
        print('FAIL missing x-scale legend:', p)
        ok = False
    if 'y-scale (unit=1): -10 -5 0 5 10' not in legend_text:
        print('FAIL missing y-scale legend:', p)
        ok = False

    m = re.search(r'shape-size: rect=(\d+)x(\d+), circle-r=(\d+), tri-size=(\d+)', legend_text)
    if not m:
        print('FAIL missing shape-size legend:', p)
        ok = False
    else:
        rw, rh, cr, ts = map(int, m.groups())
        if not (4 <= rw <= 10 and 3 <= rh <= 7 and 2 <= cr <= 4 and 2 <= ts <= 5):
            print('FAIL shape-size out of expected range:', p, rw, rh, cr, ts)
            ok = False

if not ok:
    sys.exit(1)

print('PASS render regression checks for', len(out_files), 'runs')
PY
