"""Run the RP2350 PIO + dual-core proof and gate it.

Companion to tests/on_target_rp2350/pio_multicore.mojo (see its pair
map). Same automated loop as the benchmark: UF2 flash, firmware commits
to the flash mailbox and reboots to BOOTSEL, host reads over PICOBOOT.

Hard gates:
  - core 1 launch handshake and FIFO reply both succeeded
  - core 1's value (FIFO path AND volatile-RAM path) equals the
    host-recomputed 1000-round xorshift32
  - PIO0 and PIO2 square waves each produced >= 6 observed edges on
    GPIO15's input path

Usage: pixi run piomc-rp2350   (Pico 2 in BOOTSEL)
"""

from std.time import sleep

import bench_rp2350 as b2
import build as buildmod

comptime COUNT = 4
comptime MAGIC: UInt32 = 0x31434D50  # "PMC1"
comptime HDR = 5
comptime C1_SEED: UInt32 = 0x1357_2468


def build_fw() raises -> String:
    var elf = String("build/pio_multicore.elf")
    var prefix = buildmod.toolchain_prefix()
    b2._shared_objs()
    _ = buildmod.shx(
        prefix + "/bin/mojo build --emit=object"
        + " --target-triple=riscv32-unknown-none-elf"
        + " --target-features=+m,+a,+c"
        + " -I " + prefix + "/lib/mojo -I src"
        + " -o build/pio_multicore.o tests/on_target_rp2350/pio_multicore.mojo"
    )
    b2._link(String("build/pio_multicore.o"), elf)
    return elf^


def flash_and_read(elf: String) raises -> List[UInt32]:
    _ = buildmod.sh(
        String("picotool uf2 convert ") + elf
        + " /tmp/piomc.uf2 --family rp2350-riscv"
    )
    var waited = 0
    while not b2._mounted():
        waited += 1
        if waited > 30:
            raise Error("no BOOTSEL drive after 60 s")
        sleep(2.0)
    _ = buildmod.sh(String("cp /tmp/piomc.uf2 ") + b2.MOUNT + "/")
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


def _expected() -> UInt32:
    var x = C1_SEED
    for _ in range(1000):
        x ^= x << 13
        x ^= x >> 17
        x ^= x << 5
    return x


def main() raises:
    print("building pio_multicore firmware...")
    var elf = build_fw()
    print("running on target...")
    var flat = flash_and_read(elf)

    var launch_ok = flat[0]
    var fifo_ok = flat[1]
    var fifo_val = flat[2]
    var ram_val = flat[3]
    var pio0_edges = flat[4]
    var pio0_pass = flat[5]
    var pio2_edges = flat[6]
    var pio2_pass = flat[7]

    var want = _expected()
    print(
        "core1: launch=" + String(Int(launch_ok)) + " fifo_ok="
        + String(Int(fifo_ok)) + " fifo_val=" + String(Int(fifo_val))
        + " ram_val=" + String(Int(ram_val)) + " expected="
        + String(Int(want))
    )
    print(
        "pio0: " + String(Int(pio0_edges)) + " edges   pio2: "
        + String(Int(pio2_edges)) + " edges (>=6 required)"
    )

    if launch_ok != 1 or fifo_ok != 1:
        raise Error("core 1 launch/FIFO handshake failed")
    if fifo_val != want or ram_val != want:
        raise Error("core 1 result mismatch")
    if pio0_pass != 1:
        raise Error("PIO0 square wave not observed on GPIO15")
    if pio2_pass != 1:
        raise Error("PIO2 square wave not observed on GPIO15")
    print()
    print(
        "gates: dual-core launch + FIFO + RAM result, PIO0 and PIO2"
        + " electrical read-back all verified"
    )
