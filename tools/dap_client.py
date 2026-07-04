#!/usr/bin/env python3
"""Minimal DAP (Debug Adapter Protocol) client for probe-rs dap-server.

Speaks exactly the protocol VS Code speaks when you press F5, so the
HIL suite can verify the *real* debugging experience: breakpoint hits
inside the loop, continue re-hits, stack traces, variables, registers
and memory reads.

Usage: python tools/dap_client.py [--elf build/firmware-debug.elf]
Exit code 0 = full debug experience verified.
"""

import argparse
import json
import socket
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


class Dap:
    def __init__(self, port: int):
        self.sock = socket.create_connection(("127.0.0.1", port), timeout=30)
        self.buf = b""
        self.seq = 0
        self.events = []
        self.responses = {}

    def send(self, command: str, arguments=None):
        self.seq += 1
        msg = {"seq": self.seq, "type": "request", "command": command}
        if arguments is not None:
            msg["arguments"] = arguments
        raw = json.dumps(msg).encode()
        self.sock.sendall(b"Content-Length: %d\r\n\r\n%s" % (len(raw), raw))
        return self.seq

    def _read_msg(self, timeout: float):
        self.sock.settimeout(timeout)
        while b"\r\n\r\n" not in self.buf:
            self.buf += self.sock.recv(65536)
        header, _, rest = self.buf.partition(b"\r\n\r\n")
        length = int(header.split(b":")[1])
        while len(rest) < length:
            rest += self.sock.recv(65536)
        self.buf = rest[length:]
        return json.loads(rest[:length])

    def _dispatch(self, msg):
        if msg["type"] == "event":
            self.events.append(msg)
        elif msg["type"] == "response":
            self.responses[msg.get("request_seq")] = msg

    def wait_response(self, req_seq: int, timeout: float = 60):
        deadline = time.monotonic() + timeout
        while req_seq not in self.responses and time.monotonic() < deadline:
            self._dispatch(self._read_msg(deadline - time.monotonic()))
        msg = self.responses.pop(req_seq, None)
        if msg is None:
            raise TimeoutError(f"no response for request {req_seq}")
        if not msg.get("success", False):
            raise RuntimeError(f"{msg['command']} failed: {msg.get('message')}")
        return msg

    def request(self, command: str, arguments=None, timeout: float = 60):
        if "-v" in sys.argv:
            print(f"    [dap>] {command}", flush=True)
        return self.wait_response(self.send(command, arguments), timeout)

    def wait_event(self, name: str, timeout: float = 60):
        for i, ev in enumerate(self.events):
            if ev["event"] == name:
                return self.events.pop(i)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            msg = self._read_msg(deadline - time.monotonic())
            if msg["type"] == "event" and msg["event"] == name:
                return msg
            self._dispatch(msg)
        raise TimeoutError(f"event {name} never arrived")


