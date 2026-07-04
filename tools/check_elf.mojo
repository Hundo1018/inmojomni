"""Static verifier for inmojomni firmware ELFs.

Pure-Mojo ELF32 parsing, no dependencies. Checks everything that can
be checked without hardware:

  * ELF is 32-bit little-endian ARM
  * .boot2 at 0x10000000, exactly 256 bytes, valid CRC32-MPEG2 checksum
    (the RP2040 mask ROM refuses to boot flash without it)
  * vector table at 0x10000100: initial SP inside RAM and 4-aligned,
    reset vector inside flash with the thumb bit set
  * every allocated section fits its memory region, no overlaps

Usage: mojo run -I tools tools/check_elf.mojo build/firmware.elf
"""

from std.sys import argv

comptime FLASH_ORIGIN: UInt32 = 0x1000_0000
comptime FLASH_END: UInt32 = 0x1020_0000  # 2 MB
comptime RAM_ORIGIN: UInt32 = 0x2000_0000
comptime RAM_END: UInt32 = 0x2004_0000  # 256 KB (striped banks)
comptime VECTOR_TABLE: UInt32 = 0x1000_0100
comptime STACK_MARGIN: UInt32 = 4096  # leave at least this much for stack

comptime EM_ARM: UInt32 = 40
comptime SHF_ALLOC: UInt32 = 0x2


def crc32_mpeg2(data: List[UInt8], length: Int) -> UInt32:
    """CRC-32/MPEG-2: poly 0x04C11DB7, init 0xFFFFFFFF, no reflection."""
    var crc: UInt32 = 0xFFFFFFFF
    for i in range(length):
        crc ^= UInt32(data[i]) << 24
        for _ in range(8):
            if crc & 0x8000_0000:
                crc = (crc << 1) ^ 0x04C11DB7
            else:
                crc = crc << 1
    return crc


def _rd16(d: List[UInt8], off: Int) -> UInt32:
    return UInt32(d[off]) | (UInt32(d[off + 1]) << 8)


def _rd32(d: List[UInt8], off: Int) -> UInt32:
    return (
        UInt32(d[off])
        | (UInt32(d[off + 1]) << 8)
        | (UInt32(d[off + 2]) << 16)
        | (UInt32(d[off + 3]) << 24)
    )


@fieldwise_init
struct Sect(Copyable, Movable):
    var name: String
    var sh_type: UInt32
    var flags: UInt32
    var addr: UInt32
    var offset: UInt32
    var size: UInt32


def _hex(v: UInt32) -> String:
    return String(hex(Int(v)))


def parse_sections(raw: List[UInt8]) raises -> List[Sect]:
    if len(raw) < 52 or raw[0] != 0x7F or raw[1] != UInt8(
        ord("E")
    ) or raw[2] != UInt8(ord("L")) or raw[3] != UInt8(ord("F")):
        raise Error("not an ELF file")
    if raw[4] != 1 or raw[5] != 1:
        raise Error("not a 32-bit little-endian ELF")
    var machine = _rd16(raw, 18)
    if machine != EM_ARM:
        raise Error(
            "e_machine is " + String(Int(machine)) + ", expected ARM (40)"
        )
    var shoff = Int(_rd32(raw, 32))
    var shentsize = Int(_rd16(raw, 46))
    var shnum = Int(_rd16(raw, 48))
    var shstrndx = Int(_rd16(raw, 50))

    var strtab_off = Int(_rd32(raw, shoff + shstrndx * shentsize + 16))
    var sects = List[Sect]()
    for i in range(shnum):
        var off = shoff + i * shentsize
        var name_off = Int(_rd32(raw, off))
        var p = strtab_off + name_off
        var name = String()
        while raw[p] != 0:
            name += chr(Int(raw[p]))
            p += 1
        sects.append(
            Sect(
                name,
                _rd32(raw, off + 4),
                _rd32(raw, off + 8),
                _rd32(raw, off + 12),
                _rd32(raw, off + 16),
                _rd32(raw, off + 20),
            )
        )
    return sects^


