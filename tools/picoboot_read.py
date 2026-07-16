#!/usr/bin/env python3
"""Minimal PICOBOOT memory reader (host test rig).

Reads device memory over the PICOBOOT USB interface while an RP2350 sits
in BOOTSEL mode. Unlike SWD, this path does not go through the M33 debug
AP, so it works regardless of which architecture the cores were left in
(the AP faults whenever the cores are in RISC-V mode — verified on
hardware 2026-07-17).

Protocol: pico-sdk boot/picoboot.h — 32-byte command on the bulk OUT
endpoint {dMagic, dToken, bCmdId, bCmdSize, _unused, dTransferLength,
args}; PC_READ=0x84 with range_cmd {dAddr, dSize}; data arrives on the
bulk IN endpoint; host acks an IN-data command with a zero-length OUT.

Usage: picoboot_read.py <hex-addr> <n-words>
"""

import struct
import sys

import usb.core
import usb.util

PICOBOOT_MAGIC = 0x431FD10B
PC_EXCLUSIVE_ACCESS = 0x1
PC_READ = 0x84
PC_EXIT_XIP = 0x6

FLASH_START = 0x10000000
FLASH_END = 0x14000000


def open_picoboot():
    dev = usb.core.find(idVendor=0x2E8A, idProduct=0x000F)
    if dev is None:
        raise SystemExit("no RP2350 in BOOTSEL (2e8a:000f) on USB")
    cfg = dev.get_active_configuration()
    intf = next(i for i in cfg if i.bInterfaceClass == 0xFF)
    if dev.is_kernel_driver_active(intf.bInterfaceNumber):
        dev.detach_kernel_driver(intf.bInterfaceNumber)
    ep_out = next(e for e in intf if usb.util.endpoint_direction(e.bEndpointAddress) == usb.util.ENDPOINT_OUT)
    ep_in = next(e for e in intf if usb.util.endpoint_direction(e.bEndpointAddress) == usb.util.ENDPOINT_IN)
    # PICOBOOT_IF_RESET: un-stall endpoints, reset interface state
    dev.ctrl_transfer(0x41, 0x41, 0, intf.bInterfaceNumber, b"")
    return dev, ep_out, ep_in


def _cmd_no_data(ep_out, ep_in, cmd_id, args=b""):
    cmd = struct.pack("<IIBBHI", PICOBOOT_MAGIC, 1, cmd_id, len(args), 0, 0) + args
    cmd += b"\x00" * (32 - len(cmd))
    ep_out.write(cmd)
    ep_in.read(1, timeout=2000)  # zero-length ACK for an OUT command


def read_mem(ep_out, ep_in, addr, size):
    if FLASH_START <= addr < FLASH_END:
        # flash reads need the QSPI device out of XIP and back in a serial
        # command state first (what picotool does before every flash read);
        # without this PC_READ returns zeros for the whole flash window.
        _cmd_no_data(ep_out, ep_in, PC_EXCLUSIVE_ACCESS, b"\x01")
        _cmd_no_data(ep_out, ep_in, PC_EXIT_XIP)
    cmd = struct.pack("<IIBBHIII", PICOBOOT_MAGIC, 1, PC_READ, 8, 0, size, addr, size)
    cmd += b"\x00" * (32 - len(cmd))
    ep_out.write(cmd)
    data = bytes(ep_in.read(size, timeout=2000))
    ep_out.write(b"")  # zero-length ACK for an IN-data command
    if FLASH_START <= addr < FLASH_END:
        _cmd_no_data(ep_out, ep_in, PC_EXCLUSIVE_ACCESS, b"\x00")
    return data


def main():
    addr = int(sys.argv[1], 16)
    nwords = int(sys.argv[2])
    dec = "--dec" in sys.argv[3:]
    dev, ep_out, ep_in = open_picoboot()
    data = read_mem(ep_out, ep_in, addr, nwords * 4)
    words = struct.unpack(f"<{nwords}I", data)
    if dec:
        print(" ".join(str(w) for w in words))
    else:
        print(" ".join(f"{w:08x}" for w in words))
    usb.util.dispose_resources(dev)


if __name__ == "__main__":
    main()
