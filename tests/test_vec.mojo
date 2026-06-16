from harness.runner import Suite
from geometry.vec import Vec2, Vec3, dot, length, length_sq, normalize, lane_min, lane_max


def main() raises:
    var s = Suite("vec")

    var a = Vec2(3, 4)
    s.almost(Float64(length_sq(a)), 25.0, "len_sq 3-4")
    s.almost(Float64(length(a)), 5.0, "length 3-4-5")
    s.almost(Float64(dot(Vec2(1, 0), Vec2(0, 1))), 0.0, "perp dot")
    s.almost(Float64(dot(Vec2(2, 3), Vec2(4, 5))), 23.0, "dot 2x3 . 4x5")

    # width-3: manual reduction must NOT drop the 3rd lane (1+4+4 = 9 -> 3)
    var b = Vec3(1, 2, 2)
    s.almost(Float64(length(b)), 3.0, "vec3 length width-3")
    s.almost(Float64(length_sq(Vec3(2, 3, 6))), 49.0, "vec3 len_sq")

    var n = normalize(Vec2(0, 8))
    s.almost(Float64(n[1]), 1.0, "normalize y")
    s.almost(Float64(length(n)), 1.0, "normalized length")

    var mn = lane_min(Vec3(1, 5, 3), Vec3(4, 2, 9))
    s.almost(Float64(mn[0]), 1.0, "lane_min x")
    s.almost(Float64(mn[1]), 2.0, "lane_min y")
    var mx = lane_max(Vec3(1, 5, 3), Vec3(4, 2, 9))
    s.almost(Float64(mx[2]), 9.0, "lane_max z")

    s.finish()
