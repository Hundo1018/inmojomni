"""IR retargeting: rewrite riscv32 LLVM IR so the (older) system LLVM
can codegen it for ARMv6-M.

This is the heart of the build pipeline. Mojo's bundled LLVM has no
32-bit ARM backend, so we emit IR for riscv32 (same ILP32 little-endian
data model), rewrite the target triple and datalayout, and downgrade IR
constructs the system LLVM does not know yet. Pure string processing —
every rule is a plain scan, no regular expressions.

Shared constants for the whole pipeline live here too.
"""

comptime TRIPLE_IR = "riscv32-unknown-none-elf"
comptime TRIPLE_MCU = "thumbv6m-unknown-none-eabi"
comptime CPU = "cortex-m0plus"
# ARMv6-M datalayout (matches rustc's thumbv6m-none-eabi target spec).
comptime DATALAYOUT_MCU = "e-m:e-p:32:32-Fi8-i64:64-v128:64:128-a:0:32-n32-S64"

comptime DBG_DECLARES = (
    "declare void @llvm.dbg.value(metadata, metadata, metadata)\n"
    + "declare void @llvm.dbg.declare(metadata, metadata, metadata)\n"
)


@always_inline
def _co(s: StaticString) -> UInt8:
    """Byte value of a one-character ASCII literal."""
    return UInt8(ord(s))


def _is_word(c: UInt8) -> Bool:
    return (
        (c >= _co("a") and c <= _co("z"))
        or (c >= _co("A") and c <= _co("Z"))
        or (c >= _co("0") and c <= _co("9"))
        or c == _co("_")
    )


def _is_hex(c: UInt8) -> Bool:
    return (
        (c >= _co("0") and c <= _co("9"))
        or (c >= _co("a") and c <= _co("f"))
        or (c >= _co("A") and c <= _co("F"))
    )


def _cut(line: String, start: Int, end: Int) -> String:
    """Remove [start, end) from line, swallowing one trailing space."""
    var e = end
    var b = line.as_bytes()
    if e < len(b) and b[e] == _co(" "):
        e += 1
    return String(line[byte=0:start]) + String(line[byte = e : len(b)])


def _remove_token(line: String, token: String) -> String:
    """Remove word-boundary occurrences of `token` (+ one trailing space)."""
    var out = line
    var searched = 0
    while True:
        var idx = out.find(token, searched)
        if idx == -1:
            return out
        var b = out.as_bytes()
        var before_ok = idx == 0 or not _is_word(b[idx - 1])
        var after = idx + token.byte_length()
        var after_ok = after >= len(b) or not _is_word(b[after])
        if before_ok and after_ok:
            out = _cut(out, idx, after)
            searched = idx
        else:
            searched = idx + 1


def _remove_paren_attr(line: String, opener: String, closer: String) -> String:
    """Remove `opener ... closer` spans (+ one trailing space)."""
    var out = line
    var searched = 0
    while True:
        var idx = out.find(opener, searched)
        if idx == -1:
            return out
        var b = out.as_bytes()
        if idx > 0 and _is_word(b[idx - 1]):
            searched = idx + 1
            continue
        var close = out.find(closer, idx + opener.byte_length())
        if close == -1:
            return out
        out = _cut(out, idx, close + closer.byte_length())
        searched = idx


def _remove_quoted_attr(line: String, key: String, value_optional: Bool) -> String:
    """Remove `"key"="…"` (and, if value_optional, bare `"key"`)."""
    var quoted = String('"') + key + String('"')
    var out = line
    while True:
        var idx = out.find(quoted)
        if idx == -1:
            return out
        var after = idx + quoted.byte_length()
        var b = out.as_bytes()
        if after < len(b) and b[after] == _co("="):
            # expect ="..."
            if after + 1 < len(b) and b[after + 1] == _co('"'):
                var close = out.find('"', after + 2)
                if close == -1:
                    return out
                out = _cut(out, idx, close + 1)
                continue
            return out
        if value_optional:
            out = _cut(out, idx, after)
            continue
        return out


