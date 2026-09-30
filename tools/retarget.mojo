"""IR retargeting: rewrite riscv32 LLVM IR as ARMv6-M IR.

This is the heart of the RP2040 build pipeline. Mojo's shipped LLVM has
no 32-bit ARM backend (its Bazel BACKENDS list is AArch64, RISCV, X86),
so we emit IR for riscv32 (same ILP32 little-endian data model) and
change only what names the target:

  - `target triple` and `target datalayout`
  - the `"target-cpu"` / `"target-features"` function attributes

The host LLVM that consumes the result is pinned in pixi.toml close to
Mojo's own LLVM, so newer IR syntax (debug records, `captures(...)`,
`f0x` literals, GEP `nuw`, ...) passes through untouched; no downgrade
rules. Pure string processing, no regular expressions.

Shared constants for the whole pipeline live here too.
"""

comptime TRIPLE_IR = "riscv32-unknown-none-elf"
comptime TRIPLE_MCU = "thumbv6m-unknown-none-eabi"
comptime CPU = "cortex-m0plus"
# ARMv6-M datalayout (matches rustc's thumbv6m-none-eabi target spec).
comptime DATALAYOUT_MCU = "e-m:e-p:32:32-Fi8-i64:64-v128:64:128-a:0:32-n32-S64"
# Host LLVM major version the pipeline is verified against (pixi.toml).
comptime HOST_LLVM_MAJOR = 23


def _set_quoted_attr(line: String, key: String, value: String) -> String:
    """Set every `"key"="…"` (or bare `"key"`) in line to `"key"="value"`.

    Rewriting instead of deleting keeps attribute groups non-empty.
    """
    var quoted = String('"') + key + '"'
    var out = String()
    var rest = line
    while True:
        var idx = rest.find(quoted)
        if idx == -1:
            return out + rest
        var after = idx + quoted.byte_length()
        var b = rest.as_bytes()
        var end = after
        if after + 1 < len(b) and b[after] == UInt8(ord("=")) and b[
            after + 1
        ] == UInt8(ord('"')):
            var close = rest.find('"', after + 2)
            if close == -1:
                return out + rest
            end = close + 1
        out += String(rest[byte=0:idx]) + quoted + '="' + value + '"'
        var tail = String(rest[byte = end : len(b)])
        rest = tail^


def retarget_text(src: String) -> String:
    """Rewrite one riscv32 IR module as ARMv6-M IR (see module docs)."""
    var out = String()
    for line_slice in src.split("\n"):
        var line = String(line_slice)
        if line.startswith("target datalayout"):
            line = String('target datalayout = "') + DATALAYOUT_MCU + '"'
        elif line.startswith("target triple"):
            line = String('target triple = "') + TRIPLE_MCU + '"'
        else:
            line = _set_quoted_attr(line, "target-cpu", CPU)
            line = _set_quoted_attr(line, "target-features", "")
        out += line + "\n"
    # split() yields one trailing empty piece per trailing newline; undo the
    # extra "\n" so the output ends exactly like the input.
    var trimmed = String(out[byte = 0 : out.byte_length() - 1])
    return trimmed^
