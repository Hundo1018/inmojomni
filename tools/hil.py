#!/usr/bin/env python3
"""Hardware-in-the-loop helpers: drive the RP2040 over SWD via probe-rs.

The on-target Mojo suite (tests/on_target/main.mojo) reports into a RAM
mailbox; this module flashes firmware, polls that mailbox, and makes
independent measurements (timer rate, LED blinking) from the host side.
"""

import subprocess
import time

CHIP = "RP2040"

MAILBOX = 0x2003_0000
MAGIC = 0x4D4F_4A4F
STATUS_DONE = 2
RESULT_OFFSET_WORDS = 8  # results start at mailbox +0x20
PASS = 0x600D_0001

TIMERAWL = 0x4005_4028
SIO_GPIO_OUT = 0xD000_0010
LED_MASK = 1 << 25

TEST_NAMES = [
    "u32 arithmetic & wrap",
    "u32 division (libgcc __aeabi_uidiv)",
    "u64 ops on 32-bit core",
    "float32 soft-float (libgcc)",
    "SIMD[uint32, 4] on M0+",
    "comptime for unroll",
    "GPIO15 internal loopback",
    "GPIO25 (LED) internal loopback",
    "timer sleep_us bounds",
    "GPIO pull-up / pull-down",
    "GPIO output-disable override",
    "GPIO edge event latch & ack",
    "GPIO funcsel round-trip",
    "GPIO pad config (drive/schmitt)",
    "PIO state machine toggling a pin",
    "TIMER ALARM0 IRQ via NVIC (2 fires)",
    "RTT control block + message",
    "GPIO EDGE_HIGH -> IO_IRQ_BANK0 (2 fires)",
    "PWM 12 kHz 50% (counter + pad readback)",
    "ADC temp sensor (plausible + stable)",
    "UART0 internal loopback (LBE)",
    "PIO side-set + forward label (edge count)",
    "PIO comptime-assembled program (flash constant)",
    "spinlock: 2x20k contended increments == 40000",
    "inter-core FIFO ping-pong (5 rounds)",
    "core 1 launched into Mojo (flag + heartbeat)",
]

RTT_BASE = 0x2003_8000
RTT_BUF = RTT_BASE + 64