def _remove_range_attr(line: String) -> String:
    """Remove `range(iNN …)` attributes (word-boundary, + one space)."""
    var out = line
    var searched = 0
    while True:
        var idx = out.find("range(i", searched)
        if idx == -1:
            return out
        var b = out.as_bytes()
        if idx > 0 and _is_word(b[idx - 1]):
            searched = idx + 1
            continue
        # verify: range(i<digits><space>
        var p = idx + 7
        var digits = 0
        while p < len(b) and b[p] >= _co("0") and b[p] <= _co("9"):
            p += 1
            digits += 1
        if digits == 0 or p >= len(b) or b[p] != _co(" "):
            searched = idx + 1
            continue
        var close = out.find(")", p)
        if close == -1:
            return out
        out = _cut(out, idx, close + 1)
        searched = idx


def _f32_bits_to_f64_bits(bits: UInt64) -> UInt64:
    """Widen IEEE-754 binary32 bits to binary64 bits (exact, integer math)."""
    var sign = (bits >> 31) & 1
    var exp = (bits >> 23) & 0xFF
    var frac = bits & 0x7FFFFF
    if exp == 0xFF:  # inf / nan
        return (sign << 63) | (UInt64(2047) << 52) | (frac << 29)
    if exp == 0:
        if frac == 0:  # signed zero
            return sign << 63
        # subnormal: normalize
        var e: Int = -126
        var f = frac
        while (f & 0x800000) == 0:
            f <<= 1
            e -= 1
        f &= 0x7FFFFF
        return (sign << 63) | (UInt64(e + 1023) << 52) | (f << 29)
    return (sign << 63) | ((exp - 127 + 1023) << 52) | (frac << 29)


def _hex16(v: UInt64) -> String:
    comptime DIGITS = "0123456789ABCDEF"
    var out = String()
    for i in range(16):
        var nib = Int((v >> UInt64((15 - i) * 4)) & 0xF)
        out += DIGITS[byte = nib : nib + 1]
    return out


def _parse_hex(s: String) -> UInt64:
    var v: UInt64 = 0
    var b = s.as_bytes()
    for i in range(len(b)):
        var c = b[i]
        var d: UInt64
        if c >= _co("0") and c <= _co("9"):
            d = UInt64(c - _co("0"))
        elif c >= _co("a") and c <= _co("f"):
            d = UInt64(c - _co("a") + 10)
        else:
            d = UInt64(c - _co("A") + 10)
        v = (v << 4) | d
    return v


def _downgrade_float_literals(line: String) -> String:
    """New LLVM spells f32 constants `f0xAABBCCDD` (and f64 ones
    `f0x…16 digits…`); older LLVM wants classic hex-of-double forms."""
    var out = line
    var searched = 0
    while True:
        var idx = out.find("f0x", searched)
        if idx == -1:
            return out
        var b = out.as_bytes()
        if idx > 0 and _is_word(b[idx - 1]):
            searched = idx + 1
            continue
        var p = idx + 3
        var digits = 0
        while p + digits < len(b) and _is_hex(b[p + digits]):
            digits += 1
        if digits == 16:
            # f64 literal: drop the `f` prefix.
            out = String(out[byte=0:idx]) + String(out[byte = idx + 1 : len(b)])
            searched = idx + 1
        elif digits == 8:
            var bits = _parse_hex(String(out[byte = p : p + 8]))
            var dbits = _f32_bits_to_f64_bits(bits)
            out = (
                String(out[byte=0:idx])
                + "0x"
                + _hex16(dbits)
                + String(out[byte = p + 8 : len(b)])
            )
            searched = idx + 1
        else:
            searched = idx + 1


def _split_top_level(s: String) -> List[String]:
    """Split on commas that are not nested inside parentheses."""
    var parts = List[String]()
    var depth = 0
    var start = 0
    var b = s.as_bytes()
    for i in range(len(b)):
        var ch = b[i]
        if ch == _co("("):
            depth += 1
        elif ch == _co(")"):
            depth -= 1
        if ch == _co(",") and depth == 0:
            parts.append(String(String(s[byte = start : i]).strip()))
            start = i + 1
    parts.append(String(String(s[byte = start : len(b)]).strip()))
    return parts^


