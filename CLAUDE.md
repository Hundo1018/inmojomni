# inmojomni — project rules for Claude sessions

Bare-metal RP2040 (Arm, via IR retarget) + RP2350 (Hazard3 RISC-V, native)
firmware + SDK in pure Mojo. Public repo, actively promoted:
**every public claim must have a machine-checked gate** (test, checksum, or
diff). If you add a capability, add its gate in the same change; if you can't
gate it, don't claim it. Global rules: `~/.claude/CLAUDE.md`.

## Policy

- **Tracks the newest STABLE Mojo release** (conda.modular.com/max; user
  decision 2026-09-30). Pins in pixi.toml are exact (`==`): the packaging
  path resolves the newest match and stable 1.0.0 shipped with riscv32 emit
  disabled. Bump = edit the 5 Mojo pins (`mojo-compiler` ×3, `mojo`,
  `modular`) → `pixi update` → `test-host` + `build-rp2350` → hardware gates.
  CI `stable-latest` (daily) lifts the Mojo pins and runs the host tier:
  red = a new stable release needs work, priority zero.
- **Host LLVM is pinned too** (`llvm-tools`/`clang-23`/`lld` 23.1.2 from
  conda-forge; `HOST_LLVM_MAJOR` in tools/retarget.mojo, checked by
  test_retarget). Keep it the newest conda-forge release: Mojo's own LLVM is
  trunk (24 on 1.1.0), and the retarget only works without downgrade rules
  while the gap is small.
- Firmware builds use `-D ASSERT=none` (`MOJO_FIRMWARE_FLAGS` in
  tools/build.mojo; user decision 2026-09-30).
- Docs: README/BENCHMARKS = English, rigorous, no hype adjectives.
  docs/ROADMAP.md = internal, zh-TW. Never mention "pico-drone" or
  "pico-mojo" in public docs (user directive; project name is inmojomni).
- Tooling language: new tools are Mojo (`tools/*.mojo`). Python exists only
  as test rig (run_tests.py, hil.py, dap_client.py) — don't grow it.
- Commit/push: user has authorized push to THIS repo. Commit messages end
  with the Claude co-author line. CI must be green before you call a push done.

## Commands (all via pixi; `pixi run <task>`)

| build / flash / uf2 / build-debug / flash-debug | firmware via tools/build.mojo |
| test | full suite; hardware stages auto-skip without probe |
| test-host | host-only tier — minimum bar for ANY change |
| bench → chart | 4-language benchmark (needs probe+clang+rustc) → docs/assets/benchmarks.svg |
| sizes | 4-language blink size comparison (no hardware) |
| svd-update | refresh .vscode/rp2040.svd from pinned pico-sdk |
| flash-rp2350 / flash-debug-rp2350 | Pico 2 build + SWD flash (openocd fork) |
| bench-rp2350 / features-rp2350 / piomc-rp2350 / periph-rp2350 / rtt-rp2350 | Pico 2 HIL gates (flash-mailbox loop) |
| debug-test-rp2350 | Pico 2 gdb/openocd debug gate |

| build-rp2350 | Pico 2 build without flashing (host, no probe; also in CI) |

Output filters are mandatory — canonical recipes live in
`~/.claude/playbooks/00-diagnosis.md` §1. The `/summary/,$p` sed trick works
ONLY for `test`/`test-host` (they print `=== summary ===`); for builds use
`| grep -cE "error"` first, rerun filtered only on nonzero.

## Hardware facts (this user's bench)

- One Pico + one Pico 2 + one CMSIS-DAP Debug Probe. **The probe is a
  mutex** — never let two agents/commands use SWD concurrently, including
  background polls (openocd gdb-server counts: kill it when done).
