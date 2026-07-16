"""Run the Mojo language-feature measurements on a Pico 2 and gate them.

Companion to tests/on_target_rp2350/mojo_features.mojo — see its
docstring for the pair map. Builds with the same flags/startup as the
benchmark suite, flashes over the automated UF2 -> flash-mailbox ->
PICOBOOT loop (no probe, no button), then:

  gates (hard failures):
    - trait-generic and direct checksums identical
    - comptime-LUT and runtime-compute checksums identical
    - comptime-for-unrolled and rolled checksums identical
    - @no_inline and @always_inline checksums identical
    - size_of(S4/S8/S12) == 4/8/12
  findings (reported, not asserted): cycle counts, per-call costs and
  the struct-passing boundary curve.

Usage: pixi run features-rp2350   (Pico 2 in BOOTSEL)
"""

from std.time import sleep

import bench_rp2350 as b2
import build as buildmod

comptime COUNT = 16
comptime MAGIC: UInt32 = 0x54414546  # "FEAT"
comptime HDR = 5


def build_features() raises -> String:
    var elf = String("build/mojo_features.elf")
    var prefix = buildmod.toolchain_prefix()
    b2._shared_objs()
    _ = buildmod.shx(
        prefix + "/bin/mojo build --emit=object"
        + " --target-triple=riscv32-unknown-none-elf"
        + " --target-features=+m,+a,+c"
        + " -I " + prefix + "/lib/mojo -I src"
        + " -o build/mojo_features.o tests/on_target_rp2350/mojo_features.mojo"
    )
    b2._link(String("build/mojo_features.o"), elf)
    return elf^


def flash_and_read(elf: String) raises -> List[UInt32]:
    _ = buildmod.sh(
        String("picotool uf2 convert ") + elf
        + " /tmp/features.uf2 --family rp2350-riscv"
    )
    var waited = 0
    while not b2._mounted():
        waited += 1
        if waited > 30:
            raise Error("no BOOTSEL drive after 60 s")
        sleep(2.0)
    _ = buildmod.sh(String("cp /tmp/features.uf2 ") + b2.MOUNT + "/")
    _ = buildmod.sh("sync 2>/dev/null || true")
    var gone = False
    for _ in range(30):
        sleep(2.0)
        if not b2._mounted():
            gone = True
            break
    if not gone:
        raise Error("device never left BOOTSEL (UF2 not consumed?)")
    for _ in range(60):
        if b2._mounted():
            break
        sleep(2.0)
    if not b2._mounted():
        raise Error("device never returned to BOOTSEL (firmware hung?)")
    sleep(1.0)
    var words = HDR + COUNT * 2
    var out = buildmod.sh(
        String("python3 tools/picoboot_read.py 0x103ff000 ")
        + String(words) + " --dec"
    )
    var flat = List[UInt32]()
    for piece in String(out.strip()).split(" "):
        flat.append(UInt32(Int(String(piece))))
    if flat[0] != MAGIC:
        raise Error("bad mailbox magic (stale page?)")
    if flat[1] != 2:
        raise Error("firmware did not reach done state")
    if flat[2] != COUNT:
        raise Error("count mismatch — stale firmware?")
    var body = List[UInt32]()
    for i in range(COUNT * 2):
        body.append(flat[HDR + i])
    return body^


def _pair(flat: List[UInt32], idx: Int) -> Tuple[UInt32, UInt32]:
    return (flat[idx * 2], flat[idx * 2 + 1])


def _row(name: String, cyc: UInt32, note: String):
    print(
        b2._lj(name, 34) + b2._rj(String(Int(cyc)), 10)
        + b2._rj(b2._ratio2(cyc, 10_000), 10) + "  " + note
    )


def main() raises:
    print("building mojo_features firmware...")
    var elf = build_features()
    print("running on target...")
    var flat = flash_and_read(elf)

    var trait_p = _pair(flat, 0)
    var direct_p = _pair(flat, 1)
    var sz_a = _pair(flat, 2)
    var sz_b = _pair(flat, 3)
    var lut_p = _pair(flat, 4)
    var calc_p = _pair(flat, 5)
    var unr_p = _pair(flat, 6)
    var rol_p = _pair(flat, 7)
    var ni_p = _pair(flat, 8)
    var ai_p = _pair(flat, 9)

    # --- hard gates -------------------------------------------------
    if trait_p[1] != direct_p[1]:
        raise Error("trait vs direct: checksum mismatch")
    if lut_p[1] != calc_p[1]:
        raise Error("comptime LUT vs runtime compute: checksum mismatch")
    if unr_p[1] != rol_p[1]:
        raise Error("unrolled vs rolled: checksum mismatch")
    if ni_p[1] != ai_p[1]:
        raise Error("no_inline vs always_inline: checksum mismatch")
    if sz_a[0] != 4 or sz_a[1] != 8 or sz_b[0] != 12:
        raise Error("size_of(S4/S8/S12) != 4/8/12")

    print()
    print(
        b2._lj(String("feature (10k iterations)"), 34)
        + b2._rj(String("cycles"), 10) + b2._rj(String("cyc/iter"), 10)
    )
    _row(String("trait-generic call"), trait_p[0], String(""))
    _row(String("direct call"), direct_p[0], String("checksums equal"))
    _row(String("comptime LUT"), lut_p[0], String(""))
    _row(String("runtime compute"), calc_p[0], String("checksums equal"))
    _row(String("comptime for (unrolled x16)"), unr_p[0], String(""))
    _row(String("plain for (x16)"), rol_p[0], String("checksums equal"))
    _row(String("@no_inline call"), ni_p[0], String(""))
    _row(String("@always_inline call"), ai_p[0], String("checksums equal"))
    print()
    print(
        "struct sizes: S4=" + String(Int(sz_a[0])) + " S8="
        + String(Int(sz_a[1])) + " S12=" + String(Int(sz_b[0]))
        + " S13{3xu32,u8}=" + String(Int(sz_b[1]))
    )
    print()
    print("struct-passing boundary (by-value through @no_inline):")
    var names = List[String]()
    names.append(String("R8 TrivialRegisterPassable 8B"))
    names.append(String("S8 memory struct 8B"))
    names.append(String("S16 memory struct 16B"))
    names.append(String("S32 memory struct 32B"))
    names.append(String("S64 memory struct 64B"))
    names.append(String("return S16 by value"))
    for i in range(6):
        var p = _pair(flat, 10 + i)
        _row(names[i], p[0], String(""))
    print()
    print("gates: all checksums and struct sizes verified")