def _downgrade_dbg_record(line: String) -> Tuple[Bool, String]:
    """LLVM 19+ writes debug info as records (#dbg_value …); older LLVM
    only understands the intrinsic-call form. Returns (is_record, text);
    text is empty for record kinds that must simply be dropped."""
    var stripped = String(line.lstrip())
    if not stripped.startswith("#dbg_"):
        return (False, String())
    var indent = String(line[byte = 0 : line.byte_length() - stripped.byte_length()])
    var open_p = stripped.find("(")
    if open_p == -1:
        return (True, String())
    var kind = String(stripped[byte = 5 : open_p])
    if kind != "value" and kind != "declare":
        return (True, String())  # e.g. #dbg_assign: no old equivalent
    var rstripped = String(stripped.rstrip())
    if not rstripped.endswith(")"):
        return (True, String())
    var body = String(rstripped[byte = open_p + 1 : rstripped.byte_length() - 1])
    var args = _split_top_level(body)
    if len(args) != 4:
        return (True, String())
    return (
        True,
        indent
        + "call void @llvm.dbg."
        + kind
        + "(metadata "
        + args[0]
        + ", metadata "
        + args[1]
        + ", metadata "
        + args[2]
        + "), !dbg "
        + args[3],
    )


def _patch_empty_attr_group(line: String) -> String:
    """An attribute group emptied by the stripping above is invalid IR;
    give it a harmless `nounwind`."""
    if not line.startswith("attributes #"):
        return line
    var open_b = line.find("{")
    if open_b == -1 or not String(line.rstrip()).endswith("}"):
        return line
    var rs = String(line.rstrip())
    var inner = String(rs[byte = open_b + 1 : rs.byte_length() - 1])
    if String(inner.strip()).byte_length() != 0:
        return line
    # exact match of the python pipeline's output shape
    if not String(line[byte=0:open_b]).endswith("= "):
        return line
    return String(line[byte = 0 : open_b + 1]) + " nounwind }"


def retarget_text(src: String) -> String:
    """Rewrite one riscv32 IR module as ARMv6-M IR (see module docs)."""
    var out = String()
    var converted_dbg = False
    # splitlines() semantics: one trailing newline yields no empty line.
    var text = src
    if text.endswith("\n"):
        text = String(text[byte = 0 : text.byte_length() - 1])
    for line_slice in text.split("\n"):
        var line = String(line_slice)
        if line.startswith("target datalayout"):
            line = String('target datalayout = "') + DATALAYOUT_MCU + '"'
        elif line.startswith("target triple"):
            line = String('target triple = "') + TRIPLE_MCU + '"'
        # Lifetime intrinsics changed signature in newer LLVM; they are
        # only optimization hints, so drop declares and calls entirely.
        if line.find("llvm.lifetime") != -1:
            continue
        # Debug records -> old intrinsic form (keeps variable info).
        var rec = _downgrade_dbg_record(line)
        if rec[0]:
            if rec[1].byte_length() == 0:
                continue
            out += rec[1] + "\n"
            converted_dbg = True
            continue
        # Strip riscv-specific function attributes.
        line = _remove_quoted_attr(line, "target-features", False)
        line = _remove_quoted_attr(line, "target-cpu", True)
        # Downgrade attribute syntax newer than the system LLVM.
        line = line.replace("captures(none)", "nocapture")
        line = _remove_paren_attr(line, "captures(", ")")
        line = _remove_range_attr(line)
        line = _remove_token(line, "dead_on_return")
        line = _remove_token(line, "dead_on_unwind")
        line = _remove_token(line, "nocreateundeforpoison")
        line = _remove_paren_attr(line, "initializes((", "))")
        # Float constant syntax new in LLVM: f0x… -> classic hex forms.
        line = _downgrade_float_literals(line)
        line = _patch_empty_attr_group(line)
        out += line + "\n"
    if converted_dbg:
        # Python joined this block as one more "line", producing a
        # trailing blank line; keep output byte-identical.
        out += DBG_DECLARES + "\n"
    return out