def check_rtt() -> list[str]:
    """Independently verify the RTT block the suite left in RAM: the
    exact structure an RTT host tool would scan for and read."""
    words = read_words(RTT_BASE, 12)
    if words[0:3] != [0x4747_4553, 0x5220_5245, 0x0000_5454]:
        return [f"RTT magic wrong: {[hex(w) for w in words[0:3]]}"]
    max_up, max_down = words[4], words[5]
    buf_ptr, buf_size, wroff = words[7], words[8], words[9]
    if (max_up, max_down) != (1, 0) or buf_ptr != RTT_BUF:
        return [f"RTT descriptor wrong: up={max_up} down={max_down} buf={buf_ptr:#x}"]
    msg = b"RTT self-test\n"
    if wroff != len(msg):
        return [f"RTT WrOff {wroff}, expected {len(msg)}"]
    data = read_words(RTT_BUF, (len(msg) + 3) // 4)
    raw = b"".join(w.to_bytes(4, "little") for w in data)[: len(msg)]
    if raw != msg:
        return [f"RTT buffer contains {raw!r}, expected {msg!r}"]
    print(f"  ✓ [target] RTT block valid, message read back over SWD ({msg!r})")
    return []


def probe_present() -> bool:
    res = subprocess.run(["probe-rs", "list"], capture_output=True, text=True)
    return "debug probes were found" in res.stdout


def read_words(addr: int, count: int = 1) -> list[int]:
    res = subprocess.run(
        ["probe-rs", "read", "--chip", CHIP, "b32", f"{addr:#x}", str(count)],
        capture_output=True, text=True, check=True,
    )
    return [int(w, 16) for w in res.stdout.split()]


# 1 MHz SWD: the default speed proved marginal on this wiring during
# sustained flash writes (reads were fine, downloads dropped blocks).
SWD_KHZ = "1000"


def flash(elf) -> None:
    for attempt in (1, 2):
        try:
            subprocess.run(
                ["probe-rs", "download", "--chip", CHIP,
                 "--speed", SWD_KHZ, "--verify", str(elf)],
                capture_output=True, text=True, check=True,
            )
            break
        except subprocess.CalledProcessError:
            if attempt == 2:
                raise
    subprocess.run(
        ["probe-rs", "reset", "--chip", CHIP],
        capture_output=True, text=True, check=True,
    )


def run_mailbox_suite(elf, timeout_s: float = 10.0) -> list[str]:
    """Flash the on-target suite and collect results. Returns failures."""
    flash(elf)
    deadline = time.monotonic() + timeout_s
    status = magic = 0
    while time.monotonic() < deadline:
        magic, status = read_words(MAILBOX, 2)
        if magic == MAGIC and status == STATUS_DONE:
            break
        time.sleep(0.2)
    if magic != MAGIC:
        return [f"mailbox magic never appeared (got {magic:#010x}) — firmware crashed before init?"]
    if status != STATUS_DONE:
        return [f"suite never finished (status={status}) — hung test?"]

    n = read_words(MAILBOX + 0x08)[0]
    fails = []
    if n != len(TEST_NAMES):
        fails.append(f"test count {n} != expected {len(TEST_NAMES)}")
        n = min(n, len(TEST_NAMES))
    results = read_words(MAILBOX + 0x20, n)
    for i, val in enumerate(results):
        name = TEST_NAMES[i] if i < len(TEST_NAMES) else f"test {i}"
        if val == PASS:
            print(f"  ✓ [target] {name}")
        else:
            fails.append(f"[target] {name}: result word {val:#010x}")

    # Heartbeat: the firmware must still be alive after the suite.
    hb1 = read_words(MAILBOX + 0x0C)[0]
    time.sleep(0.5)
    hb2 = read_words(MAILBOX + 0x0C)[0]
    if hb2 == hb1:
        fails.append(f"heartbeat stuck at {hb1} — firmware not running")
    else:
        print(f"  ✓ [target] heartbeat alive ({hb1} -> {hb2})")
    return fails


def check_timer_rate(tolerance: float = 0.05) -> list[str]:
    """The RP2040 TIMER must tick at 1 MHz against the host clock.

    Each probe-rs invocation costs ~150 ms of process startup, so we
    timestamp the midpoint of each read to approximate the moment the
    SWD transfer actually happened. Residual bias is ~2%; the check
    exists to catch gross clock misconfiguration (ROSC instead of XOSC
    reads ~0.5 MHz, a wrong tick divider is off by an integer factor).
    """
    h0a = time.monotonic()
    t0 = read_words(TIMERAWL)[0]
    h0b = time.monotonic()
    time.sleep(3.0)  # long baseline dilutes probe-rs startup jitter
    h1a = time.monotonic()
    t1 = read_words(TIMERAWL)[0]
    h1b = time.monotonic()
    elapsed_host = (h1a + h1b) / 2 - (h0a + h0b) / 2
    ticks = (t1 - t0) & 0xFFFF_FFFF
    ratio = ticks / (elapsed_host * 1_000_000)
    if abs(ratio - 1.0) > tolerance:
        return [f"timer runs at {ratio:.3f} MHz, expected 1 MHz ±{tolerance:.0%}"]
    print(f"  ✓ [target] timer rate {ratio:.3f} MHz (host-clock referenced)")
    return []


def check_debug_experience(elf_debug) -> list[str]:
    """Verify the full F5 experience over the real DAP protocol:
    flash + attach, breakpoint re-hits in the loop, step-over/step-in,
    variable/register scopes and memory reads. (The attach flow is
    deliberate: probe-rs's launch flow arms breakpoints while the core
    is halted in the RP2040 bootrom, where they never fire.)"""
    from pathlib import Path

    import dap_client

    return dap_client.run_debug_session(
        Path(elf_debug), Path("src/main.mojo").resolve(), "led.toggle()"
    )


def observe_blink(elf, samples: int = 24) -> list[str]:
    """Flash the blink demo and verify the LED output actually toggles."""
    flash(elf)
    time.sleep(0.3)
    states, transitions = [], 0
    for _ in range(samples):
        s = 1 if read_words(SIO_GPIO_OUT)[0] & LED_MASK else 0
        if states and s != states[-1]:
            transitions += 1
        states.append(s)
        time.sleep(0.15)
    if 0 not in states or 1 not in states:
        return [f"LED stuck at {'high' if 1 in states else 'low'}"]
    if transitions < 4:
        return [f"only {transitions} LED transitions in {samples} samples"]
    print(f"  ✓ [target] LED blinking ({transitions} transitions / {samples} samples)")
    return []
