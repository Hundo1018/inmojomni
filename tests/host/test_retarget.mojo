"""Unit tests for the IR retarget pass in tools/retarget.mojo.

retarget_text() changes only what names the target (triple, datalayout,
target-cpu, target-features). Everything else, including IR syntax newer
than old LLVM releases, must pass through untouched and be accepted by
the host LLVM pinned in pixi.toml; volatile ops must survive.

Run: mojo run -I tools tests/host/test_retarget.mojo
"""

from std.subprocess import run

from boot2 import build_boot2
from check_elf import crc32_mpeg2
from retarget import (
    CPU,
    DATALAYOUT_MCU,
    HOST_LLVM_MAJOR,
    TRIPLE_MCU,
    retarget_text,
)

# Constructs Mojo's LLVM emits that LLVM 18 rejected (each needed a
# downgrade rule before the host LLVM was pinned to a matching release).
comptime MODERN_IR = """; ModuleID = 'synthetic'
target datalayout = "e-m:e-p:32:32-i64:64-n32-S128"
target triple = "riscv32-unknown-none-elf"

@buf = global [4 x i32] zeroinitializer

declare void @llvm.lifetime.start.p0(ptr captures(none))
declare void @llvm.lifetime.end.p0(ptr captures(none))

define dso_local i32 @f(ptr captures(none) %p, i32 %x) #0 {
  %tmp = alloca i32, align 4
  call void @llvm.lifetime.start.p0(ptr %tmp)
  store i32 %x, ptr %tmp, align 4
  %v = load volatile i32, ptr %p, align 4
  store volatile i32 %x, ptr %p, align 4
  %e = load i32, ptr getelementptr inbounds nuw (i8, ptr @buf, i32 4), align 4
  %s = add i32 %v, %e
  call void @llvm.lifetime.end.p0(ptr %tmp)
  ret i32 %s
}

define dso_local void @g(ptr dead_on_return %q) #1 {
  ret void
}

define dso_local float @ff(float %a) #0 {
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


def _llc_null(path: String) -> String:
    return (
        String("llc -mtriple=") + TRIPLE_MCU + " -mcpu=" + CPU
        + " -filetype=null " + path
    )


def test_host_llvm_pinned() raises:
    var v = run("opt --version")
    _assert(
        _contains(v, String("LLVM version ") + String(HOST_LLVM_MAJOR) + "."),
        "host opt is not LLVM " + String(HOST_LLVM_MAJOR)
        + ".x (run through pixi): " + v,
    )
    _ok(String("host LLVM is the pinned ") + String(HOST_LLVM_MAJOR) + ".x")


def test_retarget_rules() raises:
    var out = retarget_text(MODERN_IR)

    _assert(
        _contains(out, String('target triple = "') + TRIPLE_MCU + '"'),
        "triple rewritten",
    )
    _assert(_contains(out, DATALAYOUT_MCU), "datalayout rewritten")
    _assert(not _contains(out, "riscv32"), "no riscv32 left")
    _ok("triple and datalayout rewritten")

    _assert(
        _contains(out, String('"target-cpu"="') + CPU + '"'),
        "target-cpu set to " + CPU,
    )
    _assert(_contains(out, '"target-features"=""'), "target-features cleared")
    _assert(not _contains(out, "generic-rv32"), "no riscv cpu left")
    _assert(not _contains(out, "+32bit"), "no riscv features left")
    _ok("target-cpu / target-features rewritten, groups stay non-empty")

    _assert(
        _count(out, "\n") == _count(MODERN_IR, "\n"),
        "line count changed",
    )
    for tok in [
        "captures(none)",
        "dead_on_return",
        "nocreateundeforpoison",
        "f0x3FC00000",
        "llvm.lifetime.start",
        "getelementptr inbounds nuw",
    ]:
        _assert(
            _count(out, tok) == _count(MODERN_IR, tok),
            String("modern syntax altered: ") + tok,
        )
    _ok("modern IR syntax passes through untouched")

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
        _tool_ok(_llc_null("build/test_retarget_modern.ll")),
        "llc could not codegen output",
    )
    _ok("output codegens for cortex-m0plus")


def test_debug_records() raises:
    var out = retarget_text(DEBUG_IR)
    _assert(_contains(out, "#dbg_value("), "#dbg_value record kept")
    _write("build/test_retarget_dbg.ll", out)
    _assert(
        _tool_ok(
            "opt -passes=verify -disable-output build/test_retarget_dbg.ll"
        ),
        "opt -verify rejected debug output",
    )
    _assert(
        _tool_ok(_llc_null("build/test_retarget_dbg.ll")),
        "llc could not codegen debug output",
    )
    _ok("#dbg_value records accepted as-is (verify + codegen)")


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
    test_host_llvm_pinned()
    test_retarget_rules()
    test_debug_records()
    test_boot2_from_source()
    print("host-unit: all assertions passed")
