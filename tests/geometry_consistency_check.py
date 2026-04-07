#!/usr/bin/env python3
"""Validate that axis tick spec and shape-size generation are consistent."""

from __future__ import annotations

X_MIN, X_MAX = -20, 20
Y_MIN, Y_MAX = -10, 10
X_STEP = 5
Y_STEP = 5


def lcg_next(seed: int) -> int:
    return (seed * 1103515245 + 12345) % 2147483648


def next_range(seed: int, lo: int, hi: int) -> tuple[int, int]:
    if hi <= lo:
        return lo, seed
    seed = lcg_next(seed)
    return lo + (seed % (hi - lo + 1)), seed


def gen_once(seed: int) -> tuple[bool, str]:
    # rectangle
    rect_w, seed = next_range(seed, 4, 10)
    rect_h, seed = next_range(seed, 3, 7)
    hw = rect_w // 2
    hh = rect_h // 2
    rect_x, seed = next_range(seed, X_MIN + hw, X_MAX - hw)
    rect_y, seed = next_range(seed, Y_MIN + hh, Y_MAX - hh)

    # circle
    circle_r, seed = next_range(seed, 2, 4)
    circle_x, seed = next_range(seed, X_MIN + circle_r, X_MAX - circle_r)
    circle_y, seed = next_range(seed, Y_MIN + circle_r, Y_MAX - circle_r)

    # triangle
    tri_s, seed = next_range(seed, 2, 5)
    tri_x, seed = next_range(seed, X_MIN + tri_s, X_MAX - tri_s)
    tri_y, seed = next_range(seed, Y_MIN + tri_s, Y_MAX - tri_s)

    rect_ok = (
        rect_x - hw >= X_MIN and rect_x + hw <= X_MAX and rect_y - hh >= Y_MIN and rect_y + hh <= Y_MAX
    )
    circle_ok = (
        circle_x - circle_r >= X_MIN and circle_x + circle_r <= X_MAX and circle_y - circle_r >= Y_MIN and circle_y + circle_r <= Y_MAX
    )
    tri_ok = (
        tri_x - tri_s >= X_MIN and tri_x + tri_s <= X_MAX and tri_y - tri_s >= Y_MIN and tri_y + tri_s <= Y_MAX
    )

    if not rect_ok:
        return False, 'rectangle out of bounds'
    if not circle_ok:
        return False, 'circle out of bounds'
    if not tri_ok:
        return False, 'triangle out of bounds'

    # Axis tick numbers should include min, max, and 0 with constant spacing.
    x_ticks = list(range(X_MIN, X_MAX + 1, X_STEP))
    y_ticks = list(range(Y_MIN, Y_MAX + 1, Y_STEP))

    if x_ticks[0] != X_MIN or x_ticks[-1] != X_MAX or 0 not in x_ticks:
        return False, 'x-axis ticks mismatch'
    if y_ticks[0] != Y_MIN or y_ticks[-1] != Y_MAX or 0 not in y_ticks:
        return False, 'y-axis ticks mismatch'

    if any((b - a) != X_STEP for a, b in zip(x_ticks, x_ticks[1:])):
        return False, 'x-axis step mismatch'
    if any((b - a) != Y_STEP for a, b in zip(y_ticks, y_ticks[1:])):
        return False, 'y-axis step mismatch'

    return True, 'ok'


def main() -> int:
    for s in range(1, 501):
        ok, msg = gen_once(s)
        if not ok:
            print(f'FAIL seed={s}: {msg}')
            return 1
    print('PASS geometry consistency for 500 seeds')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
