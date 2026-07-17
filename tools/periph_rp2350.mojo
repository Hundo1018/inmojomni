"""Run the RP2350 peripheral proofs (TIMER/PWM/ADC/UART) and gate them.

Companion to tests/on_target_rp2350/peripherals.mojo (see its pair map).
Same automated loop as the benchmark: UF2 flash, flash mailbox,
PICOBOOT readback.

Hard gates:
  - hardware timer runs at 1 µs: mcycle/timer ratio == 12.00 ±2%
    (clk_sys = 12 MHz XOSC after time.init, so the ratio is exact)
  - PWM slice counter is running and stays within TOP
  - die temperature between 5°C and 60°C
  - UART internal loopback echoes 0xA5 then 0x3C
  - sleep_us(10_000) costs 120_000 mcycles ±2%

Usage: pixi run periph-rp2350   (Pico 2 in BOOTSEL)
"""

from std.time import sleep

import bench_rp2350 as b2
import build as buildmod

comptime COUNT = 5
comptime MAGIC: UInt32 = 0x31524550  # "PER1"
comptime HDR = 5


def build_fw() raises -> String:
    var elf = String("build/peripherals.elf")
    var prefix = buildmod.toolchain_prefix()
    b2._shared_objs()
    _ = buildmod.shx(
        prefix + "/bin/mojo build --emit=object"
        + " --target-triple=riscv32-unknown-none-elf"
        + " --target-features=+m,+a,+c"
        + " -I " + prefix + "/lib/mojo -I src"
        + " -o build/peripherals.o tests/on_target_rp2350/peripherals.mojo"
    )
    b2._link(String("build/peripherals.o"), elf)
    return elf^


def flash_and_read(elf: String) raises -> List[UInt32]:
    # Two ways in: BOOTSEL (drag the UF2) or a running firmware — in
    # that case the openocd fork flashes over SWD, no button needed.
    var waited = 0
    while not b2._mounted() and waited < 3:
        waited += 1
        sleep(2.0)
    if b2._mounted():
        _ = buildmod.sh(
            String("picotool uf2 convert ") + elf
            + " /tmp/periph.uf2 --family rp2350-riscv"
        )
        _ = buildmod.sh(String("cp /tmp/periph.uf2 ") + b2.MOUNT + "/")
        _ = buildmod.sh("sync 2>/dev/null || true")
        var gone = False
        for _ in range(30):
            sleep(2.0)
            if not b2._mounted():
                gone = True
                break
        if not gone:
            raise Error("device never left BOOTSEL (UF2 not consumed?)")
    else:
        print("  (not in BOOTSEL; flashing over SWD via openocd)")
        _ = buildmod.shx(
            buildmod.openocd_rp2350()
            + " -f interface/cmsis-dap.cfg"
            + ' -c "adapter speed 1000" -f target/rp2350-riscv.cfg'
            + ' -c "program ' + elf + ' verify reset exit" 2>&1 | tail -1'
        )
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


def main() raises:
    print("building peripherals firmware...")
    var elf = build_fw()
    print("running on target...")
    var flat = flash_and_read(elf)

    var t_us = flat[0]
    var t_cyc = flat[1]
    var pwm_moving = flat[2]
    var pwm_range = flat[3]
    var temp_mc = flat[4]
    var adc_raw = flat[5]
    var uart_ok = flat[6]
    var uart_got = flat[7]
    var sleep_cyc = flat[8]

    # cycles per µs, in hundredths (expect 1200 = 12.00)
    var centi = UInt64(t_cyc) * 100 / UInt64(t_us)
    print(
        "timer: " + String(Int(t_us)) + " µs vs " + String(Int(t_cyc))
        + " cycles -> " + b2._ratio2(t_cyc, t_us) + " cyc/µs (expect 12.00)"
    )
    print(
        "pwm: moving=" + String(Int(pwm_moving)) + " in_range="
        + String(Int(pwm_range))
    )
    print(
        "adc: die temp " + String(Int(Int32(temp_mc))) + " m°C (raw "
        + String(Int(adc_raw)) + ")"
    )
    print(
        "uart: loopback ok=" + String(Int(uart_ok)) + " bytes=0x"
        + String(Int(uart_got))
    )
    print(
        "sleep_us(10000): " + String(Int(sleep_cyc))
        + " cycles (expect 120000 ±2%)"
    )

    if centi < 1176 or centi > 1224:
        raise Error("timer/mcycle ratio outside 12.00 ±2%")
    if pwm_moving != 1 or pwm_range != 1:
        raise Error("PWM counter not running correctly")
    var mc = Int(Int32(temp_mc))
    if mc < 5_000 or mc > 60_000:
        raise Error("die temperature implausible")
    if uart_ok != 1:
        raise Error("UART loopback failed")
    if sleep_cyc < 117_600 or sleep_cyc > 122_400:
        raise Error("sleep_us accuracy outside ±2%")
    print()
    print("gates: TIMER rate, PWM, ADC temp, UART loopback, sleep accuracy verified")