def check(elf_path: String) -> List[String]:
    """Return a list of failure messages (empty = all good)."""
    var fails = List[String]()
    var raw: List[UInt8]
    var sects: List[Sect]
    try:
        var f = open(elf_path, "r")
        raw = f.read_bytes()
        f.close()
        sects = parse_sections(raw)
    except e:
        fails.append(String("cannot parse ELF: ") + String(e))
        return fails^

    # --- boot2 ------------------------------------------------------
    var have_boot2 = False
    var have_vt = False
    for s in sects:
        if s.name == ".boot2":
            have_boot2 = True
            if s.addr != FLASH_ORIGIN:
                fails.append(
                    String(".boot2 at ") + _hex(s.addr)
                    + ", expected " + _hex(FLASH_ORIGIN)
                )
            if s.size != 256:
                fails.append(
                    String(".boot2 is ") + String(Int(s.size))
                    + " bytes, expected 256"
                )
            else:
                var blob = List[UInt8]()
                for i in range(256):
                    blob.append(raw[Int(s.offset) + i])
                var want = _rd32(blob, 252)
                var got = crc32_mpeg2(blob, 252)
                if want != got:
                    fails.append(
                        String(".boot2 checksum ") + _hex(want)
                        + " != computed " + _hex(got)
                        + " (chip would hang in the mask ROM)"
                    )
        elif s.name == ".vector_table":
            have_vt = True
            if s.addr != VECTOR_TABLE:
                fails.append(
                    String(".vector_table at ") + _hex(s.addr)
                    + ", expected " + _hex(VECTOR_TABLE)
                )
            var sp = _rd32(raw, Int(s.offset))
            var reset = _rd32(raw, Int(s.offset) + 4)
            if not (RAM_ORIGIN < sp and sp <= RAM_END) or sp % 4 != 0:
                fails.append(
                    String("initial SP ") + _hex(sp)
                    + " not a 4-aligned RAM address"
                )
            if (reset & 1) == 0:
                fails.append(
                    String("reset vector ") + _hex(reset)
                    + " missing the thumb bit"
                )
            var reset_a = reset & ~UInt32(1)
            if not (FLASH_ORIGIN <= reset_a and reset_a < FLASH_END):
                fails.append(
                    String("reset vector ") + _hex(reset)
                    + " points outside flash"
                )
    if not have_boot2:
        fails.append(String("missing .boot2 section"))
    if not have_vt:
        fails.append(String("missing .vector_table section"))

    # --- memory budget and overlaps ----------------------------------
    var flash_bytes: UInt32 = 0
    var ram_bytes: UInt32 = 0
    var lo_l = List[UInt32]()
    var hi_l = List[UInt32]()
    var name_l = List[String]()
    for s in sects:
        if (s.flags & SHF_ALLOC) == 0 or s.size == 0:
            continue
        var lo = s.addr
        var hi = s.addr + s.size
        lo_l.append(lo)
        hi_l.append(hi)
        name_l.append(s.name)
        if FLASH_ORIGIN <= lo and lo < FLASH_END:
            if hi > FLASH_END:
                fails.append(s.name + " overflows flash")
            flash_bytes += s.size
        elif RAM_ORIGIN <= lo and lo < RAM_END:
            if hi > RAM_END:
                fails.append(s.name + " overflows RAM")
            ram_bytes += s.size
        else:
            fails.append(
                s.name + " at " + _hex(lo) + " is outside flash and RAM"
            )
    # insertion sort by lo
    for i in range(1, len(lo_l)):
        var j = i
        while j > 0 and lo_l[j - 1] > lo_l[j]:
            var tl = lo_l[j - 1]
            lo_l[j - 1] = lo_l[j]
            lo_l[j] = tl
            var th = hi_l[j - 1]
            hi_l[j - 1] = hi_l[j]
            hi_l[j] = th
            var tn = name_l[j - 1]
            name_l[j - 1] = name_l[j]
            name_l[j] = tn
            j -= 1
    for i in range(1, len(lo_l)):
        if hi_l[i - 1] > lo_l[i]:
            fails.append(
                String("sections ") + name_l[i - 1] + " and "
                + name_l[i] + " overlap"
            )
    if ram_bytes > (RAM_END - RAM_ORIGIN) - STACK_MARGIN:
        fails.append(
            String("RAM usage ") + String(Int(ram_bytes))
            + " leaves <" + String(Int(STACK_MARGIN)) + " bytes of stack"
        )

    return fails^


def main() raises:
    var args = argv()
    if len(args) != 2:
        raise Error("usage: check_elf.mojo <elf>")
    var path = String(args[1])
    var fails = check(path)
    for f in fails:
        print("  ✗", f)
    if len(fails) > 0:
        raise Error(String(len(fails)) + " ELF check(s) failed")
    # basename for the tick line
    var base = path
    var slash = -1
    var searched = 0
    while True:
        var n = base.find("/", searched)
        if n == -1:
            break
        slash = n
        searched = n + 1
    if slash != -1:
        base = String(base[byte = slash + 1 : base.byte_length()])
    print(
        "  ✓ " + base + ": boot2 CRC, vector table, memory layout all OK"
    )