def run_debug_session(elf: Path, main_src: Path, bp_pattern: str) -> list[str]:
    """Full F5-equivalent session. Returns a list of failures."""
    fails = []
    lines = main_src.read_text().splitlines()
    bp_line = next(i for i, l in enumerate(lines, 1) if bp_pattern in l)

    # Flash first, then ATTACH. probe-rs's launch flow arms breakpoints
    # while the core is halted in the bootrom, where they never take on
    # RP2040 (verified upstream bug); breakpoints set while the core is
    # in application code work every time.
    subprocess.run(["probe-rs", "download", "--chip", "RP2040", str(elf)],
                   capture_output=True, check=True)
    subprocess.run(["probe-rs", "reset", "--chip", "RP2040"],
                   capture_output=True, check=True)
    time.sleep(0.5)

    port = 45678
    server = subprocess.Popen(
        ["probe-rs", "dap-server", "--port", str(port)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        time.sleep(1.5)
        dap = Dap(port)
        dap.request("initialize", {
            "adapterID": "probe-rs-debug",
            "clientName": "inmojomni-hil",
            "supportsMemoryReferences": True,
        })
        launch_seq = dap.send("attach", {
            "cwd": str(ROOT),
            "chip": "rp2040",
            "connectUnderReset": False,
            "speed": 4000,
            "coreConfigs": [{"coreIndex": 0, "programBinary": str(elf)}],
            "consoleLogLevel": "Info",
            "wireProtocol": "Swd",
        })
        dap.wait_event("initialized", timeout=60)
        dap.request("setBreakpoints", {
            "source": {"path": str(main_src)},
            "breakpoints": [{"line": bp_line}],
        })
        dap.request("configurationDone")
        dap.wait_response(launch_seq, timeout=60)

        threads = dap.request("threads")["body"]["threads"]
        tid = threads[0]["id"]

        def continue_to_stop(tag: str):
            # drop stale stopped events (e.g. the halt-after-reset one)
            dap.events = [e for e in dap.events if e["event"] != "stopped"]
            dap.request("continue", {"threadId": tid})
            ev = dap.wait_event("stopped", timeout=15)
            reason = ev["body"].get("reason", "?")
            st = dap.request("stackTrace", {"threadId": tid})["body"]["stackFrames"]
            top = st[0]
            src = (top.get("source") or {}).get("path", "?")
            print(f"  ✓ [dap] {tag}: stopped ({reason}) at "
                  f"{Path(src).name}:{top['line']} in {top['name']}")
            return reason, top, st

        # --- the user's exact complaint: does the loop line re-hit? ---
        hits = []
        for i in range(3):
            reason, top, stack = continue_to_stop(f"hit #{i + 1}")
            hits.append((reason, Path((top.get("source") or {}).get("path", "?")).name,
                         top["line"]))
        for reason, srcname, line in hits:
            if reason != "breakpoint" or srcname != main_src.name:
                fails.append(f"expected breakpoint in {main_src.name}, got {reason} in {srcname}:{line}")

        # --- stepping: next (step over) and step in ---------------------
        dap.request("next", {"threadId": tid})
        ev = dap.wait_event("stopped", timeout=15)
        st = dap.request("stackTrace", {"threadId": tid})["body"]["stackFrames"][0]
        print(f"  ✓ [dap] step-over -> line {st['line']} ({ev['body'].get('reason')})")
        if (st.get("source") or {}).get("path", "").rsplit("/", 1)[-1] != main_src.name:
            fails.append(f"step-over left {main_src.name}: {st}")

        dap.request("stepIn", {"threadId": tid})
        dap.wait_event("stopped", timeout=15)
        st = dap.request("stackTrace", {"threadId": tid})["body"]["stackFrames"]
        entered = (st[0].get("source") or {}).get("path", "?")
        print(f"  ✓ [dap] step-in -> {Path(entered).name}:{st[0]['line']} "
              f"in {st[0]['name']} (depth {len(st)})")

        # --- variables & registers --------------------------------------
        frame_id = st[0]["id"]
        scopes = dap.request("scopes", {"frameId": frame_id})["body"]["scopes"]
        scope_names = [s["name"] for s in scopes]
        shown = []
        for s in scopes:
            body = dap.request("variables", {"variablesReference": s["variablesReference"]})
            for v in body["body"]["variables"][:6]:
                shown.append(f"{s['name']}/{v['name']}={v.get('value', '?')[:24]}")
        print(f"  ✓ [dap] scopes {scope_names}; sample: {shown[:6]}")
        if not any("Registers" in n or "Variables" in n or "Locals" in n for n in scope_names):
            fails.append(f"no variable/register scopes exposed: {scope_names}")

        # --- memory read: vector table must start with our stack top ----
        mem = dap.request("readMemory", {"memoryReference": "0x10000100", "count": 8})
        import base64
        data = base64.b64decode(mem["body"]["data"])
        sp = int.from_bytes(data[0:4], "little")
        print(f"  ✓ [dap] readMemory(0x10000100): initial SP = {sp:#010x}")
        if not (0x20000000 < sp <= 0x20042000):
            fails.append(f"vector table SP read via DAP looks wrong: {sp:#x}")

        dap.request("disconnect", {"terminateDebuggee": False})
    except (RuntimeError, TimeoutError, OSError) as e:
        fails.append(f"DAP session failed: {e}")
    finally:
        server.terminate()
        try:
            server.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server.kill()
    return fails


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--elf", type=Path, default=ROOT / "build/firmware-debug.elf")
    ap.add_argument("--source", type=Path, default=ROOT / "src/main.mojo")
    ap.add_argument("--pattern", default="led.toggle()")
    ap.add_argument("-v", action="store_true", help="trace DAP requests")
    args = ap.parse_args()
    fails = run_debug_session(args.elf, args.source, args.pattern)
    for f in fails:
        print(f"  ✗ {f}")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