- RP2350 flash/debug go through ~/.local/bin/openocd (raspberrypi fork;
  Ubuntu's 0.12 lacks rp2350 targets). Flash: `pixi run flash-rp2350`.
  Debug gate: `pixi run debug-test-rp2350`. probe-rs still cannot attach
  to a running Hazard3. Consult wren6991/hazard3 repo for core facts
  (user directive; see memory).
- SWD wiring is marginal: tools already flash at `--speed 1000 --verify` with
  one retry (hil.py / hil.mojo). Don't remove these. Unverified flashes have
  silently corrupted and produced phantom bugs (cost: a full bisect session).
- If SWD dies (reads fail, "device not responding"): try 1 MHz + verify; if
  USB enumeration is gone (error -71 in dmesg), software cannot recover —
  ask the user to replug the probe (and possibly reseat the 3 SWD wires).
- Never poll SWD while a timing run executes: each probe-rs attach steals
  ~6 ms of AHB from the core. Sleep past the run, then read.
- RAM survives reset: zero mailboxes/counters before reading them (stale
  benchmark residue has masqueraded as results).
- Leave the board running blink at session end (`pixi run flash`).

## Mojo gotchas (all verified on hardware/IR; keep list updated)

- `_ = read32(addr)` **discards the volatile load in the elaborator** — it
  never reaches LLVM. Route the value into a compare whose branch has a side
  effect (pattern in src/pico/multicore.mojo `_fifo_drain`).
- `len(myString)` is a compile error → `s.byte_length()`; slice `s[byte=a:b]`.
- Bare int literals may not compare with UInt32 on newer nightlies — write
  `UInt32(10) > x`, not `10 > x` (packaging builds resolve the NEWEST nightly,
  not the lockfile, so this breaks there first).
- A `comptime VALUE = f()` whose type holds an `Array` cannot be
  `ImplicitlyCopyable`; use it at runtime via `materialize[VALUE]()`
  (`comptime assert VALUE.field` works directly). See `Asm` in src/pico/pio.mojo.
- No module-level `var` (globals unsupported); no regex/json/socket in stdlib;
  `std.subprocess.run` goes through a shell, captures stdout, does NOT raise
  on nonzero exit — use the `; echo __RC$?` marker pattern (tools/build.mojo `sh`).
- Mojo ≥1.0 (verified on 1.1.0 stable and 1.2.0.dev2026092905, host tier):
  - `InlineArray` → `Array` (params `T`, `length`); no alias left.
  - `UnsafePointer` → `Pointer`; `.load`/`.store` → `.unsafe_load`/
    `.unsafe_store` (volatile ops still reach LLVM; count is gated).
  - `x = String(x[byte=a:b])` is an aliasing error → go through a temp
    (`var t = String(x[byte=a:b]); x = t^`).
  - Bounds checks on by default: a failing check formats through a 2 KB
    stack buffer + `__aeabi_memcpy` (undefined on RP2040). Hence
    `-D ASSERT=none` for firmware.
- RP2040 codegen: functions must be `nounwind` (build.mojo passes
  `opt -force-attribute=nounwind`), or llc emits EHABI entries referencing
  `__aeabi_unwind_cpp_pr0` and libgcc's unwinder (needs memcpy) gets linked.
- Mojo's shipped LLVM has no ARM backend: `llvm_project.bzl` BACKENDS =
  AArch64/RISCV/X86, although `HostTraits::isSupported` already accepts
  `isARM()`. Adding "ARM" there is the path to deleting tools/retarget.mojo
  (see ROADMAP). Building the compiler needs GitHub archive downloads that
  cloud sessions block (403), so do it on the user's machine.
- `import` paths: `std.ffi.external_call` (not std.sys.ffi). When unsure,
  probe-compile a 6-liner before writing real code.

## Recipes

**Add an on-target test:** bump `NUM_TESTS` in tests/on_target/main.mojo →
write `def test_x() -> Bool` → add `report(idx, test_x())` in start() →
append name to `TEST_NAMES` in tools/hil.py → update README test-count →
`pixi run test` with probe. Scratch RAM for test state: 0x20024000+ (document
each address in the test file).

**A Mojo release emits IR the pinned LLVM rejects:** first bump
`llvm-tools`/`clang-NN`/`lld` to the newest conda-forge release (and
`HOST_LLVM_MAJOR` in tools/retarget.mojo, `CLANG` in tools/build.mojo);
add the construct to MODERN_IR in
tests/host/test_retarget.mojo. Only if no LLVM release accepts it, add a
string-scan rule to tools/retarget.mojo. Volatile-op preservation is
checked automatically; never weaken it.

**Add a driver:** registers into src/pico/rp2040.mojo (datasheet § in comment)
→ module in src/pico/x.mojo (docstring with usage example) → export in
__init__.mojo → on-target test → README SDK section + tests table.

**Verify like the project does:** parity gates (md5 the ELF before/after a
tooling refactor), goldens (runtime/boot2.bin), spread gates (bench <2%),
checksums across implementations. Copy these patterns, don't invent weaker ones.
