"""Build the RP2040 second-stage bootloader from vendored public source.

Assembles runtime/boot2/boot2_w25q080.S (verbatim pico-sdk 2.1.0,
BSD-3-Clause — see runtime/boot2/README.md), pads the raw binary to
252 bytes and appends the CRC32-MPEG2 checksum the mask ROM demands.
Output: build/boot2.bin, which crt0.S `.incbin`s.

A host regression test asserts the result is byte-identical to the
golden reference runtime/boot2.bin.
"""

from std.subprocess import run

from check_elf import crc32_mpeg2


def _sh(cmd: String) raises:
    var out = run(cmd + "; echo __RC$?")
    var idx = -1
    var searched = 0
    while True:
        var next = out.find("__RC", searched)
        if next == -1:
            break
        idx = next
        searched = next + 1
    var rc = String(out[byte = idx + 4 : out.byte_length()])
    if rc != "0":
        raise Error("command failed (exit " + rc + "): " + cmd)


def build_boot2() raises -> String:
    """Produce build/boot2.bin from source; returns the path."""
    _sh("mkdir -p build")
    # PICO_FLASH_SPI_CLKDIV=2 matches the pico-sdk default build (and
    # the golden blob, byte for byte). VMA 0x20041f00 is where the mask
    # ROM copies boot2 (top of SRAM); the code is position-independent
    # but literal pools must match the reference layout.
    _sh(
        "arm-none-eabi-gcc -DPICO_FLASH_SPI_CLKDIV=2 -mcpu=cortex-m0plus"
        + " -mthumb -I runtime/boot2 -c runtime/boot2/boot2_w25q080.S"
        + " -o build/boot2.o"
    )
    _sh(
        "arm-none-eabi-gcc -nostdlib -nostartfiles -Wl,-Ttext=0x20041f00"
        + " build/boot2.o -o build/boot2.elf"
    )
    _sh(
        "arm-none-eabi-objcopy -O binary build/boot2.elf build/boot2_raw.bin"
    )

    var f = open("build/boot2_raw.bin", "r")
    var raw = f.read_bytes()
    f.close()
    if len(raw) > 252:
        raise Error(
            "boot2 code is " + String(len(raw))
            + " bytes; must fit 252 (256 minus checksum)"
        )
    var blob = List[UInt8]()
    for i in range(len(raw)):
        blob.append(raw[i])
    while len(blob) < 252:
        blob.append(0)
    var crc = crc32_mpeg2(blob, 252)
    blob.append(UInt8(crc & 0xFF))
    blob.append(UInt8((crc >> 8) & 0xFF))
    blob.append(UInt8((crc >> 16) & 0xFF))
    blob.append(UInt8((crc >> 24) & 0xFF))

    var out = open("build/boot2.bin", "w")
    out.write_bytes(blob)
    out.close()
    return String("build/boot2.bin")
