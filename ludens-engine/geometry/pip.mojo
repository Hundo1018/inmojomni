"""Point-in-polygon tests for 2D polygons.

Two classic methods, both taking a `Polygon` (vertices in order; the edge from
the last vertex back to the first is implicit):

  * `point_in_polygon` — ray-casting crossing-number. Cast a +x ray from the
    point and count edge crossings; an odd count means inside. Works for any
    simple polygon, convex or concave.
  * `winding_number` — signed turns of the polygon boundary around the point;
    a nonzero result means inside. Robust for self-overlapping polygons and the
    even-odd-vs-nonzero distinction (holes).

Edges are treated half-open so a point exactly on a horizontal edge does not get
double-counted. Reductions/SIMD lanes go through scalar lane access (`v[0]`,
`v[1]`); width-2 vectors are safe here.
"""

from .vec import WorldType, Real, Vec2
from .shape import Polygon


def point_in_polygon(p: Vec2, poly: Polygon) -> Bool:
    """Crossing-number ray cast along +x. Odd number of crossings => inside."""
    var n = len(poly.verts)
    if n < 3:
        return False
    var inside = False
    var j = n - 1
    for i in range(n):
        var vi = poly.verts[i]
        var vj = poly.verts[j]
        # Does the horizontal ray at y = p[1] straddle edge (vj -> vi)?
        var straddles = (vi[1] > p[1]) != (vj[1] > p[1])
        if straddles:
            # x of the intersection of the edge with the horizontal line y=p[1].
            var t = (p[1] - vi[1]) / (vj[1] - vi[1])
            var x_cross = vi[0] + t * (vj[0] - vi[0])
            if p[0] < x_cross:
                inside = not inside
        j = i
    return inside


def _is_left(a: Vec2, b: Vec2, p: Vec2) -> Real:
    """>0 if p is left of the directed line a->b, <0 right, 0 on the line."""
    return (b[0] - a[0]) * (p[1] - a[1]) - (p[0] - a[0]) * (b[1] - a[1])


def winding_number(p: Vec2, poly: Polygon) -> Int:
    """Signed winding number of the polygon boundary about `p` (0 = outside)."""
    var n = len(poly.verts)
    var wn = 0
    for i in range(n):
        var a = poly.verts[i]
        var b = poly.verts[(i + 1) % n]
        if a[1] <= p[1]:
            if b[1] > p[1]:  # an upward crossing
                if _is_left(a, b, p) > 0:  # p strictly left of the edge
                    wn += 1
        else:
            if b[1] <= p[1]:  # a downward crossing
                if _is_left(a, b, p) < 0:  # p strictly right of the edge
                    wn -= 1
    return wn
