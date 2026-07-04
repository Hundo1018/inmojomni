"""Unit tests for the IR retarget/downgrade pass in tools/retarget.mojo.

Mojo bundles an LLVM much newer than the system one, so retarget_text()
must translate new IR syntax into something `opt`/`llc` 18 accept —
without ever touching the semantics we care about (volatile ops).

Run: mojo run -I tools tests/host/test_retarget.mojo
"""

from std.subprocess import run

from boot2 import build_boot2
from check_elf import crc32_mpeg2
from retarget import CPU, DATALAYOUT_MCU, TRIPLE_MCU, retarget_text

comptime MODERN_IR = """; ModuleID = 'synthetic'
target datalayout = "e-m:e-p:32:32-i64:64-n32-S128"
target triple = "riscv32-unknown-none-elf"

declare void @llvm.lifetime.start.p0(ptr captures(none))
declare void @llvm.lifetime.end.p0(ptr captures(none))

define dso_local i32 @f(ptr captures(none) %p, i32 %x) #0 {
  call void @llvm.lifetime.start.p0(ptr %p)
  %v = load volatile i32, ptr %p, align 4
  store volatile i32 %x, ptr %p, align 4
  %s = add i32 %v, %x
  call void @llvm.lifetime.end.p0(ptr %p)
  ret i32 %s
}

define dso_local void @g(ptr dead_on_return %q) #1 {
  ret void
}

define dso_local float @ff(float %a) {
  %r = fadd float %a, f0x3FC00000
  ret float %r
}

attributes #0 = { "target-cpu"="generic-rv32" "target-features"="+32bit,+i" }
attributes #1 = { nocallback nocreateundeforpoison nofree nosync nounwind willreturn memory(none) }
"""

comptime DEBUG_IR = """target datalayout = "e-m:e-p:32:32-i64:64-n32-S128"
target triple = "riscv32-unknown-none-elf"

define void @h(i32 %x) !dbg !5 {
  #dbg_value(i32 %x, !9, !DIExpression(), !10)
  ret void, !dbg !10
}

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!3, !4}
!0 = distinct !DICompileUnit(language: DW_LANG_C99, file: !1, emissionKind: FullDebug)
!1 = !DIFile(filename: "t.mojo", directory: "")
!3 = !{i32 7, !"Dwarf Version", i32 4}
!4 = !{i32 2, !"Debug Info Version", i32 3}
!5 = distinct !DISubprogram(name: "h", scope: !1, file: !1, line: 1, type: !6, unit: !0)
!6 = !DISubroutineType(types: !7)
!7 = !{null}
!9 = !DILocalVariable(name: "x", scope: !5, file: !1, line: 1, type: !11)
!10 = !DILocation(line: 1, scope: !5)
!11 = !DIBasicType(name: "int", size: 32, encoding: DW_ATE_signed)
"""

def _ok(name: String):
    print("  ✓", name)


def _assert(cond: Bool, msg: String) raises:
    if not cond:
        raise Error("assertion failed: " + msg)


def _contains(hay: String, needle: String) -> Bool:
    return hay.find(needle) != -1


def _count(hay: String, needle: String) -> Int:
    var n = 0
    var searched = 0
    while True:
        var idx = hay.find(needle, searched)
        if idx == -1:
            return n
        n += 1
        searched = idx + needle.byte_length()


def _tool_ok(cmd: String) raises -> Bool:
    var out = run(cmd + " >/dev/null 2>&1; echo __RC$?")
    return _contains(out, "__RC0")


def _write(path: String, text: String) raises:
    var f = open(path, "w")
    f.write(text)
    f.close()


def test_retarget_rules() raises:
    var out = retarget_text(MODERN_IR)

    _assert(
        _contains(out, String('target triple = "') + TRIPLE_MCU + '"'),
        "triple rewritten",
    )
    _assert(_contains(out, DATALAYOUT_MCU), "datalayout rewritten")
    _assert(not _contains(out, "riscv32"), "no riscv32 left")
    _ok("triple and datalayout rewritten")

    _assert(not _contains(out, "captures("), "captures stripped")
    _assert(not _contains(out, "dead_on_return"), "dead_on_return stripped")
    _assert(
        not _contains(out, "nocreateundeforpoison"),
        "nocreateundeforpoison stripped",
    )
    _assert(not _contains(out, "target-features"), "target-features stripped")
    _assert(not _contains(out, "generic-rv32"), "target-cpu stripped")
    _ok("modern attributes stripped")

    _assert(not _contains(out, "llvm.lifetime"), "lifetime dropped")
    _ok("lifetime intrinsics dropped")

    # f0x3FC00000 is 1.5f -> double bits 0x3FF8000000000000
    _assert(not _contains(out, "f0x"), "f0x literals gone")
    _assert(_contains(out, "0x3FF8000000000000"), "1.5f widened to double")
    _ok("float literals downgraded")

    _assert(
        _contains(out, "attributes #0 = { nounwind }"),
        "emptied attribute group patched",
    )
    _ok("emptied attribute group patched")

    _assert(
        _count(out, "volatile") == _count(MODERN_IR, "volatile"),
        "volatile op count changed",
    )
    _ok("volatile ops preserved")

    _write("build/test_retarget_modern.ll", out)
    _assert(
        _tool_ok(
            "opt -passes=verify -disable-output build/test_retarget_modern.ll"
        ),
        "opt -verify rejected output",
    )
    _ok("output passes the LLVM verifier")

    _assert(
        _tool_ok(
            String("llc -mtriple=") + TRIPLE_MCU + " -mcpu=" + CPU
            + " -filetype=null build/test_retarget_modern.ll"
        ),
        "llc could not codegen output",
    )
    _ok("output codegens for cortex-m0plus")


def test_debug_records() raises:
    var out = retarget_text(DEBUG_IR)

    _assert(not _contains(out, "#dbg_value"), "#dbg_value gone")
    _assert(
        _contains(
            out,
            "call void @llvm.dbg.value(metadata i32 %x, metadata !9, "
            + "metadata !DIExpression()), !dbg !10",
        ),
        "record became intrinsic call",
    )
    _assert(
        _contains(out, "declare void @llvm.dbg.value"),
        "intrinsic declared",
    )
    _ok("#dbg_value record becomes intrinsic call")

    _write("build/test_retarget_dbg.ll", out)
    _assert(
        _tool_ok(
            "opt -passes=verify -disable-output build/test_retarget_dbg.ll"
        ),
        "opt -verify rejected debug output",
    )
    _ok("debug output passes the LLVM verifier")


def test_boot2_from_source() raises:
    # Rebuild boot2 from the vendored pico-sdk source and require it to
    # be byte-identical to the golden reference blob — provenance and
    # checksum in one regression test.
    _ = build_boot2()
    var gen_f = open("build/boot2.bin", "r")
    var gen = gen_f.read_bytes()
    gen_f.close()
    var gold_f = open("runtime/boot2.bin", "r")
    var gold = gold_f.read_bytes()
    gold_f.close()
    _assert(len(gen) == 256, "generated boot2 must be 256 bytes")
    _assert(len(gold) == 256, "golden boot2 must be 256 bytes")
    for i in range(256):
        if gen[i] != gold[i]:
            raise Error(
                "generated boot2 differs from golden at byte "
                + String(i)
            )
    var want = (
        UInt32(gen[252])
        | (UInt32(gen[253]) << 8)
        | (UInt32(gen[254]) << 16)
        | (UInt32(gen[255]) << 24)
    )
    _assert(
        crc32_mpeg2(gen, 252) == want,
        "generated boot2 CRC32-MPEG2 invalid",
    )
    _ok("boot2 built from pico-sdk source == golden blob, CRC valid")


def main() raises:
    _ = run("mkdir -p build")
    test_retarget_rules()
    test_debug_records()
    test_boot2_from_source()
    print("host-unit: all assertions passed")
