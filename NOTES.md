# 2010 FIFA World Cup South Africa – PC Port Notes

## Current State (2026-10-17, after Round 23) - one page

**One line.** The port boots, loads both XEXs, runs ~48 s, then dies on a *new* unregistered
indirect-call target `0x836A24B0` (a 4-instruction tail fragment); the first-boot crash at
`0x83884CA0` is resolved by the override, and the original `0x0006C6B8` null-field read is
tolerated by the temporary on-demand guest-virtual commit workaround (one page committed). The
game loads menus, processes XAM/XContent, starts APU/GPU, then stops on the vtable call to
`0x836A24B0`.
~3.3 s) and reach a *different* wall: an indirect call to unrecompiled guest `0x83884CA0` ->
`[FATAL] Call to invalid or unregistered function` (exit `0xC0000409`). Round 21's causal story
("a fault in Xenia's virtual heap walks the guest page table and lazily commits the page, 3x per run")
is **retracted**: Xenia's `AccessViolationCallback` has the *same* `!= kGuestPhysical` early-out
(so it cannot commit a virtual page), and those 3 lines are Xenia kernel-init allocation lines
logged next to `Added handle:F8000000 for class xe::kernel::XObject`, not the guest read. Why Xenia
has that page committed is still **UNKNOWN**; the on-demand commit is a behavioural approximation of
Xenia's *observable* result (the guest reads 0), not a copy of a Xenia code path. So the stop is still
not a missing guest function, not a value divergence and not an override - but the *next* blocker
after the page fix is a missing recompiled function (`0x83884CA0`). Round 17's `r3 != 0` claim remains
retracted (Round 21).

Evidence, corrections and dead ends from Rounds 7-11 are archived in
[`NOTES_archive.md`](NOTES_archive.md); this file keeps the stages, this summary and Round 12.

**Verified (measured, reproducible)**
- Host<->guest translation is `host = base + guest` with `base` = a runtime-allocated, 4 GB-aligned
  guest memory base: `0x1_0000_0000` in every run logged except one, which used `0x2_0000_0000`
  (VERIFIED from the runtime's own AV line, 30+ occurrences:
  `read of guest 0x0006C6B8 (host 0x000000010006C6B8)`); the generated macro is
  `REX_LOAD_U32(x) = bswap32(*(u32*)(base + (u32)x + REX_PHYS_HOST_OFFSET(x)))` with
  `REX_PHYS_HOST_OFFSET(a) = (a >= 0xE0000000) ? 0x1000 : 0` (VERIFIED in `codegen_pch_h.inja.h`).
  Debugger guest reads must be byte-swapped (`bswap32`).
  A "`host = guest + 0x8000_0000`" rule was briefly written here in Round 13 - **withdrawn**, see
  Round 14 item 0. The mirror value `0x83A4648C -> 0x103A4648C` is UNVERIFIED (a hypothesis about a
  masked 0x80000000 window that no log or macro supports; the generated code does not mask).
- Singleton object at `0xBF3C57D0` (deterministic). Ctor `sub_82C50EF0`; publish
  `sub_82C6AFC8+0xF4`; populate `sub_82CA1138` writes `+0x08/+0x0C/+0x10`; `+0x00 = obj-8`;
  `+0x64` stays `0`.
- Complete `+0x64` write history, all runs/threads: **3 stores, all before the read** (memset-zero,
  memset-poison `0xCDCDCDCD`, ctor-zero). A valid pointer is never stored.
- The 83 no-block stubs (Round 14): **71 leaf / 12 epilogue-tail-fragment**; **14 are reached by a
  real call** (`sub_X(ctx, base)` emitted), **69 only by `goto loc_X`** (their body is already
  emitted inside the caller, so the empty stub is dead weight); none reads an incoming non-volatile;
  4 have a CFG extent that contains a sibling entry (all 4 in the harmless set). Execute breakpoints
  must use the `PPCFuncMappings` host pointers, never `guest + base` (exe base `0x140000000`, dll base
  `0x180000000`); no ICF folding of any sampled stub (24/24 distinct host pointers).
  **Round 15 applied the 14 called ones** (Tier 1, with CFG-validated exclusive `end`s); the no-block
  count fell **83 -> 69** and the 69 left are exactly the 65 Tier-2 + 4 Tier-3. **The AV is unchanged.**
- Fault chain: `sub_82CBD7E0` -> `sub_82C501D0` (`r3 = *(0x83A4648C)`) -> `sub_832BF128`
  (`r3 = *(r3+100)`) -> `lwzx r28,r3,r11` with `r11 = 0x6C6B8`; AV = read of guest `0x6C6B8` on the
  **FEThread (guest 26)**, 0-1 ms after it names thread 35.
- **Round 17 - RETRACTED by Round 21: Xenia does execute `0x82CBD80C`, but its `r3` there is 0.**
  The firing counts still stand (`break_on_instruction = 0x82CBD80C` = **5,029 int3 in 100 s** and
  **3,674 int3 in the 80 s control**, ~46-50/s, first hit 15.4/16.9 s in, one host thread, the C
  run's first hit just after `SetThreadName(35, ...)`), but the *conclusion drawn from the condition
  run was wrong*: the conditional path (`break_condition_gpr >= 0`) does **not** emit an int3 - it
  compiles to `CallNative(TrapDebugBreak)`, which only logs
  `tw/td forced trap hit! This should be a crash!` (and int3s only when `break_on_debugbreak` is
  true, which Round 17 turned **off** in the copy). So "condition run = 0 int3" measured nothing.
  Re-read with the correct oracle, that same run B log holds **3,618 forced-trap lines**, i.e.
  `r3 == 0` was **true** at every execution - the opposite of what the bullet used to claim. Round 21
  reproduces it in both directions: `r11 == 0x6C6B8` (provably true at that instruction) -> **3,873**
  trap hits; `r3 != 0` -> **0**. See Round 21 for the source citations and the resolution.
- **Round 18: the accessor setter is dead, and the init order is ctor/publish once each.** `0x82BDB2F8`
  (the bare `+0x64` setter the accessor table pairs with the getter) is **never executed by Xenia**
  - 0 hits in an 80 s armed run and **0 direct branch sites** in the image (two independent methods).
  The ctor `0x82C50EF0` and the publish `0x82C6AFC8` each execute **exactly once**, before worker 35
  exists; statics prove `0x82C6AFC8` allocates 0xC4 bytes, `bl 0x82C50EF0` at +0x28, then
  `stw r3, 25740(r11)` with `r11 = 0x83A40000` - i.e. the singleton global `0x83A4648C`. The getter
  and `0x82CBD80C` run ~58/s starting **after** the naming and the worker's first
  `RtlInitializeCriticalSection` (reproduced in 3 runs). So the `+0x64` writer is not reachable
  through the accessor table, and the field is already valid when the FEThread's per-frame path
  reads it - the writer is still unidentified (Round 18).
- **Round 20 (1 Xenia batch = 4 x 80 s on the copy + 1 run of our build; no rebuild, no override
  change): the "producer" story fails on measurement.** In Xenia, armed on `0x82C9A4B0`
  (`break_on_instruction` = 2194252976, read back) the producer **never executes** in 80 s (**0
  int3 in the whole process**), while in the same batch `sub_82D03C90` fires **6x** (all guest
  thread 26/FEThread, first at log line 10910 = +4905 from thid26, i.e. *before* the control run's
  first `0x82CBD80C` read at +5206), `sub_82D1F100` fires **2x** (guest 26, line 12955 = +6860,
  *after* the read) and `sub_82D22390` fires **30,670x** (30,667x guest 26/FEThread + 3x guest
  6/Main XThread, first at line 9105 = +3029). Host tids were mapped to guest threads through the
  run's own `XThread::Execute ... native=` lines. The instruction that kills our port, `0x82CBD80C`,
  is executed by **guest thread 26 (FEThread)** in Xenia (control run: host tid 13956 = native
  0x3684 = `XThread::Execute thid 26`). Our build, DR0..DR3 execute breakpoints on the four host
  entries resolved **at runtime from the module's own `PPCFuncMappings`** (base + rva `0x7313000`,
  87,183 entries read): **0 hits for all four before the AV**; the AV is the runtime's own
  `Unhandled guest access violation: read of guest 0x0006C6B8 (host 0x000000010006C6B8)`, 3.26 s
  in, guest handle 0xF8000354. So no A/B/ROOT/producer code runs before our fault, **and in Xenia
  the `+0x64` value is not established by the producer either**. Round 19's "the writer is
  identified" is therefore **not confirmed by execution** - the Round 20 section records the
  contradiction and the two surviving explanations.
- **Round 20 item 1: the `+0x18`-state / `+0x23`-gate object is *not* the singleton - it is a
  separate polymorphic manager.** The object is 0x44 = 68 bytes, built by ctor **`0x82D041B8`**
  (`alloc(68,0,"rw45 tag")` + `stw r9,0(r3)` at `0x82D17CC4`, i.e. vptr `0x8244CE04`) inside the
  factory **`sub_82D17A50`**; its sibling 0x80-byte object (ctor `0x82D04048`, vptr `0x8244CDFC`)
  has the identical state/gate field layout. The singleton is the 0xC4-byte **POD** built by
  `0x82C50EF0` (`addi r11,0; stw r11,0..0xC0(r3)`, no vptr store at all). `sub_82D22390` (ROOT) is
  that manager's **virtual command dispatcher** - case `r4==1` initialises exactly this layout
  (`+0x18=0, +0x1C=3, +0x20..0x22=0, +0x23=1` gate armed, `+0x24=-1, +0x28=-1, +0x2C=0`). Item 4:
  `.rdata 0x8244CE10` is the manager's **vtable slot** (vtable `0x8244CE04`, ROOT at `+0x0C`);
  `.rdata 0x82607418` is **not** a dispatch vector - it is ROOT's own entry in the guest's static
  function-extent table (`{code ptr, 0x4000_0000|(ninstr<<8)|flags}`), i.e. constant .rdata.
- **Round 19 (static only, no runs): the writer is identified - `sub_82C9A4B0`.** It is a plain `new`
  block: `alloc(0x6C6D0, 0, "rw45 tag")` at `0x82C9A4E0`, `bl 0x82C8D278` (the ctor, returns `this`)
  at `0x82C9A4EC`, then **`stw r3, 100(r31)` at `0x82C9A4F8`** with `r31 = this` (set by `mr r31,r3`
  on entry). Its only two callers (`0x82D03D4C` in `sub_82D03C90`, `0x82D1F234` in `sub_82D1F100`) both
  do `bl 0x82C501D0` - the **singleton getter** - immediately before, so the store target is provably
  `*(0x83A4648C) + 0x64`. `0x6C6D0 = 0x6C6B8 + 0x18` and it is the **only** allocation in either
  image in `0x6C600..0x6C800`, i.e. the object's last field is exactly the `+0x6C6B8` element count
  that the faulting `lwzx` reads (`+4` is the array base pointer, stride 8144, per the decoded
  accessors `sub_82C71858` / `sub_82C71740`; the bare setter `0x82C718D0` writes the count). Our
  build's DR write history of `+0x64` (3 stores, all zero/poison - the `alloc-failed` arm of the same
  block would still be a 4th store) says the call never happens here. The call is gated by
  `state == 8` at `0x82D03CD8` plus the one-shot byte `this+0x23` at `0x82D03D1C`, and the chain's root
  `sub_82D22390` has **0 `bl` callers** (entered only via `.rdata` `0x8244CE10` / `0x82607418`).
  Which of those guards excludes our build is the one thing still OPEN (needs a run or the GUI words).
- Thread 35 is created CREATE_SUSPENDED, `startup = 0x8282FD10`, `start = 0x828360B8`,
  `ctx = 0x40103E40`, then named, priority 1, affinity `0x10`, then resumed - identical numbers in
  Xenia's log and in our runtime's recompiled call site. Its guest address is registered and its
  name string resolves (`rw45_pkg_factory_seg`); its body writes nothing to `+0x64`.
- Xenia's thread 35 does exactly: 2 x `KeTlsSetValue`, `ObReference`/`ObDereference`, then
  **88 x `RtlInitializeCriticalSection`** (stride `0x60`) - and no other kernel call. Xenia's
  level-3 log contains **no wait calls anywhere** (0/197,511 lines), so its silence about waits is
  a logging gap, not evidence.
- Our worker, by contrast, runs ~15.6 ms of guest CPU then parks in a guest wait
  (`sub_8282DD28+0x19A`, handle `0xF28`, no timeout).
- cvar surface: `ignore_thread_priorities` (ours **true**; Xenia **false** - the only real
  difference), `ignore_thread_affinities` (both true), `protect_zero` (both true),
  `writable_executable_memory` (both true); **`kernel_build_version` and `console_type` do not
  exist in our runtime at all**. `log_high_frequency_kernel_calls` is defined but never read.
- 5-run cvar matrix (incl. `--ignore_thread_priorities=false`): the AV is **unchanged** in all of
  them.
- Of the 83 "no blocks" stubs: **82 are real PPC code, 1 is code with Xenon VMX128 words, 0 are
  padding/data**; all 83 are reachable (14 have emitted `sub_XXX(ctx,base)` call sites - Round 14
  recount; an earlier "22" came from a scan that also counted `goto loc_X` sites) and
  they are exactly the 83 functions that could not seal (console log: 92,659 `DISCOVERED` vs
  83 `cannot seal (0 unresolved)`). None sits inside the singleton code, the fault chain, or
  the worker bodies; none writes `+0x64`.
  padding/data**. None sits inside the singleton code, the fault chain, or the worker bodies.
- Both override copies: 266 entries, byte-identical, SHA-256 `FFB03BFC...`.

**Inferred (not proven)**
- Leading hypothesis: the `+0x64` assignment is a path that never executes here (narrow variant:
  the factory must serve a creator request first).
- Competing hypothesis: the assigner is reached only through an indirect `bctr` dispatch that
  mis-routes in our build (12 `bctr` sites in `sub_82CBD7E0` alone).
- The 867-function gap explanation is unverified (see Stage 3/5).
- The two `0x8370xxxx` stubs near the worker chain are the most interesting of the 83 as candidate
  silently-returning stubs on the worker's path, but nothing ties them to thread 35 yet.

**Open items / next experiments (each needs approval)**
1. Inverted throttle: 1 ms on / 100 ms off and 2 ms on / 200 ms off, ~3 s, must **not** break on
   the AV - the only configuration that gives the factory wall time to serve an already-issued
   request.
2. Data references to the only `+0x64` setter `sub_82BDB2F8`: does any guest table row point at it?
3. Resolve the 12 `bctr` sites in `sub_82CBD7E0` through the guest pointer tables.
4. Counter on host `RtlInitializeCriticalSection` (hardware exec breakpoint or int3) to compare our
   worker's critical-section count with Xenia's 88 - the decisive same-branch test.

---

## Game Identity

| Field | Value |
|---|---|
| Title ID | 0x454108E4 |
| Media ID | 0x24473D52 |
| Region | PAL |
| Version | 0.0.0.2 |
| Title update | None |

## Modules

### default.xex
- SHA-256: `d0df5465e077eaebeadda252c786d9322551ab13ef23aad461836e510971337d`
- OriginalPE: `fifalauncherzf.exe`
- Load base: 0x82000000, size: 0x1F0000
- .text: 0x82050000, size: 0x11067C
- Entry point: 0x820FB900
- Loads `fifadllzf.xex` at runtime via XexLoadImage

### fifadllzf.xex
- SHA-256: `462676f9fbab83530c2659e79aa43e3dbe81b43dc917db9299933c19fa34905d`
- Load base: 0x82300000, size: 0x1850000
- .text: 0x82650000, size: 0x1288DB4
- Entry point: 0x82832840
- Loads via manifest `guest_path = "game:\\fifadllzf.xex"` → target `worldcup2010_fifadllzf`

## XEX Compression

Both XEXs: `encryption_type=0x0001` (AES-128) + `compression_type=0x0002` (LZX).
Raw instruction bytes at guest virtual addresses **cannot** be read by seeking into the .xex
file directly. rexglue decompresses them in memory during codegen; no decompressed image is
written to disk.

## ReXGlue SDK

- Pinned commit: `c94f5ebdcb3c9d1a460ca48e04f9758448f8d518`
- Built: `ReXGlue/out/win-amd64/Release/rexglue.exe` (3.1 MB)
- Confirmed version: `v0.10.0.2-dev.gc94f5eb` (matches commit prefix)

## Missing Kernel Exports

Only `XUsbcamGetState` and `XUsbcamSetConfig`. Already stubbed in
`Installer/recomp-template/src/stubs.cpp`.

## fifadllzf_overrides.toml

> **Status (2026-10-17, corrected in Round 12):** both copies contain **266 function
> entries** (11699 bytes each, byte-identical: SHA-256
> `FFB03BFC9CF50E0932E8A1FDA40CC8D1950E9063A26C81329A05430D62A7787D`, re-verified
> 2026-10-17). The first entry is `"835F7700" = { end = 0x835F7714 }` (Stage 6); the
> other 265 were added by the Stage 6b-6d `.rdata`/`.data` target batches described in the
> Stage 6 sections below. A backup copy of both files is in `D:\FWC10\_backups\`.

`native_libc_hooks.cpp` stays `#if 0` disabled — no addresses for this binary yet.

---

## Stage 3 – Codegen (2026-10-16)

**Workspace:** `C:\FWC10B\fwc10stage4\WorldCup2010Rex`
**Command:** `rexglue.exe --log-file codegen.log --log-level debug codegen worldcup2010_manifest.toml`

### Summary

| Metric | Value |
|---|---|
| Exit code | **0** |
| Runtime | 9 min 54 s |
| Files written | 706 |
| Total size | 361.1 MB |
| default.xex | 20 × `worldcup2010_recomp.N.cpp` ≈ 19.8 MB |
| fifadllzf.xex | 325 × `worldcup2010_recomp.N.cpp` ≈ 341.2 MB |

### Function Counts

| Category | Count | Source |
|---|---|---|
| Code bodies discovered | 92,659 | console log `DISCOVERED with N blocks` |
| Import thunks discovered | 432 | console log `DISCOVERED as import` |
| Total discovered | 93,091 | |
| Emitted `DEFINE_REX_FUNC` – default.xex | 4,728 | partition JSON + grep |
| Emitted `DEFINE_REX_FUNC` – fifadllzf.xex | 86,632 | partition JSON + grep |
| **Total emitted** | **91,360** | |

### Gap: 92,659 Discovered vs 91,360 Emitted (= 1,299)

The partition JSON is ground truth: 4,728 + 86,632 = **91,360** emitted bodies.

`register.cpp` has **91,792** `SetFunction` entries — 432 more than emitted bodies.
Those 432 are **import thunks**: kernel/XAM imports discovered at code addresses in
`.text`, registered via `SetFunction` to host-side stubs, but emitted with no
`DEFINE_REX_FUNC` body. They account for the full 432-entry gap between `SetFunction`
count and emitted count.

The remaining 1,299 - 432 = 867 is an **explained-away remainder, and the explanation is
UNVERIFIED**: "merged, de-duplicated, or alternate entry points" is a plausible guess, not a
measurement. 867 is simply what is left after subtracting the 432 import thunks. Treat the
867 as *unknown, not a defect* until a measured merge/de-dup count exists. The 432 import-thunk
part above **is** verified from `register.cpp`.

### Diagnostics

| Type | Count |
|---|---|
| `[warning]` "has no blocks – generating stub" | 83 |
| `[warning]` FindRecompiledModule (teardown) | 1 |
| `[error]` BaseHeap::Release (teardown) | 1 |
| Unresolved calls in generated .cpp | **0** |
| Unresolved branches in generated .cpp | **0** |
| Silent/omitted branch markers | **0** |
| Missing goto-labels | **0** |

The single `[error]` fires during guest memory teardown **after** all 706 files are
written. Exit code is 0. Cosmetic — no action needed.

### First 20 Diagnostics (verbatim)

```
[warning] Function 0x8211A170 has no blocks - generating stub
[warning] Function 0x826B37E0 has no blocks - generating stub
[warning] Function 0x82744A9C has no blocks - generating stub
[warning] Function 0x82744AF4 has no blocks - generating stub
[warning] Function 0x82744B08 has no blocks - generating stub
[warning] Function 0x8277F7BC has no blocks - generating stub
[warning] Function 0x8277F7C8 has no blocks - generating stub
[warning] Function 0x827B642C has no blocks - generating stub
[warning] Function 0x827C03EC has no blocks - generating stub
[warning] Function 0x827C0488 has no blocks - generating stub
[warning] Function 0x827C0498 has no blocks - generating stub
[warning] Function 0x827DA51C has no blocks - generating stub
[warning] Function 0x827DA8D8 has no blocks - generating stub
[warning] Function 0x828032DC has no blocks - generating stub
[warning] Function 0x82813FF0 has no blocks - generating stub
[warning] Function 0x82A63768 has no blocks - generating stub
[warning] Function 0x82ADF698 has no blocks - generating stub
[warning] Function 0x82ADF6B0 has no blocks - generating stub
[warning] Function 0x82BCBDB8 has no blocks - generating stub
[warning] Function 0x82DA6148 has no blocks - generating stub
```

All 83 stubs fall inside valid `.text` ranges: **1** in `default.xex`,
**82** in `fifadllzf.xex`. None are outside `.text`.

### No-Blocks Stubs – 3 Examples

Raw instruction bytes are not accessible (AES+LZX). The stubs are confirmed in
generated code.

**0x8211A170** — default.xex `.text`, `worldcup2010_recomp.5.cpp`

```cpp
DEFINE_REX_FUNC(sub_8211A170) {
    REX_FUNC_PROLOGUE();
}
```

Called by `sub_8211A178` via a PPC `b` tail-call:
```cpp
DEFINE_REX_FUNC(sub_8211A178) {
    REX_FUNC_PROLOGUE();
    // addi r3,r3,-8
    ctx.r3.s64 = ctx.r3.s64 + -8;
    // b 0x8211a170
    sub_8211A170(ctx, base);
    return;
}
```
The stub **silently returns** (no body, no trap). If the game calls this path at runtime,
the caller receives whatever was in r3/lr unchanged — likely incorrect game logic.

**0x826B37E0** — fifadllzf.xex `.text`, `worldcup2010_recomp.166.cpp`

```cpp
DEFINE_REX_FUNC(sub_826B37E0) {
    REX_FUNC_PROLOGUE();
}
```

No direct callers in generated code. Discovered via `.pdata` exception tables and
registered via `SetFunction`. Silently returns if called. Deferred — add an override
in `fifadllzf_overrides.toml` only if the game crashes at this address.

**0x82744A9C** — fifadllzf.xex `.text`, `worldcup2010_recomp.148.cpp`

```cpp
DEFINE_REX_FUNC(sub_82744A9C) {
    REX_FUNC_PROLOGUE();
}
```

Debug log shows: `FunctionGraph::sealAllReady: 0x82744A9C cannot seal (0 unresolved)` —
rexglue found zero decodable PPC instructions at this address (data padding or unreachable
compiler-generated code). No callers in generated code. Silently returns.

**All stubs:** `REX_FUNC_PROLOGUE()` sets up the call frame, then the function exits.
LR is restored, so control returns to the caller without a host crash. Output registers
expected by the caller will hold their incoming values.

### verify_direct_branches.py

Script shipped with wrong glob (`fifastreet_recomp.*.cpp`). **Fixed** to
`worldcup2010_recomp.*.cpp`.

Result after fix (345 files checked):
```
Files checked: 345
Direct branches verified: no unresolved calls, branches, or omitted CTR jumps.
```

`verify_ctr_region.py` and `verify_allocation_region.py` contain FIFA Street-specific
addresses and are **not called by any build script**. No changes needed.

---

## Stage 4 – Pre-Compile Checks (2026-10-16)

### Check 1 — fifadllzf_overrides.toml (both copies)

- Workspace `C:\FWC10B\fwc10stage4\...\config\fifadllzf_overrides.toml`: `[functions]` only, empty ✓
- Template `Installer\recomp-template\config\fifadllzf_overrides.toml`: `[functions]` only, empty ✓

### Check 2 — Glob fix + verify script status

- `verify_direct_branches.py`: glob fixed `fifastreet_recomp` → `worldcup2010_recomp` ✓
- `verify_ctr_region.py` and `verify_allocation_region.py`: not invoked by build scripts,
  no change needed ✓

### Check 3 — BuildWorldCup2010.ps1 tail

File: 9,791 bytes, 267 lines. Final content (verified from raw bytes):
```powershell
    Stop-Transcript | Out-Null
    Write-Host "Source build complete: $Output ($GraphicsApi)"
    return
}

Stop-Transcript | Out-Null
```
Ends at `Stop-Transcript | Out-Null\n`. No appended content. Parses correctly.
The manifest blob seen in an earlier session was from the template's
`worldcup2010_manifest.toml` being read in the same batch — a separate file.

### Check 4 — Discovered vs emitted gap

See Stage 3 section above. Short answer: 432 entries in `register.cpp` are import thunks
with no `DEFINE_REX_FUNC` body. Partition JSON (4,728 + 86,632 = 91,360) is the exact
emitted count. Full discrepancy accounted for.

### Check 5 — No-blocks stubs

See three examples in Stage 3 above. Key points:
- All bodies: `DEFINE_REX_FUNC(sub_X) { REX_FUNC_PROLOGUE(); }` — silently return, no trap
- 0x8211A170: one known caller (tail-call from 0x8211A178 in default.xex)
- 0x826B37E0, 0x82744A9C: discovered via `.pdata`, no call chain in generated code
- XEX files are AES+LZX; raw instruction words not readable without decryption

### Check 6 — git status

`D:\FWC10\fifa-street-pc-port`: **clean** (nothing to commit, working tree clean) ✓

---

## Files Modified by These Sessions

| File | Change |
|---|---|
| `Installer/recomp-template/config/verify_direct_branches.py` | Glob `fifastreet_recomp` → `worldcup2010_recomp` |

---

## Stage 5 – Compile Build Result (2026-10-16)

**Build status: SUCCESS** — exit code 0, no compile errors, no linker errors.

All 1,121 ninja targets built. Compiler: Clang 23.1.3.

### Output binaries (`dist\Output`)

| File | Size |
|---|---|
| `worldcup2010.exe` | 7.7 MB |
| `worldcup2010_fifadllzf.dll` | 117.3 MB |
| `rexruntime.dll` | 9.7 MB |
| `rexgpu-xenos.dll` (root + Backends\D3D12) | 2.9 MB |
| `TracyClient.dll` | 231 KB |

### PATH fix required

`BuildWorldCup2010.ps1` calls `cmake` and `ninja` by name but neither is on the
system PATH by default. They ship with Visual Studio 2022 (v18). Before running the
script, prepend both to the session PATH:

```powershell
$cmakeBin = "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin"
$ninjaBin  = "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja"
$env:PATH  = "$cmakeBin;$ninjaBin;$env:PATH"
powershell -ExecutionPolicy Bypass -File "Installer\BuildWorldCup2010.ps1" `
    -GameData "...\dist\GameData" -Output "...\dist\Output" `
    -Workspace C:\FWC10B\fwc10stage4 -SourceBuild -Jobs 2
```

The workspace flag `-Workspace C:\FWC10B\fwc10stage4` resumes the existing codegen
output so codegen is not re-run on incremental builds.

### Unresolved item A — 1,299 function gap

- **Discovered code bodies:** 92,659 (console log `DISCOVERED with N blocks`)
- **Emitted `DEFINE_REX_FUNC`:** 91,360 (partition JSON: 4,728 default + 86,632 fifadllzf)
- **Gap:** 1,299

Root cause: `register.cpp` has 91,792 `SetFunction` entries — exactly 432 more than
the 91,360 emitted bodies. Those 432 are **import thunks**: kernel/XAM imports
discovered at code addresses in `.text`, registered via `SetFunction` pointing to
host-side stubs, but emitted without a `DEFINE_REX_FUNC` body. The remaining ~867 (**UNVERIFIED** - see Stage 3, "Gap") are
alternate entry points or functions merged during iterative analysis.

No fix needed — this is normal ReXGlue behaviour.

### Unresolved item B — 83 "no blocks" stubs

All 83 fall inside valid `.text` ranges (1 in `default.xex`, 82 in `fifadllzf.xex`).

**Generated body (all 83 identical):**
```cpp
DEFINE_REX_FUNC(sub_XXXXXXXX) {
    REX_FUNC_PROLOGUE();
}
```

Behaviour: `REX_FUNC_PROLOGUE()` sets up the call frame, then the function exits
immediately with no body. The LR is restored so control **returns to the caller —
no host crash, no trap**. Output registers expected by the caller retain their
incoming values, potentially corrupting game logic.

These stubs were discovered at addresses where rexglue found zero decodable PPC
instructions (data padding, unreachable code, or misidentified `.pdata` references).
They will only matter if actually executed at runtime. If the game crashes at one of
these addresses, add an override in `fifadllzf_overrides.toml`.

Known stubs with callers:
- `0x8211A170` — called by `sub_8211A178` via PPC `b` tail-call in `default.xex`

Stubs with no generated callers (discovered via `.pdata`):
- `0x826B37E0`, `0x82744A9C` (and 80 others in `fifadllzf.xex`)

---

## Stage 6 – First-Boot Crash Fix at 0x835F7700 (2026-10-17)

### The crash (old boot log)

`C:\FWC10B\firstboot_runtime.log` (log lines 184/185):

```
[error] [cpu] INVALID INDIRECT CALL: target=835F7700 LR=83616654 CTR=835F7700 r1=7019E170 r2=00000000 r3=BBACA104 r11=835F7700 r12=83616CDC
[critical] ... FATAL Call to invalid or unregistered function at guest address 0x835F7700
```

An indirect call (`CTR = 0x835F7700`) landed on a `.text` address that codegen never
registered as a function. Fix: add an explicit function-boundary override so codegen
recompiles it.

### Condition 1 — `fifadllzf_overrides.toml` schema (quoted from source)

`ReXGlue/src/codegen/config.cpp` lines 177–210:

```cpp
  // [functions]
  if (auto functionsTable = toml["functions"].as_table()) {
    size_t added = 0;
    for (auto& [key, value] : *functionsTable) {
      std::string keyStr(key.str());
      auto addrOpt = ParseHexAddress(keyStr);
      ...
      FunctionConfig fcfg;
      fcfg.size = (*table)["size"].value_or(0u);
      fcfg.end = (*table)["end"].value_or(0u);
      fcfg.name = (*table)["name"].value_or(std::string{});
      fcfg.parent = (*table)["parent"].value_or(0u);
      fcfg.shareRegisters = (*table)["share_registers"].value_or(false);

      if (fcfg.size && fcfg.end) {
        REXCODEGEN_ERROR("Function 0x{:08X}: cannot specify both 'size' and 'end'", address);
        continue;
      }
      if (fcfg.end && fcfg.end <= address) {
        REXCODEGEN_ERROR("Function 0x{:08X}: 'end' (0x{:08X}) must be greater than address",
                         address, fcfg.end);
        continue;
      }
```

`ReXGlue/include/rex/codegen/config.h` lines 45–59:

```cpp
struct FunctionConfig {
  uint32_t size = 0;    // Explicit size in bytes (mutually exclusive with end)
  uint32_t end = 0;     // End address, exclusive (mutually exclusive with size)
  std::string name;     // Custom symbol name (empty = auto-generate sub_XXXXXXXX)
  uint32_t parent = 0;  // Parent function address (0 = standalone, non-zero = chunk)
  bool shareRegisters = false;
  // Get effective size (prefers size over end)
  uint32_t getSize(uint32_t address) const {
    return size ? size : (end > address ? end - address : 0);
  }
  bool isChunk() const { return parent != 0; }
};
```

**Schema summary**

| Item | Value |
|---|---|
| Table name | `[functions]` |
| Key | hex address **string** (e.g. `"835F7700"`) |
| Value keys | `size`, `end`, `name`, `parent`, `share_registers` (all optional) |
| `end` semantics | **EXCLUSIVE** end address (`getSize` = `end - address`) |
| Constraint | `size` and `end` are **mutually exclusive** |
| Constraint | `end <= address` is rejected with an error |
| Default name | `sub_XXXXXXXX` (auto) |

### Condition 2 — raw bytes and disassembly at 0x835F7700

The XEX is AES-128 + LZX. A standalone decompressor (reusing the repo's
`rijndael-alg-fst.c` + libmspack `lzxd.c`) produced a decompressed image
`fifadllzf.dec.bin` of size `0x1850000` (25,493,504 bytes), a valid `MZ`/PE image.
Guest VA maps to file offset `VA - 0x82300000` (verified against the PE section
table). Raw big-endian words re-verified directly from that image:

```
VA 0x835F76D8: 3863FFF8   addi    r3,r3,-8
VA 0x835F76DC: 548B063F   clrlwi. r11,r4,24
VA 0x835F76E0: 81630000   lwz     r11,0(r3)
VA 0x835F76E4: 41820010   beq     cr0,0x835F76F4
VA 0x835F76E8: 816B001C   lwz     r11,28(r11)
VA 0x835F76EC: 7D6903A6   mtctr   r11
VA 0x835F76F0: 4E800420   bctr
VA 0x835F76F4: 816B0020   lwz     r11,32(r11)
VA 0x835F76F8: 7D6903A6   mtctr   r11
VA 0x835F76FC: 4E800420   bctr
VA 0x835F7700: 2B030000   cmplwi  cr6,r3,0
VA 0x835F7704: 38630008   addi    r3,r3,8
VA 0x835F7708: 4C9A0020   bclr    4,26          ; bne cr6,lr  (return if r3 != 0)
VA 0x835F770C: 38600000   li      r3,0
VA 0x835F7710: 4E800020   blr
VA 0x835F7714: 00000000   (zero padding)
VA 0x835F7718: ...        (next registered function begins here)
```

Findings:

1. **0x835F7700 is a real function.** It is 5 instructions
   (`0x835F7700..0x835F7714`), a leaf routine that ends with `blr` at `0x835F7710`.
   `0x835F7714` is zero padding; the exclusive end is therefore **`0x835F7714`**.
2. **No overlap with 0x835F76D8.** The preceding registered function starts at
   `0x835F76D8`, is 10 instructions, and terminates with an **unconditional `bctr`
   at `0x835F76FC`**. There is no fall-through into `0x835F7700`; the two functions
   are disjoint.
3. **The dump is validated.** The rexglue-generated C++ for `sub_835F76D8`
   reproduces these exact instructions, confirming the decompressed image is correct.
4. **No "minimum size threshold" is involved.** Nothing in the SDK codegen rejects
   small functions. `0x835F7700` was simply never discovered: it is absent from
   `.pdata` and is only referenced from `.rdata` pointer tables, so neither the
   entry-point walk nor the exception-table walk found it.

### The override applied

`config/fifadllzf_overrides.toml` (workspace **and** `Installer/recomp-template` copy):

```toml
[functions]
"835F7700" = { end = 0x835F7714 }
```

### Condition 4 — unregistered `.text` pointers in `.rdata`/`.data` (REPORT ONLY)

Scan of 4-aligned big-endian words in `.rdata` and `.data` whose value points inside
`.text` (`0x82650000..0x838D8DB4`) and is **not** in the 86,917-entry registered set
(`SetFunction(...)` in `worldcup2010_register.cpp`).

Script: `C:\Users\<user>\AppData\Local\Temp\opencode\xexdump\analyze2.py`
Output preserved at: `...\xexdump\scan_rdata_data_report.txt`

| Metric | `.rdata` | `.data` |
|---|---|---|
| text-pointer occurrences | 54,454 | 8,633 |
| not-registered occurrences | 752 | 233 |
| distinct not-registered targets | 499 | 195 |

Combined distinct not-registered targets: **688**.

| Breakdown of the 688 distinct targets | Count |
|---|---|
| 4-aligned | 564 |
| decode prologue-like (first instruction plausible) | 537 |
| 4-aligned **and** prologue-like | 537 |
| inside a `.pdata` range (interior, not a start) | 201 |
| **4-aligned + prologue-like + not in `.pdata`** (best "real function" candidates) | **337** |

`0x835F7700` itself: occurs as a `.rdata` pointer at 6 locations —
`0x82376F98`, `0x8256522C`, `0x82568C5C`, `0x8256FB7C`, `0x825757BC`, `0x825778B4`;
`registered=False`, not a `.pdata` start, not inside a `.pdata` range.

**First 30 distinct not-registered targets (sorted by address)**

```
target       hits   align    prolog inPdata    first-insn
0x82650648  15     yes      yes    no         4BFFFFA0 op18 b/bl (op18)
0x82659E49  1      NO       no     no         (unaligned)
0x8265A330  1      yes      yes    no         81430020 op32 lwz rX,imm(rA)
0x8265A370  1      yes      yes    no         2B040000 op10 cmp/cmpl/cmpi/cmpli
0x826760F8  1      yes      yes    no         38A10120 op14 addi/li
0x8267BABC  1      yes      yes    yes        3C60406D op15 addis/lis
0x8267BAD4  1      yes      yes    yes        7D084378 op31 op31 (mr/mtspr/or/...)
0x8267BAE0  1      yes      yes    yes        383F0080 op14 addi/li
0x8268FC70  1      yes      yes    no         3D60839B op15 addis/lis
0x826A6C90  1      yes      yes    no         3D00838F op15 addis/lis
0x826A6CC0  1      yes      yes    no         3D00838F op15 addis/lis
0x826AA8EB  1      NO       no     no         (unaligned)
0x8270F37F  1      NO       no     no         (unaligned)
0x8271FEB2  1      NO       no     no         (unaligned)
0x8275B6F5  1      NO       no     no         (unaligned)
0x82792F9C  1      yes      yes    yes        807E0008 op32 lwz rX,imm(rA)
0x82792FBC  1      yes      yes    yes        7D084378 op31 op31 (mr/mtspr/or/...)
0x82792FCC  1      yes      yes    yes        83DF02A4 op32 lwz rX,imm(rA)
0x82793E46  1      NO       no     no         (unaligned)
0x8279EE17  1      NO       no     no         (unaligned)
0x827B60E0  9      yes      yes    no         81630000 op32 lwz rX,imm(rA)
0x827B64E8  3      yes      yes    no         81630000 op32 lwz rX,imm(rA)
0x827B6510  3      yes      yes    no         81630000 op32 lwz rX,imm(rA)
0x827B6538  3      yes      yes    no         81630000 op32 lwz rX,imm(rA)
0x827B6560  3      yes      yes    no         81630000 op32 lwz rX,imm(rA)
0x827B6990  2      yes      yes    no         81630000 op32 lwz rX,imm(rA)
0x827C5CE3  1      NO       no     no         (unaligned)
0x82823D38  1      yes      yes    yes        81680000 op32 lwz rX,imm(rA)
0x82823D58  1      yes      yes    yes        7D084378 op31 op31 (mr/mtspr/or/...)
0x82823D68  1      yes      yes    yes        7C7E1B78 op31 op31 (mr/mtspr/or/...)
```

Interpretation: most candidates are **interior class-layout / RTTI / jump-table pointers**
(they land inside an existing `.pdata` range, e.g. `0x8267BABC`, `0x82792F9C`), or
**unaligned** values (plain data). The 337 `aligned+prologue+not-in-pdata` entries are
the ones worth a look if later crashes occur — but none of them have caused a crash yet,
so **no further overrides were added**. This is report-only.

### Condition 5 — source of the "FIFA TRACE" `[error]` lines

They come from the local SDK patch, **not** the game:
`D:\FWC10\world-cup-2010-pc-port\patches\rexglue-local-changes.patch` adds
`REXKRNL_ERROR(...)` trace lines into `src/kernel/xboxkrnl/xboxkrnl_modules.cpp`
(`XexLoadImage_entry` and `XexGetProcedureAddress_entry`). Patch excerpt:

```cpp
 u32 XexLoadImage_entry(mapped_string module_name, u32 module_flags, u32 min_version,
                        mapped_u32 hmodule_ptr) {
+
+  REXKRNL_ERROR(
+      "FIFA TRACE XexLoadImage: module='{}' flags=0x{:08X} min_version=0x{:08X}",
+      module_name.value(),
+      module_flags,
+      min_version);
+
   X_STATUS result = X_STATUS_NO_SUCH_FILE;
```

```cpp
 u32 XexGetProcedureAddress_entry(mapped_void hmodule, u32 ordinal, mapped_u32 ou...)
   ...
   if (module) {
+    REXKRNL_ERROR(
+        "FIFA TRACE XexGetProcedureAddress: module='{}' hmodule=0x{:08X} "
+        "ordinal=0x{:08X} caller=0x{:08X}",
+        module->name(),
+        static_cast<uint32_t>(hmodule),
+        ordinal,
+        caller_address);
```

These are emitted at `[error]` log level because `REXKRNL_ERROR` is used; there is no
"minimum function size" logic anywhere in the SDK codegen.

### Stage 6 follow-up A — why GapFill missed 0x835F7700 (GapFill logic, quoted)

Source: `ReXGlue/src/codegen/phase_gapfill.cpp`.

`splitRegionOnTerminators` decides where to cut a code region into candidate
functions. It only cuts on two things:

```cpp
    // Check for terminators
    if (decoded.is_return()) {
      shouldSplit = true;
      reason = "blr";
    } else if (decoded.opcode == Opcode::b && decoded.branch_target.has_value()) {
      uint32_t target = decoded.branch_target.value();
      // Don't split on tail recursion (branch to own segment start)
      if (target != segmentStart && knownCallables.contains(target)) {
        shouldSplit = true;
        reason = "tail call";
      }
    }
```

`is_return()` is defined in `ReXGlue/src/codegen/ppc/instruction.cpp`:

```cpp
bool Instruction::is_return() const {
  // blr is bclr with BO=20 (unconditional)
  if (opcode == Opcode::bclr) {
    return (raw == 0x4E800020);  // Specific encoding for blr
  }
  return false;
}
```

So a terminator is recognised **only** for the exact `blr` word `0x4E800020`, or
for a direct `b` (`Opcode::b`, the I-form) whose target is an already-known
callable. A `bctr` is `0x4E800420` → opcode `bcctr` (`opcode.h:55`), which is
neither `Opcode::bclr` nor `Opcode::b`, so **it is not a split point at all**.

Consequently, walking the region that contains `0x835F76D8`:

* `0x835F76FC` `bctr` (`4E800420`) — **no split** (not `is_return`, not `Opcode::b`).
* `0x835F7710` `blr` (`4E800020`) — split here; the segment ends at `0x835F7714`.

So the segment that physically contains `0x835F7700` **starts earlier than
`0x835F7700`** (at/behind `0x835F76D8`). GapFill only ever registers a segment's
**start** address:

```cpp
    for (const auto& segment : segments) {
      // Skip if this segment's start is already a registered function entry
      if (graph.isEntryPoint(segment.start))
        continue;

      // Skip if this segment's start is inside another function
      if (auto* containingFunc = graph.getFunctionContaining(segment.start)) {
        continue;
      }
      ...
      graph.addFunction(segment.start, segmentSize, FunctionAuthority::GAP_FILL, false);
```

`0x835F7700` is never a `segment.start`, it is interior to `[<earlier>, 0x835F7714)`.
Either that segment starts at the already-registered `0x835F76D8` (→ dropped by
`isEntryPoint`), or it starts earlier (→ dropped by `getFunctionContaining`, or later
by `cleanupAbsorbedGapFills`). In every case `0x835F7700` is never registered.

This is the *same* reason the containing `bctr`-terminated function at
`0x835F76D8` was not discovered by GapFill either — it was found by `.pdata`/other
analysis. **There is no "minimum function size" check** in the SDK codegen; the
miss is purely the terminator set being `{blr, known direct b}`.

**How many gaps of the same kind exist.** Scanning `.text` between consecutive
registered functions, walking each registered function's control flow to bound
its body, and validating each maximal uncovered run as a complete function
(every path ends at `blr`/`bctr`, or at an out-of-range tail `b`):

| quantity | count |
|---|---|
| registered functions (pre-Stage-6) | 86,917 |
| unregistered gap functions between registered functions | **1,193** |
| — ending strictly in `blr` / `bctr` | **779** |
| — ending in a tail branch (`b`) | 414 |
| of the 1,193, referenced by a `.rdata`/`.data` pointer | small subset (see B) |

So yes: `0x835F7700` is one of ~1,193 such gaps, but only a small number of them
are reachable through pointer tables (which is what actually causes the runtime
indirect-call crash).

### Stage 6 follow-up B — re-ranking the unregistered `.rdata`/`.data` targets

Method: the pre-Stage-6 registered set (86,917 addresses) and a CFG walk from every
registered function give a *covered* set. An unregistered target is **valid** when
it is 4-aligned, not registered, not inside any `.pdata` range, not inside a covered
body, and a CFG walk from it ends cleanly (all paths `blr`/`bctr`/out-of-range tail
`b`), with no data words. "Vtable-like run" = ≥3 consecutive 4-byte words in
`.rdata`/`.data` that all point into `.text`. No prologue test is used.

| quantity | count |
|---|---|
| distinct unregistered `.text` pointer targets | 688 |
| — inside a vtable-like run (≥3) | 447 |
| — isolated | 241 |
| vtable-like runs (≥3 entries) | 1,787 |
| runs containing ≥1 unregistered target | 249 |
| — where **every** unregistered target is CFG-valid | **175** |
| CFG-valid aligned non-`.pdata` candidates (all targets) | 272 |
| — of those, members of a vtable-like run | 266 |

Largest runs (all unregistered targets CFG-valid): `.rdata@0x82416A38` (len 739,
44 unreg, all valid), `.rdata@0x8234B080` (len 324, 16 unreg, all valid),
`.rdata@0x824F2240`/`0x824F2180`/`0x824F1DF8`/`0x824F1E90` (the `0x831A48xx`/
`0x831A8Exx` this-pointer thunk table), `.rdata@0x823C8F5C`, `.rdata@0x82416948`.
One run is a counter-example: `.rdata@0x825D5914` (len 11, 8 unreg, **0** valid) —
its targets do not decode as functions, i.e. it is not a real function-pointer table.

### Stage 6 follow-up C — proposed override batch (≤20), NOT applied

Ranked from the vtable-run + CFG-valid group. Every entry below is preceded
immediately by a terminator (`bctr`/`blr`/tail `b`) in the previous function, which
is the strongest "this is a real function start" signal, and none sits inside a
`.pdata` range or a registered body.

`0x835F7700` (already applied, see above) is omitted from this list.

| # | address | end (exclusive) | insns | ends | refs | notes |
|---|---|---|---|---|---|---|
| 1 | `0x82650648` | `0x8265064C` | 1 | tail `b` | 15 | pure jump thunk `b 0x826505E8` |
| 2 | `0x827B60E0` | `0x827B60F0` | 4 | `bctr` | 9 | virtual-dispatch thunk (`lwz r11,0(r3); lwz r11,380(r11); mtctr; bctr`) |
| 3 | `0x82AD8C60` | `0x82AD8C88` | 10 | `bctr` | 6 |  |
| 4 | `0x82AD8C88` | `0x82AD8CB0` | 10 | `bctr` | 6 |  |
| 5 | `0x82ADCBF0` | `0x82ADCBFC` | 3 | `blr` | 33 | `lis r3,0; ori r3,r3,0xFFFF; blr` (returns 0xFFFF) |
| 6 | `0x82C44098` | `0x82C440A8` | 4 | `bctr` | 10 |  |
| 7 | `0x83187BC0` | `0x83187BEC` | 11 | tail `b` | 13 |  |
| 8 | `0x831A4820` | `0x831A4828` | 2 | tail `b` | 5 | `addi r3,r3,-4; b …` this-adj thunk |
| 9 | `0x831A4828` | `0x831A4830` | 2 | tail `b` | 5 | same thunk table |
| 10 | `0x831A8E50` | `0x831A8E58` | 2 | tail `b` | 5 | same thunk table |
| 11 | `0x831A8E58` | `0x831A8E60` | 2 | tail `b` | 5 | same thunk table |
| 12 | `0x831A8E60` | `0x831A8E68` | 2 | tail `b` | 5 | same thunk table |
| 13 | `0x831A8E68` | `0x831A8E70` | 2 | tail `b` | 5 | same thunk table |
| 14 | `0x831A8E80` | `0x831A8E88` | 2 | tail `b` | 5 | same thunk table |
| 15 | `0x831A90F8` | `0x831A9100` | 2 | tail `b` | 5 | same thunk table |
| 16 | `0x831A9108` | `0x831A9110` | 2 | tail `b` | 5 | same thunk table |
| 17 | `0x831A9110` | `0x831A9118` | 2 | tail `b` | 5 | same thunk table |
| 18 | `0x83265768` | `0x8326576C` | 1 | tail `b` | 5 | jump thunk |
| 19 | `0x82883A48` | `0x82883A54` | 3 | `blr` | 4 |  |
| 20 | `0x82A9F6C8` | `0x82A9F70C` | 17 | `blr` | 4 |  |

Raw first words (evidence): `0x827B60E0` = `81630000 816B017C 7D6903A6 4E800420`;
`0x82ADCBF0` = `3C600000 6063FFFF 4E800020`; `0x831A4820` = `3863FFFC 4BFFFF6C`;
`0x82650648` = `4BFFFFA0`.

Proposed TOML (do **not** apply without approval):

```toml
[functions]
"82650648" = { end = 0x8265064C }
"827B60E0" = { end = 0x827B60F0 }
"82AD8C60" = { end = 0x82AD8C88 }
"82AD8C88" = { end = 0x82AD8CB0 }
"82ADCBF0" = { end = 0x82ADCBFC }
"82C44098" = { end = 0x82C440A8 }
"83187BC0" = { end = 0x83187BEC }
"831A4820" = { end = 0x831A4828 }
"831A4828" = { end = 0x831A4830 }
"831A8E50" = { end = 0x831A8E58 }
"831A8E58" = { end = 0x831A8E60 }
"831A8E60" = { end = 0x831A8E68 }
"831A8E68" = { end = 0x831A8E70 }
"831A8E80" = { end = 0x831A8E88 }
"831A90F8" = { end = 0x831A9100 }
"831A9108" = { end = 0x831A9110 }
"831A9110" = { end = 0x831A9118 }
"83265768" = { end = 0x8326576C }
"82883A48" = { end = 0x82883A54 }
"82A9F6C8" = { end = 0x82A9F70C }
```

Caveats: entries 8–17 are 2-instruction this-pointer trampolines from a single
vtable (`.rdata@0x824F1DF8`/`0x824F1E90`); they are structurally valid but low value
individually. Many of the 1,193 gaps are *not* pointer-referenced and cannot cause an
indirect-call crash, so a blanket override of all of them would be mostly harmless
but pointless noise; this batch is the pointer-reachable, structurally-confirmed set.

### Stage 6 follow-up D — batch proposal after crash #2 (2026-10-17)

Crash #2 hit `0x82650648`, which is entry #1 of the batch above, confirming the
method. Per instruction, the follow-up is a **batch** over the full CFG-valid
vtable-run candidate set, with a jump-table case-body exclusion.

**Exclusion method.** For each candidate `T`, look at the word immediately before it
(`T-4`). If that word is a `bctr` (`0x4E800420`) fed by `mtctr` from an indexed load
(`lwzx`, opcode 31/XO 23) whose base register resolves to a constant jump table, and
the table points into `[T, end)`, then `T` is a switch case body and is dropped.
(Distinct from virtual dispatch: those load the table from the object pointer
`lwz r11,0(r3)`, which is *not* a resolvable constant, so they are never dropped.)

| quantity | count |
|---|---|
| CFG-valid vtable-run candidates (**before**) | **266** |
| excluded as jump-table case bodies | **0** |
| remaining (**after**) | **266** |
| candidates immediately preceded by a `bctr` | 184 |
| of those, preceding `bctr` is a resolved switch | 0 |
| resolved switch dispatch sites in `.text` (mtctr;bctr + constant table) | 129 |
| distinct switch-table entries | 1100 |
| candidates whose range contains any switch-table entry | 0 |

So the exclusion is empty for this binary: all 184 preceding `bctr`s are
virtual-dispatch thunks (dynamic vtable), and none of the 129 real switch tables
points into a candidate range. Batch = **266** overrides (awaiting approval).

10 sample entries (target, exclusive end, instruction count, terminator, ref count):

| target | end | insns | term | refs |
|---|---|---|---|---|
| `0x82650648` | `0x8265064C` | 1 | tail `b` | 15 |
| `0x827B60E0` | `0x827B60F0` | 4 | `bctr` | 9 |
| `0x82AD8C60` | `0x82AD8C88` | 10 | `bctr` | 6 |
| `0x82AD8C88` | `0x82AD8CB0` | 10 | `bctr` | 6 |
| `0x82ADCBF0` | `0x82ADCBFC` | 3 | `blr` | 33 |
| `0x82C44098` | `0x82C440A8` | 4 | `bctr` | 10 |
| `0x83187BC0` | `0x83187BEC` | 11 | tail `b` | 13 |
| `0x831A4820` | `0x831A4828` | 2 | tail `b` | 5 |
| `0x831A8E50` | `0x831A8E58` | 2 | tail `b` | 5 |
| `0x83265768` | `0x8326576C` | 1 | tail `b` | 5 |

Full 266-entry list: `C:\Users\<user>\AppData\Local\Temp\opencode\xexdump\rank_report5.txt`
("full KEEP list as TOML" section).

### Stage 6 follow-up E — approved batch applied (2026-10-17)

Decision (user): apply the **184 bctr-preceded subset only** (not all 266); leave the
other 82 out and add them one at a time only if a crash points at one. Conditions,
all satisfied:

1. **Jump-table exclusion.** Of the 184, **0** were excluded. For each candidate `T`,
   `word_at(T-4)` is a `bctr`; none of those `bctr`s is a resolved switch dispatcher
   (a `bctr` fed by `mtctr` from a constant jump table), so no table points into any
   range. The 184 preceding `bctr`s are all virtual-dispatch thunk tails
   (`lwz r11,0(r3); lwz r11,off(r11); mtctr; bctr`), whose table is the dynamic
   object vtable and is therefore not statically resolvable. Detector validated on
   the binary's real switches: 129 resolved switch sites / 1100 table entries, none
   intersecting a candidate.
2. **Function/overlap check.** 184/184 decode as complete functions (every control
   path ends at `blr`/`bctr` or an out-of-range tail `b`); **0** have a registered
   function inside `(start, end)`; **0** pairwise overlaps.
3. **Files written.** 183 new entries + the existing `0x835F7700` = **184 entries**,
   written identically (verified same SHA-256) to both:
   * `Installer\recomp-template\config\fifadllzf_overrides.toml`
   * `C:\FWC10B\fwc10stage4\WorldCup2010Rex\config\fifadllzf_overrides.toml`
4. **Generated-output verification** (after codegen, before boot): for every one of
   the 184 addresses, `worldcup2010_register.cpp` contains
   `registrar->SetFunction(0xADDR, sub_ADDR);`, `worldcup2010_init.cpp` contains
   `{ 0xADDR, sub_ADDR },`, `worldcup2010_funcs.h` contains
   `DECLARE_REX_FUNC(sub_ADDR);`, and a `worldcup2010_recomp.*.cpp` contains
   `DEFINE_REX_FUNC(sub_ADDR)`. Script: `...\xexdump\verify_generated.py`.
   Result: **184 / 184 present** (`verify_generated.py`, exit 0).

Full 184-entry list: `...\xexdump\batch_184.toml`. The untouched 82 are in
`...\xexdump\rank_report5.txt` ("full KEEP list as TOML" minus the 184).

### Condition 3 / Condition 6 — codegen, rebuild, boot (results)

**Codegen (2026-10-17) — DONE, exit code 0.** Re-run against
`C:\FWC10B\fwc10stage4\WorldCup2010Rex`:

```
rexglue.exe --log-file codegen.stage6.log --log-level debug codegen worldcup2010_manifest.toml
...
  done   fifadllzf.xex (435.1s)
Codegen summary: 5 written, 654 unchanged, 0 deleted, 1 module(s) up to date
Done in 435.6s.        EXITCODE=0
```

The override was picked up (`Analyze: 1 CONFIG functions`), and `0x835F7700` is now
emitted:

```
worldcup2010_register.cpp : registrar->SetFunction(0x835F7700, sub_835F7700);
worldcup2010_init.cpp     : { 0x835F7700, sub_835F7700 },
worldcup2010_recomp.136.cpp: DEFINE_REX_FUNC(sub_835F7700) {
worldcup2010_funcs.h      : DECLARE_REX_FUNC(sub_835F7700);
```

Registered function count went **86,917 → 86,918**.

**Rebuild (2026-10-17) — DONE, exit code 0.** `BuildWorldCup2010.ps1 -SourceBuild`
transcript: start `11:28:33`, end `11:35:45` → **432 s wall**. Note the CMake build
re-runs codegen itself (`[8/38] Generating recompiled code for worldcup2010`,
`Done in 385.5s`), independent of the script's fingerprint check; compile/install was
the remaining ~46 s (`[9/15]…[14/15]` + `[6/6] Installing`). New binaries:
`worldcup2010.exe` (8,022,528 B) and `worldcup2010_fifadllzf.dll` (123,008,000 B),
both written `11:35:44`.

**Boot #2 (2026-10-17 11:35:58) — exited after 5 s, code `-1073740791` (0xC0000409).**
Runtime registered the module with the new function:

```
[info] [core] Registering module: fifadllzf.xex (code_base=82650000)
[info] [core] Module 'fifadllzf.xex' registered 86918 functions
```

The Stage-6 fix held — **`0x835F7700` no longer faults**. Execution advanced to the
*next* missing function:

```
[error] [cpu] INVALID INDIRECT CALL: target=82650648 LR=826914C0 CTR=82650648
       r1=7019F7D0 r2=00000000 r3=BEE5BC28 r11=82650648 r12=82691DF4
[critical] [core] [FATAL] Call to invalid or unregistered function at guest address 0x82650648
```

`0x82650648` is `4BFFFFA0` = `b 0x826505E8` — a 1-instruction jump thunk, preceded by
`0x82650644` `bctr` (tail of the virtual-dispatch thunk at `0x82650638`). It is
candidate #1 of the Stage-6 follow-up D batch. Full log:
`C:\FWC10B\boot_stage6_runtime.log` (156 lines); previous crash log
`C:\FWC10B\firstboot_runtime.log`.

**Cycle timings (for planning).**

| stage | this cycle |
|---|---|
| standalone codegen (`rexglue codegen`) | **435.6 s** (~7.3 min) |
| rebuild (`BuildWorldCup2010.ps1`) wall | **432 s** (~7.2 min) — of which codegen 385.5 s + compile/install ~46 s |
| boot to crash | 5 s |

### Stage 6b applied → boot #3 (2026-10-17 12:00)

**Rebuild (Stage 6b):** exit 0. This cycle codegen actually rewrote output
(`195 written, 511 unchanged`) because the config changed, so ninja recompiled the
whole module (186 objects) instead of a handful. Script codegen 390.4 s; total wall
11:46:55 → 11:59:53 ≈ **778 s (~13 min)**.

**Post-codegen verification:** 184/184 batch addresses present in all four generated
files (`register.cpp`, `init.cpp`, `funcs.h`, and a `recomp.*.cpp`).

**Boot #3 — exited after 10 s, code `-1073740791` (0xC0000409).** Got **further**
(477 log lines vs 156; audio/XMA now running). Registration:
`Module 'fifadllzf.xex' registered 87101 functions` (= 86,918 + 183). The batch
worked — no crash at any of the 184; execution advanced to the next missing target:

```
[error]    [cpu]  INVALID INDIRECT CALL: target=82EEFB68 LR=82EEF500 CTR=82EEFB68
                  r1=7019E5D0 r2=00000000 r3=BE701EB8 r11=82EEFB68 r12=82EEF4D4
[critical] [core] [FATAL] Call to invalid or unregistered function at guest address 0x82EEFB68
```

The caller is a virtual call: `0x82EEF4E4 lwz r11,0(r31)` /
`0x82EEF4F4 lwz r11,0x10(r11)` / `mtctr r11` / `bctrl` — vtable slot `0x10`.

`0x82EEFB68` is in the 266 keep list but **not** the 184 batch: it is one of the
**82 omitted** candidates. Structural note: **all 82 omitted are preceded by a tail
`b`** (opcode 18); the 184 batch are all `bctr`-preceded. It is a real 55-instruction
function (`lbz r11,0x28(r3); addi r5,r5,4; cmplwi r11,0; beqlr; …; blr`), terminator
`blr` at `0x82EEFC40`, so `end = 0x82EEFC44` (exclusive).

### Stage 6c (2026-10-17) — one-at-a-time addition

Per instruction ("add them one at a time only if a crash points at them"), added the
single entry to both override copies:

```toml
"82EEFB68" = { end = 0x82EEFC44 }
```

Rebuild + boot results:

* **Boot #4 (2026-10-17 12:09):** exited after 10 s, `-1073740791`. Registered
  `87102 functions` (= 87,101 + 1). Got further again (854 log lines). New target:
  `INVALID INDIRECT CALL: target=82883A48 LR=82851034` — **also one of the 82
  omitted**. Caller `0x82851024 lwz r11,0(r3)` / `lwz r11,0x18(r11)` / `mtctr` /
  `bctrl` — vtable slot `0x18`. `0x82883A48` is 3 instructions
  (`lwz r11,8(r3); lbz r3,0x60(r11); blr`), end `0x82883A54`.
* Entry added one-at-a-time, then a full rebuild was started, then **stopped**
  (the approved batch below supersedes it) — `[3/6] Cleaning` re-wipes generated
  code each run, so nothing was left inconsistent.

Once two consecutive crashes both landed in the 82 omitted, user approved batching
the rest.

### Stage 6d (2026-10-17) — remaining 80 (tail-b-preceded) batch

Backups first (condition 3):
* `Installer\recomp-template\config\fifadllzf_overrides.backup_stage6b_184.toml` (184)
* `Installer\recomp-template\config\fifadllzf_overrides.backup_stage6c_186.toml` (186)

Condition 1 (branch-into-range): the **preceding function's start** is computed as
the address after the **2nd** unconditional terminator (`blr`/`bctr`/unconditional
`b` with LK=0, AA/LK decoded correctly from bit 1/bit 0) going backward from the
candidate, skipping zero padding. (First attempt wrongly used a shared *epilogue* —
e.g. `0x83187B54`, reached by a legitimate tail `b` — as the start, giving 14 false
positives; fixed.) Result:

| quantity | count |
|---|---|
| remaining omitted (before) | **80** |
| excluded (branch into range / prev-b self-loop / reg-inside / not-clean) | **0** |
| **batch (after)** | **80** |

Verified: 80/80 are complete CFG functions with no registered function inside their
range; **0** have any branch in the preceding function targeting into `[v, end)`;
the preceding tail `b` is a tail call to a shared epilogue, not a self-loop.
Evidence samples (`pcheck.py`): `0x83187BC0` prev_start `0x83187B64`, `b@0x83187BBC ->
0x83187B54` (epilogue, outside) — same shape for `83265768`, `82A62CA8`, `8324A980`.

Condition 4: both copies written → **266 entries each**, **identical SHA-256**
(`FFB03BFC…7787D`). Rebuild: exit 0, transcript 12:15:22 → 12:24:38 = **556 s
(~9.3 min)**, codegen `121 written` 399.0 s, 76 compile targets.
`verify_generated.py`: **266 / 266** present in all four generated files.

**Boot #5 (2026-10-17 12:25): registered `87183 functions`** (= 86,918 + 183 + 1 + 1
+ 80, exact). **No `INVALID INDIRECT CALL` / unregistered fatal** — the batch worked.
The process got **further** than ever (thread id 35 vs boot #4's 34). It then exited
after 5 s with a *different* class of fault:

```
[2026-10-17 12:25:28.855] [debug] [krnl] [t216] SetThreadName(35, rw45_pkg_factory_seg)
[2026-10-17 12:25:28.856] [error] [sys] [t216] Unhandled guest access violation:
    read of guest 0x0006C6B8 (host 0x000000010006C6B8) on thread 0xF8000358
```

Exit code `-1073741819` = `0xC0000005` (ACCESS_VIOLATION), **not** the previous
`0xC0000409`. This fault is **new** (0 occurrences in the four earlier boot logs).
It happens on a freshly-started game thread (`rw45_pkg_factory_seg`, thread 35),
reading guest `0x6C6B8` (near-null base + offset).

### Stage 6e — STOPPED (per instruction)

Per the rule "if a new crash appears at an address that worked before, tell me
immediately and don't continue the loop": **loop stopped, no overrides touched.**
Assessment: monotonic progress (thread id per boot 19 → 22 → 27 → 34 → 35) means the
batch did its job; the AV is a *different failure class* (bad data pointer, not a
missing function) that was previously unreachable. It could be (a) the next latent
bug (a stubbed call returning null, e.g. `__imp__XUsbcamGetState STUB - returning
0x0`), or (b) a regression from one of the 80 overrides. Backups exist to bisect
(`backup_stage6b_184.toml`, `backup_stage6c_186.toml`). Awaiting direction — do not
modify overrides.

### Root-cause analysis of the boot #5 access violation (2026-10-17)

Method (no rebuild): the process crash produced minidumps in
`%LOCALAPPDATA%\CrashDumps` (`worldcup2010.exe.7488.dmp` = the 12:29 re-run). Parsed
it directly (`dmp.py`) — the fault is on **host `worldcup2010_fifadllzf.dll + RVA
0x70ACE86`**, i.e. inside *recompiled guest code*, not the runtime.

Then mapped host RVA → guest address using two independent artefacts in the DLL
(`map_fn.py`): the static `PPCFuncMappings[]` table
(`struct PPCFuncMapping { size_t guest; PPCFunc* host; }`, 16-byte entries; 87,183
found) and the `.pdata` `RUNTIME_FUNCTION` list (67,204 entries). Both agree:

| host RVA | guest fn |
|---|---|
| `0x70ACC50`..`0x70AE821` | **`0x82CBD7E0`** ← faulting function |

Disassembly of the faulting site and its own prologue (`investigate.py`, `dump3.py`):

```
guest 0x82CBD7E0: mflr r12 ; bl 0x828328DC ; stwu r1,-144(r1) ; or r31,r3,r3
                  bl 0x82C501D0        ; r3 = *(0x83A4648C)   (engine singleton)
                  bl 0x832BF128        ; r3 = singleton->[+0x64]  (getter: lwz r3,0x64(r3); blr)
  0x82CBD7F8:     lis  r11,0x6
  0x82CBD804:     ori  r11,r11,0xC6B8  ; r11 = 0x6C6B8
  0x82CBD80C:     lwzx r28,r3,r11      ; <== FAULT: *(singleton->[+0x64] + 0x6C6B8)
```

i.e. the engine singleton exists, but its field at `+0x64` is **null**, and the code
then dereferences `null + 0x6C6B8`. Exactly one **static** caller (`investigate.py`):
an x86 `call` from RVA `0x049A6410` → guest **`0x82CA1B50`** (call site `0x82CA2A10`).

Membership check (`check2.py`, `chain.py`): **none** of the functions on the faulting
path (`0x82CBD7E0`, `0x82CA1B50`, `0x82C501D0`, `0x832BF128`, `0x828328DC`,
`0x82CBC610`) is one of our 266 overrides. The only override in this neighbourhood is
`0x82883A48` — the *previous* crash target (vtable slot `0x18`), a faithful getter
(`lwz r11,8(r3); lbz r3,0x60(r11); blr`) whose registration simply let execution
reach this point.

The crashing thread `rw45_pkg_factory_seg` logged only two lines ever
(`SetThreadName(35, …)` then the AV); the whole run had only 4 stub hits, all on the
main thread (`XeKeysConsolePrivateKeySign`, `XLiveBaseUnk58046`,
`__imp__XUsbcamGetState → 0x0`, `IoDismountVolumeByFileHandle`), none on this thread.

**Conclusion:** the AV is the game dereferencing an uninitialised subsystem pointer
(`singleton->[+0x64]`) from its own code — not a mis-registered override, and not an
unregistered-call stop. (A search for the writer of `singleton->+0x64` via the
`0x648C`-displacement sites, `writer.py`, found no simple writer — the field is
populated more indirectly.) The 80-batch is therefore not implicated; this AV would
appear with the earlier 186-entry config too.

Analysis scripts: `dmp.py`, `dmp_stack.py`, `map_fn.py`, `who_fn.py`, `chain.py`,
`investigate.py`, `check2.py`, `dump3.py`, `writer.py` (all in `…\xexdump`).

List: `...\xexdump\batch_80.toml`.

---

## Offline hunt: boot #5 AV at `0x82CBD80C` �?" full root-cause (no rebuild, no override changes)

Directive honoured: this whole section is **offline analysis of the existing artefacts only**
(decompressed XEX image + minidump + built DLL + generated sources + boot logs). No rebuild,
no override changes, no re-run of the game.

### Object identity

`*(0x83A4648C)` is a singleton created by guest **`0x82C6AFC8`** (`CREATE`):
`operator new(196)` (guest `0x82A64018` �?' allocator vtable dispatch, size in r4=196) then
ctor **`0x82C50EF0`**, then `stw r3,0x648C(r11)` (publishes the global). `CREATE` has exactly
one caller: **`0x8265EF7C`** inside **`0x8265EF40`**, an init/registration function that is
invoked at startup through a static-initialiser function-pointer table
(.rdata pointers at `0x82307270`, `0x823072B8`, `0x82307300`), which is why it has no `bl` callers.

Type: the ctor is a **pure zero-fill** �?" `addi r11,r0,0` then `stw r11,0(r3) … stw r11,0xC0(r3)`
(skipping `+0xB8`). Therefore:
* **offset 0 = 0 �?" the object is constructed with no vtable.**
* **offset +0x64 = 0** at construction.

Class: the thread that faults is named `rw45_pkg_factory_seg`, and that string sits in a
RenderWare 4.5 name pool (`0x8259BB08`) whose neighbours are
`RwAssetPackageFactoryCommon:filename`, `RwAsyncLoadPackageSegmented`,
`RwAsyncLoadPackage::Thread`, `RwPackageSegmented::DefaultAsset`, `sg1`, `sg2`.
So `*(0x83A4648C)` is the **`RwAsyncLoadPackageSegmented`** (RW4.5 async package factory)
instance and `[+0x64]` is its pointer to the package **segment** object (`RwPackageSegmented`),
which owns the big array at `+0x6C6B8` (element stride 8144 = `sub_82C71858`). RTTI is stripped
(no class-name strings), so this identification is from the name pool, not from RTTI.

### Fault chain (generated code verified)

```
sub_82CBD7E0 :  sub_82C501D0(ctx)            -> ctx.r3 = *(0x83A4648C)   (global getter)
                sub_832BF128(ctx)            -> ctx.r3 = *(r3 + 0x64)     (field getter)
                lis r11,6 ; ori r11,r11,50872 (=0x6C6B8)
                lbz r10,19(r31) ; cmplwi r10,0
                lwzx r28,r3,r11              <<< FAULT (guest 0x82CBD80C)
```
guest `0x82CBD80C`, host `worldcup2010_fifadllzf.dll + RVA 0x70ACE86`, reads host `0x10006C6B8`
(guest `0x6C6B8`), i.e. `r3` was NULL and `r3 + 0x6C6B8` was dereferenced.
`sub_82CBD7E0` is a dispatcher that afterwards switches on `this[+4]` (8 cases via `mtctr`).

### Real call stack (from the minidump itself)

Walked the faulting thread's own stack (`stackwalk2.py`) and mapped every in-DLL return address
back to a guest function through `PPCFuncMappings[]`:

```
sub_82CBD7E0  (fault)
  <- sub_82CA1B50      (bl 0x82CBD7E0)
  <- sub_82A64EC8
  <- sub_8265E158
  <- sub_8265E810
  <- sub_82A70B30      (callback/task dispatcher, called with an index from init code)
  <- sub_8265F5F0
  <- sub_8267CAD8      (RW module/thread trampoline, region 0x8267Bxxx)
  <- sub_82836038 / sub_828360B8 / sub_8282FD10   (host thread start -> guest thread entry)
```
Exception record: `tid=20760`, code `0xC0000005`, exception address `0x7FFCA186CE86`
( = dll base `0x7FFC9A7C0000` + `0x70ACE86` ).

### Thread identity / timeline

Boot `12:25:25.849`. Thread 35 (handle `F8000358`, host tid 216) emitted exactly one line:
`[12:25:28.855] SetThreadName(35, rw45_pkg_factory_seg)` and faulted 1 ms later
`[12:25:28.856]`. The name is not referenced as an absolute pointer anywhere; it is referenced
as `addi r11,r4,-24` (i.e. `0x8259BB08` = `0x8259BB20 - 24`) in the **thread-creation** code
`0x83701980…0x83701A40`, which stores the descriptor (`+4=16384`, `+8=1`, `+12=4`,
`+20="rw45_pkg_factory_seg"`) and starts the thread with entry `addi r4,r10,6352` = **`0x837018D0`**
(`RwAsyncLoadPackage::Thread`). All other threads (9–34) were named by the main thread `t25060`;
thread 35 is the first thread that names *itself*, i.e. it sets its name once running and then
immediately touches the uninitialised field. The thread is created ~30 ms after the last
file-open failures in the log (`d:\data\ice\icenislist.txt` @28.826, `d:\data\sceneassets\genheadtex.big`,
`d:\data\loc\locale.bh`), i.e. it is started by startup while the missing content has already failed.

### Exhaustive search for the writer of `singleton+0x64` (five independent passes)

1. **Direct-store dataflow** over all **87,183** registered functions, tracking the singleton both
   as the getter result and as the incoming `r3` (with `mr`/`or` copy propagation, `lis/addi/ori`,
   `add` chains, stack-slot round-trips, `GLOBAL` load folding) �?" **0 stores to `singleton+0x64`.**
   Sanity check: the same pass *does* find the field writes that genuinely happen (e.g. the
   `+0xAC` store from `sub_82C50840`, `stw r4,172(r3)`), so the pass is not blind.
2. **All stores with base = incoming `r3` at offset 0x64** (raw binary scan): 100 functions;
   only 5 lie in the class's own code region `0x82C5…0x82C9` �?" the ctor `0x82C50EF0` (writes 0)
   and `0x82C624A8` / `0x82C7F2A0` / `0x82C88270` / `0x82C88B08`, which are **constructors of other
   classes** (they fill `-1` runs and are given other `this` pointers).
3. **Interprocedural reachability** (BFS over call sites that pass the singleton as `r3`):
   exactly **113** functions are ever called with the singleton; **none** of them writes `+0x64`.
4. **The full init function `0x8265EF40`** (dumped to its real end `0x8265EFF8`): singleton-related
   calls are only `CREATE`, the global getter, `0x82C50840` (sets `+0xAC`), `0x82CA1138`,
   `0x82C506B0`. Its later `bl 0x826546E0` (a function that does store `r31+0x64`) is passed
   `r4 = r31` while **`r3` is not the singleton** �?" that store targets a different object.
5. **Alias test**: no global/static anywhere in the image ever *receives* the singleton pointer,
   so there is no second name for it that a store could be funnelled through.

Also excluded: the trivial `+0x64` setter `sub_82BDB2F8` (`stw r4,100(r3); blr`) has **no `bl`
callers at all**; it exists only as a function-pointer/vtable slot (`0x8241690C`, inside the
table at `0x82416800` which constructors install as some other object's vtable). So it cannot be
reached with this object (whose offset 0 is 0, i.e. which has no vtable to dispatch through).

### Classification of the missing initialiser (the user's a/b/c/d)

* **(c) empty "no blocks" stub �?" ruled out.** Every function in the fault chain and in the
  class region is present in `worldcup2010_register.cpp` / `worldcup2010_init.cpp` and has a
  faithful generated body (e.g. `sub_82BDB2F8` = `REX_STORE_U32(ctx.r3.u32 + 100, ctx.r4.u32);`).
* **(d) split by an override �?" ruled out.** None of `0x82CBD7E0`, `0x82CA1B50`, `0x82C501D0`,
  `0x832BF128`, `0x82C50EF0`, `0x82C6AFC8`, `0x8265EF40`, `0x826546E0` is in the 266-entry override list.
* **(b) called but skipped by an early return �?" no such branch found.** The init path that runs
  (`CREATE` + the 3 method calls) has no conditional that guards a `+0x64` write; there is simply
  no `+0x64` write to guard.
* **(a) never called - the option *best supported* by the evidence, but NOT proven (Round 12)**, with the refinement
  that no *direct* store of a value into `singleton+0x64` exists anywhere in the image: the only
  generic setter for that offset is a vtable-dispatched accessor and the object is never given the
  vtable that would let it be dispatched.

**Therefore the AV is the game reading a field it never initialises in this build** �?"
`GetPackageFactory()->segment == NULL` �?" exactly as the register/AV log shows.

### Scripts added (`…\xexdump`)

`accessors.py`, `ctor_and_setter.py`, `table.py`, `tablerefs.py`, `tableref_code.py`, `rtti.py`,
`initfull.py`, `initfull2.py`, `genchain.py`, `stackwalk.py`, `stackwalk2.py`, `threadname2.py`,
`poolrefs.py`, `rwvtable.py`, `rwvtable2.py`, `flow64f.py`, `flow64g.py`, `w64list.py`,
`region64.py`, `alias1.py`.

---

## Offline hunt part 2: ISO listing, stub hits, static-search gaps

No rebuild, no override changes, no new codegen (0 s codegen / 0 rebuilds, ~40 min analysis).
Follows the user's 5 follow-up questions on the boot #5 AV.

### 1. ISO listing vs `dist\GameData` -- **the "missing data" claim is RETRACTED**

`extract-xiso -l "D:\FWC10\2010 World Cup.iso"` lists **43 files, 5,995,265,385 bytes**.
`dist\GameData` contains **all 43 files with byte-identical sizes** (incl. `$SystemUpdate\`,
`nxeart`, both `.xex`, `data\ant.cbac`, `data\launcher\*`, `data\movies\*`).

`data\ice`, `data\sceneassets` and `data\loc\locale.bh` **do not exist on the disc at all**.
The ISO has only: `data\ant.cbac`, `data\launcher\*` (6 files), `data\loc\locale.big`,
`data\movies\*` (9 files), `data\ui\artAssets\heads\2dheads.{bh,big}`.

So the earlier "re-stage the game data from a complete disc" recommendation was based on an
unverified inference (GameData lacks the path -> disc must have it). **Withdrawn.** Those
`NtCreateFile -> 0xc000000f` (STATUS_OBJECT_NAME_NOT_FOUND) lines are the title probing
optional/dev-only paths, exactly like the same run's probes for `d:\audiodata\aemsdata\crowdstreams.big`,
`d:\osdkdebugmanager.ini` and `E:\dvdini\osdkdebugmanager.ini`. Game content lives inside
`data0..data8.big` (mounted through their `.bh`), not as loose `data\` files.

### 2. The 4 stub hits (all `[krnl]`, all on `t25060`, all **before** the AV)

These are **unimplemented host/platform exports**, not recompiler "no blocks" stubs (the run
emitted no recompiler "no blocks" message at all). Three are static imports, i.e. they have a
guest import thunk in the image (16-byte thunk = two ordinal-marker words + `mtctr r11` + `bctr`):

| log | time | import | guest thunk | thunk words | `bl` call site | caller fn | call word |
|---|---|---|---|---|---|---|---|
| L144 | 26.570 | `XeKeysConsolePrivateKeySign` | `0x838D7A3C` | `01010256 02010256 7D6903A6 4E800420` | `0x8281FEA4` | `0x8281FDF8` | `490B7B99` |
| L146/149 | 26.570 | `IoDismountVolumeByFileHandle` | `0x838D7D6C` | `0101003C 0201003C 7D6903A6 4E800420` | `0x8282D85C` | `0x8282D498` | `490AA511` |
| L528 | 28.463 | `__imp__XUsbcamGetState` | `0x838D852C` | `0101021D 0201021D 7D6903A6 4E800420` | `0x831FA610` | `0x831FA600` | `486DDF1D` |
| L520 | 28.461 | `XLiveBaseUnk58046` | *none* | -- | *none* | -- | -- |

Marker prefixes in the image: `0x0100` = xam.xex (456), `0x0101` = xboxkrnl.exe (191),
`0x0102` (13), `0x0104` (53); each thunk's 2nd word = 1st word | `0x01000000`.

Call-site detail: `0x8281FEA4` signs the 0x58-byte buffer at `this+0x22C`;
`0x8282D85C` dismounts the handle in `0x60(r1)` (the log's `0xF800029C`);
`0x831FA600` is a one-call wrapper (`stwu`, `bl XUsbcamGetState`, `cmpwi r3,2`).

`XLiveBaseUnk58046` is **not** a static import of this XEX: no `SetFunction` registration
contains `58046`, no ordinal-`0xE2BE` marker pair exists anywhere in the image under any prefix,
and `fifadllzf` imports no `XLive*` export at all. The log line also differs -- no `__imp__`
prefix, "unimplemented" instead of "stub"; its args `0x301E3000, 0x7019F1A0` are guest
heap-region pointers. => resolved dynamically by ordinal and called through a function pointer,
so there is no guest call site to report.

**Could any initialise the package subsystem? No.** Console key signing, volume dismount,
USB-camera state and Xbox-Live logon are unrelated to RW asset packages; all four fire 3.3 s /
0.4 s before the 28.856 s AV and none is on the RW package chain.

### 3. Gaps in the static search -- all clean

One over-approximate dataflow pass (`gaps5.py`) taints every register r3..r10 that holds the
singleton (global load `0x83A4648C` or a `bl 0x82C501D0`) and propagates along all `bl` edges:
**1,699 functions hold the singleton, 1,797 are reachable with it** (over-approx; the strict
argument-slot count was 113, so this can only be a superset).

| check | result |
|---|---|
| `stw/stb/sth/stfs/stfd` writing `this+0x64`, any class | 68 sites, **0 inside the reachable set** |
| ... of those, with base produced by `addi rX,r3,0x64` etc. ("`this+0x60` then `+4`") | 9 sites formed (`0x826CB988`, `0x829CC5A8`, `0x829CC748`, `0x82AF2270`, `0x82E508B4`, `0x82F9EC6C`, `0x83179974`, `0x834E0DB0`, `0x834E0E90`) -- 2 are pure `addi r3,r3,100; blr` getters, the rest pass/iterate it; **none uses it as a store base** |
| `stwx` with base = singleton and a **constant** index | **0 sites** |
| `stwx` where the singleton is the index reg (EA = rX + this) | 240 sites, all pointer-keyed table idioms; **0 reachable** |
| `stwx` touching an L-tagged (really-singleton) register | **0 sites** |
| `stmw` / `lmw` with singleton base | **0 sites** |
| struct copy / bulk write: reachable functions writing >2 offsets on their `this` | only **2** (`0x829A5FD8`: 0x98/0x9C/0xA0; `0x82C752B8`: 0x28-0x2D/0x30/0x38/0x39) -- neither touches `+0` or `+0x64` |
| whole-196-byte writers | `0x8325E6F8` (196 offsets) is an **unrolled array reset** (stride 8: `stw 0` at +0, `stb 1` at +4 per element), callers `0x8325FA90`/`0x8325FF48`, **not reachable**; `0x83810370` (172 offsets) not reachable. The only whole-object writer for this type remains the ctor `0x82C50EF0` (49 `stw` zero-fills, 0x00..0xC0 skipping 0xB8) |

Caveat: the metric "distinct offsets on incoming r3" over-counts unrolled loops; and calls
through function pointers (`bctr`) cannot be resolved statically, so reachability is a
lower bound on the *call* graph but was deliberately over-approximated on the *data* side.

### 4. Vtable claims: verified vs hypothesis

**Verified** (raw instruction/data words or generated source): the ctor `0x82C50EF0` stores 0 to
offset 0 and zero-fills to +0xC0; the table at `0x82416800` contains `0x82BDB2F8` at `0x8241690C`;
`0x82B8A880`/`0x82B8C618`/`0x82BDBE80` store that table base to `0(r3)`; `0x82BDB2F8` is
`stw r4,100(r3); blr` and has **zero `bl` callers**; `0x83A4648C` has exactly 3 writers
(CREATE `stw r3,0x648C(r11)`, failure path -> 0, destructor -> 0); the crash reads `[this+0x64]`
as a pointer (`lwz r3,100(r3)` -> `lwzx`).

**Hypothesis** (inference, no proof in the image): that `0x82416800` is a *vtable* rather than a
plain function-pointer table; that the singleton is an `RwAsyncLoadPackageSegmented` /
`RwPackageSegmented` (from RW name-pool proximity `0x8259BB08` + thread name `rw45_pkg_factory_seg`;
no RTTI survives); that the four `+0x64`-writing ctors in the class region belong to *other*
classes; that `0x832BF128` is the member accessor for this object.

### 5. Item 6 -- no instrumented run yet

Waiting for the Xenia Canary result before proposing anything. Scripts added this round:
`gaps.py`, `gaps2.py`, `gaps3.py`, `gaps4.py`, `gaps5.py`, `iso_list.txt`, `gaps5_out.txt`.

---

## Xenia Canary discriminator: FULL MATCH RUNS -- port-side divergence confirmed

**User evidence:** the same ISO in Xenia Canary (`D:\FWC10\xenia`, read-only) plays a full
match. So disc/GameData are complete and the null `+0x64` field is a **port-side divergence**.
This supersedes the "incomplete GameData" hypothesis entirely (already withdrawn above).
No rebuild, no override change, no new codegen this round.

### A. Xenia log vs our boot log, side by side (`xenia.log`, 1541 lines, 1 run)

Xenia logs **no timestamps**, so only ordering is comparable.

| | Xenia | ours (boot #5) |
|---|---|---|
| mount | `Mounted ... at \Device\Harddisk0\Partition1` | same (log L25) |
| thread 30 `DLC` | `XThread::Execute thid 30 'DLC'` | `SetThreadName(30, DLC)` |
| thread 31 `DIME` | `thid 31 'DIME'` | `SetThreadName(31, DIME)` |
| threads 32/33/34 | `'Filesystem'` x3 | `SetThreadName(32/33/34, Filesystem)` |
| `\data\sceneassets` | `DiscImageDevice::ResolvePath(\data\sceneassets)` | same attempt, then `VFS: entry not found` + `NtCreateFile FAILED ...genheadtex.big -> 0xc000000f` |
| `\data\ice` | `ResolvePath(\data\ice)` | same + `FAILED ...icenislist.txt -> 0xc000000f` |
| `E:\dvdini` | `!> ResolvePath(E:\dvdini) failed - device not found` x2 | `[error] ResolvePath(E:\dvdini) failed - device not found` x2 (L514/L522) -- **same count** |
| `IoDismountVolumeByFileHandle` | `!> undefined extern call to 838D7D6C IoDismountVolumeByFileHandle` x2 | `IoDismountVolumeByFileHandle(0xf800029c) - stub` x2 (L146/L149) |
| thread 35 | `XThread::Execute thid 35 (handle=F80003BC, 'rw45_pkg_factory_seg', native=00006720)` | `SetThreadName(35, rw45_pkg_factory_seg)` (L694) |
| **after thread 35** | **continues**: `\data\loc`, `\data\movies`, `\data`, `\audiodata\aemsdata`, threads 36-42, `\data\sceneassets\{accessory,fx,hair}`, game keeps running | **AV 1 ms later** (L695): `read of guest 0x0006C6B8 (host 0x000000010006C6B8) on thread 0xF8000358` |

Verified from the files: the startup *sequence to* thread 35 is identical (same thread indices,
same names, same order), the same file probes happen in both, the same import stubs are
undefined/unimplemented in both (Xenia's `IoDismountVolumeByFileHandle` is unimplemented too
and the game is fine) -- and Xenia's thread 35 continues past the point where ours faults.

> **ROUND 16 CORRECTION (reworded).** "Xenia's thread 35 runs **past** the exact point where
> ours faults" is **INFERRED, NOT VERIFIED**. It rests only on the *ordering of kernel calls*
> in Xenia's level-3 log (Xenia keeps emitting kernel calls after the point where ours has
> already died). A level-3 log is not an instruction trace: it never records execution of
> guest `0x82CBD80C`, never records `r3`/`r11`/`*(r3+0x64)` there, and therefore cannot show
> that Xenia executed that instruction at all. Round 16 measured the matching limitation on
> our side: our runtime logs almost no kernel entry points (see Round 16, item 2), so the two
> logs cannot be compared call-for-call either. Verifying this claim needs a guest-address
> breakpoint in Xenia (Round 16, item 1) -- not requested yet.

Xenia-only log lines: `!> undefined extern call to 838D7E8C XamBackgroundDownloadSetMode`
(our run never logs this call at all) and `XThreadF80003BC (23) Stack: 70760000-70770000`
(Xenia logs each guest thread's stack range; ours does not log stacks).
Xenia log ends with `i> 00004188 Cheap-skate exit!` -- the log carries only the startup window,
so no gameplay-time comparison is possible from it.

**NtCreateFile failures are normal (inferred, not verified):** Xenia logs the same
`ResolvePath(\data\sceneassets)` / `(\data\ice)` attempts but does **not** log a failure for a
missing *file* (it only logs `failed - device not found` at device level, which it does log for
`E:\dvdini`). Since the ISO provably has no `data\sceneassets`/`data\ice`, Xenia must fail those
lookups too and just doesn't log them at `log_level = 2`. To verify, Xenia needs `log_level = 3`
(see D).

### B. Cross-boot stability of the watch address (item 1) -- VERIFIED, address stable

Two consecutive boots, both fault lines:

| log | time | line |
|---|---|---|
| `boot_stage6d_runtime.log` | 12:25:28.856 | `read of guest 0x0006C6B8 (host 0x000000010006C6B8) on thread 0xF8000358` |
| `boot_stage6d_rerun.log` | 12:29:14.773 | `read of guest 0x0006C6B8 (host 0x000000010006C6B8) on thread 0xF8000350` |

Identical guest **and** host address. And the mapping is logged, not guessed:
`Guest memory arena mapped: virtual base 0x0000000100000000, physical base 0x0000000200000000`
(boot #5 line 17) => `host = guest + 0x1_0000_0000`, a fixed reserved base (an AV from a null
field is at guest 0x6C6B8 = 0 + 0x6C6B8, and it lands at host 0x1_0000_0000+0x6C6B8 in both runs).

**Exact host address to watch:** `0x83A4648C + 0x64 + 0x1_0000_0000 = 0x1_83A464F0`.

Not verified: that the singleton global itself lies inside that arena mapping rather than in a
separately-relocated module mapping (its code is recompiled *host* code, so the DLL's ASLR base
differs boot to boot -- dump said `0x7FFC9A7C0000`, disk says `0x180000000`), and that a debugger's
hardware breakpoint is inherited by guest-created threads (x86 debug registers are per-thread;
this is the one thing the experiment itself must sanity-check -- see below).

Recipe (hardware write breakpoint, 4 bytes):
1. In the run's log confirm `Guest memory arena mapped: virtual base 0x0000000100000000`
   (0.2 s in) -- if that line ever differs, recompute `arena_base + 0x83A464F0`.
2. Launch the game **under** the debugger (not attach -- object is created ~0.7 s in and the AV is
   ~3 s in): WinDbg `windbg "D:\FWC10\world-cup-2010-pc-port\dist\Output\worldcup2010.exe"`
   (breaks at the initial breakpoint before guest code runs); x64dbg: File > Open, tick
   "Break on entry".
3. Set the watch: WinDbg `ba w4 0x1_83A464F0` / x64dbg command `bphws 183A464F0,w,4`
   (GUI: dump at that address -> Breakpoint -> Hardware, Write, size 4).
4. `g` / F9. On every hit log the value and the writer: WinDbg `dw 1_83A464F0 L1` + `k`;
   x64dbg `dw 183A464F0` + Call stack.
5. Expected hits: **first** hit = the ctor's zero-fill, guest `0x82C50F58` `stw r11,0x64(r3)` with
   `r11 = 0`, on the creating (main) thread. That first hit doubles as the inherited-BP sanity
   check. A **second** hit with a nonzero value is the missing initialiser; **no second hit**
   before the AV means nothing ever populates the field in our build.

### C. What our build does differently around thread 35 (item 2)

**(a) Indirect calls (bctr / vtable dispatch) on the path** -- not enumerated this round
(ran out of the 30-min box). Known from earlier work: the only `mtctr`-based dispatch on the
recorded chain is *inside* the faulting function `sub_82CBD7E0`, which switches on `this[+4]`
(8 cases) **after** the faulting read, so it cannot be the writer. The thread-entry dispatch
(guest `0x837018D0`) resolved and ran (the thread named itself first), so no indirect dispatch on
the path failed, and boot #5 logged no `INVALID INDIRECT CALL`. Remaining to do (cheap): list every
`bctr`/`bcctr` site in the 17 recorded chain functions with the register it dispatches through.

**(b) Kernel calls on the path, with return values** -- from our log, the last calls before the
AV are only: `XamContentCreateEnumerator: added 0 items` x2 (`t10840`), `SetThreadName(30..34)`,
`NtCreateFile FAILED ...genheadtex.big -> 0xc000000f`, `NtCreateFile FAILED ...icenislist.txt ->
0xc000000f`, then thread 35 starts and faults 1 ms later. No other kernel call sits between the
last successful file op and the AV. Divergences flagged:
* `XamBackgroundDownloadSetMode` -- Xenia calls it (`undefined extern call`, i.e. unimplemented
  there and ignored); our run never logs it (either implemented silently or never reached).
* `XamContentCreateEnumerator: added 0 items` (ours) vs Xenia running with content mounted
  (`~ContentPackage: Closing package: rmcsave (Device: \Device\Content\3\)`).
* `XLiveBaseUnk58046` -- see (d).
Timings cannot be compared: Xenia's log has no timestamps.

**(c) Ordering / race** -- no race. The AV proves the object exists (a null *singleton* would fault
at guest 0x64, not 0x6C6B8), so `CREATE` (`0x82C6AFC8`, only caller `0x8265EF7C` inside init
`0x8265EF40`, reached from the static-init pointer table `.rdata 0x82307270/0x823072B8/0x82307300`)
ran and returned ~2.3 s before thread 35 was even created; Xenia's thread 35 does the same work and
continues. Also, no registered function reachable with the singleton writes `+0x64` (0 of 1,797
over-approximate reachable functions), so no concurrency or ordering fix can populate it.
Therefore the divergence must be a **taken/not-taken branch or a host-side service return**, not a
missing initialiser call. (Inferred: that all static-init entries completed before the game starts
threads -- inferred from the object existing.)

**(d) `XLiveBaseUnk58046`** -- VERIFIED from source, `ReXGlue/src/kernel/xam/apps/xlivebase_app.cpp:82`:

```cpp
case 0x00058046: {
  // Required to be successful for 4D530910 to detect signed-in profile
  // Doesn't seem to set anything in the given buffer, probably only takes input
  REXKRNL_DEBUG("XLiveBaseUnk58046({:08X}, {:08X}) unimplemented", buffer_ptr, buffer_length);
  return X_E_SUCCESS;
}
```

So: it is an **xlivebase ordinal `0x58046`** (that is why no import thunk / marker pair exists in
the image -- it is dispatched as an xlivebase app message, not as a static import), it returns
**`X_E_SUCCESS` (0)** and it **writes nothing** to either buffer. It is preceded in our log by
`XLiveBaseGetLogonId(7019F090)`, i.e. it is on the profile/logon path. Whether the guest uses the
return value cannot be settled statically (no guest call site; message dispatch).

**Biggest divergence found:** Xenia runs with `[Profiles] logged_profile_slot_0_xuid =
"E03000007F393D8F"` (auto-login) and a title save on disk -- `content\E03000007F393D8F\454108E4\
00000001\WCSettings0 20261017134145` (494,349 B) + `.header` (40,960 B) + `454108E4.gpd` (38,631 B)
+ `FFFE07D1.gpd` (13,442 B) + `Account` (404 B). Our build creates **no** content/save at all
(verified: nothing matching `WCSettings`/`454108E4`/`.gpd`/`content` under `dist`), and our
enumerator adds 0 items. So Xenia's run has a signed-in profile *with settings*; ours has neither
profile nor save. This is the leading candidate for a startup-path divergence and should be tested
by replicating a profile/save on our side, not by code changes.

### D. Xenia config diffs that could plausibly matter (read-only read of `xenia-canary.config.toml`)

Full active settings were dumped to the analysis scratch. Differences worth naming (Xenia value ->
our runtime): `[Profiles] logged_profile_slot_0_xuid = "E03000007F393D8F"` (we have no profile);
`[Storage] mount_cache = true` (cache device mounted), `mount_memory_unit = false`,
`mount_scratch = false`; `[Kernel] console_type = -1` (retail), `kernel_build_version = 1888`,
`ignore_thread_affinities = true`, `apply_title_update = true`; `[Memory] protect_zero = true`,
`scribble_heap = false`, `writable_executable_memory = true`; `[CPU]
disable_prefetch_and_cachecontrol = true`, `ignore_undefined_externs = true`;
`[x64] enable_host_guest_stack_synchronization = true`, `max_stackpoints = 65536`;
`[GPU] async_shader_compilation = true`; `[General] apply_patches = true` (no `patches\` folder
exists in the install, so nothing is patched -- verified by the file listing);
`[Logging] log_level = 2` (info), `log_mask = 0`.

Ranked by plausibility of affecting *this* startup path: (1) profile/content state, (2) thread
affinity/priority handling, (3) `protect_zero`/`writable_executable_memory`, (4) console type +
kernel build version. Everything GPU/APU/display-related is not plausible for a pre-render AV.

### E. Log is too quiet for a fuller comparison

Xenia at `log_level = 2` logs no guest file-open failures and no kernel-call arguments. To capture
a second, comparable run the config would need `log_level = 3`, plus (optionally)
`log_high_frequency_kernel_calls = true`, and `[Kernel] log_string_format_kernel_calls = true`.
Doing this requires editing `xenia-canary.config.toml`, which is off-limits, so it must be done on
a **copy** of the install -- **awaiting approval, nothing changed, nothing launched.**

### F. Proposed instrumentation (described only -- not written, not built, not run)

1. Log the creation exit (guest `0x82C6AFF8`) and the thread entry (guest `0x837018D0`): both are
   inside generated (rewritten) functions and are called **directly**, so a registry-only hook
   cannot see them. Two options: (i) two override entries whose implementations log and then call
   the original generated symbol (`void ov_82C6AFF8(PPCContext& ctx){ LOG(...); sub_82C6AFF8(ctx); }`)
   -- must first confirm the build's override mechanism rewrites direct call sites, not just the
   registry (not verified); or (ii) a runtime-side hook if the thread start path is central.
2. Log any write to `singleton+0x64`: implement in the runtime memory layer, not in guest code --
   `ReXGlue/src/system/xmemory.cpp`, `Memory::AccessViolationCallback` (line 534, the function that
   already prints the AV line): protect the 4 KB host page holding `0x1_83A464F0` read-only after
   the arena is mapped and log every write whose host address equals `0x1_83A464F0` (value before
   the write, RIP, call stack, thread) then re-arm. Caveat: the page holds neighbouring globals, so
   the filter must be an exact-address compare, and the page is hot (perf).
3. No "missing function" override, and no override that changes behaviour -- logging only.

### G. Item 4: guest-PC reporting in the AV handler (proposal only)

Current handler prints guest address + host address + thread but not *where* the code was:
`ReXGlue/src/system/xmemory.cpp:547`. Host RIP is available in the SEH layer
(`src/core/seh_win.cpp` decodes the exception record / CONTEXT) but is not passed down.
Proposal: (i) thread the faulting host RIP into `AccessViolationCallback` (extra parameter or a
thread-local set by the SEH handler); (ii) build a host-PC -> guest-function map at registration
time from the very same pairs the generated file already hands the registrar
(`registrar->SetFunction(0x83.../0x82..., fn)`); (iii) log
`guest_function=0x%08X (+0x%X host_rva)` alongside the existing line. Guest *instruction* precision
is not achievable this way (the recompiler expands instructions, so host offsets do not map
linearly to guest offsets) -- that would need per-instruction metadata emitted by the codegen.

### H. New lead from this round

* All **158** raw `stw rX,0x64(r3)` sites in the image lie inside registered functions (verified by
  bisecting against the 87,183-entry list) -- so nothing was dropped by function discovery.
* But my tagged dataflow found only **68** of them with a recognised `this`; and the raw scan over
  *all* base registers is 100 functions. The ~32 untagged `stw rX,0x64(rB)` sites are the remaining
  gap: `this` may sit in a register loaded from a global or from a dynamically-offset stack slot.
  Combined with the fact that Xenia runs the *same* code, the writer may also be **host-side**
  (an emulated kernel/host call filling a guest struct passed by the guest) rather than a guest
  `stw`. Next cheap step: enumerate those untagged sites and check their base registers; and check
  whether any kernel call on the path receives a pointer *into* the region `[0x83A4648C, +0xC8)`.

---

## Rounds 7-11 - archived

Rounds 7, 8, 9, 10 and 11 (hardware watchpoints, thread identity, the RenderWare pkg-factory
worker, the throttle runs, the static dig, the sibling-port search) are archived verbatim in
[`NOTES_archive.md`](NOTES_archive.md), in original order, with the corrections made in place at
the time. Their conclusions that still stand are folded into the **Current State** summary at the
top of this file.

---

## Round 12 (2026-10-17): the 83 no-block stubs decoded, the cvar matrix run, Xenia's thread-35 calls, and the doc corrections

Box: 60 min, no rebuilds, no override changes, no Xenia launches. Items 1-4 are answered
below; item 2 (execution check) needs the user's OK before any run; item 7 (backup) was done
first.

### Item 7 - backup (done first, verified)

`D:\FWC10\_backups\20261017-174947\` - `world-cup-2010-pc-port` copied with `dist\GameData`
excluded (robocopy: 21,777 files, 2.29 GB, 0 failed) plus `overrides\` holding both
`fifadllzf_overrides.toml` copies. Both copies hash to
`FFB03BFC9CF50E0932E8A1FDA40CC8D1950E9063A26C81329A05430D62A7787D` (11699 bytes each) - VERIFIED.

### Item 1 - the 83 "no blocks" addresses, decoded from the decompressed images (VERIFIED)

Method: re-derived the address list from the generated sources (a `DEFINE_REX_FUNC` whose body is
only `REX_FUNC_PROLOGUE();`) - exactly **83** (1 in `default`, 82 in `fifadllzf`), matching Stage 5
item B. Decompressed both images with our own `xexdump.exe`: `default.dec.bin` (0x1F0000, base
0x82000000) and `fifadllzf.dec.bin` (0x1850000, base 0x82300000); file offset = VA - base.
Decoded 12 words per address (2 before, 10 forward) with a hand-written PPC decoder.

Result - **no padding at all**:

| class | count |
|---|---|
| real PPC code (>=6/10 forward words decode) | **82** |
| code containing Xenon VMX128 (opcode 4/5) words | **1** (`0x836A4C14`) |
| zero padding / 0xFF padding / data | **0** |

These are real function bodies that codegen emitted as empty stubs (the stub returns immediately
with the caller's registers intact). Reached at runtime they would corrupt logic silently - the
strongest candidate for "a path that never executes correctly" in this build.

Distance to the `+0x64` / package-factory code (nearest key function per stub):

| stub | nearest key function | distance |
|---|---|---|
| `0x82BCBDB8` | `sub_82BDB2F8` (the only `+0x64` setter) | 62,784 before (not adjacent) |
| `0x837045C0` | `sub_837018D0` (worker startup chain) | 11,504 after |
| `0x83704A30` | `sub_837018D0` (worker startup chain) | 12,640 after |
| `0x828032DC` | `sub_82821808` (memset) | 124,204 before |
| `0x82813FF0` | `sub_82821808` (memset) | 55,320 before |

No stub lies inside the singleton ctor/populate/publish bodies, the fault chain, or the worker
bodies. The two `0x8370xxxx` stubs sit in the same code region as the worker's startup chain.
INFERRED (not proven): they are the most interesting of the 83 for this bug, because a silently
returning stub on the worker's path would explain a missing producer - but nothing yet ties them
to thread 35.

### Item 2 - can any of the 83 execute before the AV? (NOT RUN - needs approval)

Proposal, before doing anything: set an `int3` (0xCC) on the **host** entry of each of the 83
stubs' containing functions (or, cheaper, on host `RtlInitializeCriticalSection` for the counter
in item 4) by writing the byte through `WriteProcessMemory` at the host VA, then in the AV
handler report which `int3` was hit and restore the byte. Wait for OK before this: it modifies
code bytes in memory (no rebuild, no file change, but it *does* perturb the run) and it needs a new
tool mode. A cheaper non-invasive variant exists: **hardware execute breakpoints** (DR7 `R/W=00`)
on up to 4 of the 83 host addresses at a time, no code patch. Either way, say the word and I will
state the exact addresses and the exact DR7 words before running.

### Item 3 - cvar surface vs the Xenia config, and the 5-run matrix (VERIFIED)

Xenia's config values (read-only, `xenia-canary.config.toml`): `ignore_thread_priorities = false`,
`ignore_thread_affinities = true`, `protect_zero = true`, `writable_executable_memory = true`,
`kernel_build_version = 1888`, `console_type = -1`.

Our runtime (`REXCVAR_DEFINE_*` in source **and** the strings in the shipped
`rexruntime.dll`): `ignore_thread_priorities` (default **true**), `ignore_thread_affinities`
(default true), `protect_zero` (default true), `writable_executable_memory` (default true),
`clock_no_scaling` (default false). **`kernel_build_version` and `console_type` do not exist at
all** - ABSENT from the DLL's strings as well as from the source.

So of the five the user named, **exactly one is a real difference: `ignore_thread_priorities`
(Xenia false, ours true)**.

Run matrix (20 s each, one at a time, fresh log per run, control first):

| run | flag | AV? | AV time vs `SetThreadName(35,...)` |
|---|---|---|---|
| control | - | **yes** - read of guest `0x0006C6B8`, thread `0xF800034C` | same millisecond |
| 1 | `--ignore_thread_priorities=false` | **yes**, identical | +1 ms |
| 2 | `--ignore_thread_affinities=false` | **yes**, identical | +1 ms |
| 3 | `--no-protect_zero` | **yes**, identical | +1 ms |
| 4 | `--no-writable_executable_memory` | **yes**, identical | +1 ms |

The AV is unchanged in all five. A sixth run with `--log_high_frequency_kernel_calls=true` also
changed nothing: that cvar is **defined but never read** anywhere in the source (dead), so it
cannot turn on kernel-call logging. Log volume per fresh run is ~716-886 lines (the 38,012-line
figure quoted earlier came from an **appended** log across runs - corrected here).

### Item 4 - Xenia thread 35's kernel calls, in order (VERIFIED from the level-3 log)

Worker handle in that log = `F80003BC` (from `XThread::Execute thid 35 (handle=F80003BC,
'rw45_pkg_factory_seg (F80003BC)', native=000027A4)`). **All 94 lines attributed to that handle
across the 197,511-line log:**

    17889  XThread::Execute thid 35 (...)
    17890  KeTlsSetValue(00000001, 40103E40)
    17891  ObReferenceObjectByHandle(F8000068, 30000000, ...)
    17892  ObDereferenceObject(3001A010, ContextArg)
    17893  KeTlsSetValue(00000002, F80003BC)
    18116  Added handle:F80003C8 for class xe::kernel::XObject
           then 88 x RtlInitializeCriticalSection(<addr>) at stride 0x60, in two runs
           (25 then 63), the last at log line 115501; nothing else, no waits.

Call types: `RtlInitializeCriticalSection` 88, `KeTlsSetValue` 2, `ObReference/ObDereference` 1+1,
`XThread::Execute` 1.

Creator's ordered calls around the create (`F8000330`): `ExCreateThread(..., 8282FD10, 828360B8,
40103E40, 00000001)` -> `ExCreateThread Active: Thread Initially Suspended` -> `XThreadF80003BC`
-> `RtlRaiseException(406D1388)` -> `SetThreadName(35, rw45_pkg_factory_seg)` ->
`ObReferenceObjectByHandle(F80003BC, ...)` -> `KeSetBasePriorityThread(301E5010, 00000001)` ->
`ObDereferenceObject` -> `KeSetAffinityThread(301E5010, 00000010, ...)` -> `NtResumeThread`.

Waits: **0** `NtWaitForSingleObject` / `KeWaitForSingleObject` / `NtDelayExecution` in the *entire*
197,511-line log (with 111,657 `NtReleaseMutant`). So Xenia's level-3 log does not log wait calls -
the worker's silence about waits is **not** evidence that it never waits (INFERRED; the 88
critical-section inits and the absence of every other call type is measured).

Contrast with our worker (from earlier rounds, VERIFIED): it executes ~15.6 ms of guest code and
then parks in a guest wait at `sub_8282DD28+0x19A` (handle `0xF28`, no timeout).

Counting our worker's critical-section inits needs a counter: our runtime **does not log**
`RtlInitializeCriticalSection` / `KeTlsSetValue` at all, and the cvar that would enable it is dead.
The honest options are (a) hardware execute breakpoints / an int3 counter on the host
`RtlInitializeCriticalSection` (the item-2 approval), or (b) leave it as "not comparable". If Xenia
does 88 and our worker does 0, the worker is on a *different branch* - that is the decisive value
of the experiment.

### Items 5+6 - documentation (VERIFIED by re-reading after write)

Stale claims corrected: the overrides status at the top (was "one entry" -> **266 entries**,
SHA-256 verified), the bottom `fifadllzf_overrides.toml` row, the 867-function gap explanation
(marked **UNVERIFIED** in both places), the "(a) never called - this is the only option"
wording (now "best supported, NOT proven"), and Round 8's "the AV is not a scheduling race
(VERIFIED)" heading (**SUPERSEDED**).

A one-page **Current State** summary was added at the top of this file, and Rounds 7-11 were moved
verbatim to `NOTES_archive.md` (with a pointer + the carry-over conclusions left here).

---

## Round 13 (2026-10-17): the 83 stubs cross-referenced and disassembled, and the SDK logic behind "cannot seal / has no blocks"

Box: 60 min, no rebuilds, no override changes, no Xenia launches. Item 5 was skipped (it needs the
execute-breakpoint tooling that item 4 is still waiting on; the user's own <10 min condition did not
hold). Every claim below is marked VERIFIED or INFERRED.

### Correction carried in this round - **WITHDRAWN IN ROUND 14, see Round 14 item 0**

(The text that stood here claimed the translation rule was `host = guest + 0x8000_0000`. That was
wrong: it promoted an *unverified* mirror candidate to a rule. The verified rule is
`host = base + guest`. Round 14 item 0 records the withdrawal with evidence; the original wording is
kept only in this stub so the audit trail shows what was believed when.)

### Item 1 - cross-reference of all 83 (VERIFIED)

Method: (a1) branch comments in the generated sources (`// b 0x...`, tracked per
`DEFINE_REX_FUNC`); (a2) real `b`/`bc`/`bl` instructions decoded from both decompressed images;
(b) 32-bit big-endian occurrence of the address in a non-executable section, with the contiguous
run measured. Images are in *mapped* layout (file offset = VA - base); the PE's `rawptr` fields are
stale on-disk values, so the section ranges were taken from `va`/`vsize` - this mattered: using
`rawptr` produced a bogus "83/83 called" result which was discarded.

| group | count |
|---|---|
| table-referenced (a 32-bit BE pointer in `.rdata`/`.data`) | **4** |
| directly-called (a real branch to it, or a generated `sub_XXX(ctx,base)` call) | **83** |
| table-only | 0 |
| neither | **0** |

Table-referenced four: `0x8211A170` (default), `0x82BCBDB8`, `0x831A11B8`, `0x8323FB38`.
All four are also directly called. Detail (section, pointer VA, enclosing run, index, neighbours):

| stub | section | pointer at | run | entries | index | neighbours |
|---|---|---|---|---|---|---|
| `0x8211A170` | default `.rdata` | `0x8201A540` | `0x8201A518..0x8201A578` | 24 | 10 | `0x8211A160`, `0x8211A168`, `0x82118380`, `0x82118418` |
| `0x82BCBDB8` | fifadllzf `.rdata` | `0x824116D8` | `0x82411540..0x82411860` | 200 | 102 | `0x82BC7C18`, `0x828330F0`, `0x82AEB648`, `0x82B094E0` |
| `0x831A11B8` | fifadllzf `.rdata` | `0x824F1CF8` | `0x824F1CD0..0x824F1D30` | 24 | 10 | `0x831A11A8`, `0x831A11B0`, `0x8319F3B8`, `0x8319F450` |
| `0x8323FB38` | fifadllzf `.rdata` | `0x8252274C` **and** `0x82522828` | `0x82522504..0x82522AA4` | 360 | 146 and 201 | `0x83244B90`, `0x8322B978`, `0x836D1548`, `0x8365C0E0` |

Every enclosing run contains only code pointers (VERIFIED), i.e. these are address tables, not data
tables. Two of the runs are small (24 entries) and the neighbours include the two instructions
immediately *before* the stub (`0x8211A160`/`0x8211A168`, `0x831A11A8`/`0x831A11B0`), so they are
address lists of contiguous code regions. `0x8323FB38` is referenced twice, from two tables that
overlap in one 360-entry run. **Which function installs each table is NOT determined** - the table
bases and all four pointer VAs have **no direct reference in the generated sources** (verified by
search; the tables are installed by code the recompiler could not fully resolve, or by data-to-data
initialisation), so "which class installs it" stays open.

Direct callers, two independent sources:
* generated code emits an actual **call** for 22 of them, e.g. `sub_82744AD0` -> `beq 0x82744B08`;
  `sub_827C0418` -> `bgt 0x827C0488`; `sub_830CDD30` -> `bne 0x830CDD58`; `sub_82E455F0` -> `b
  0x82E45604` (2 sites); `sub_83439CE0` -> `b 0x83439DE0` (4 sites); `sub_82D94AA0` -> `b
  0x837045C0`; `sub_82D91128` -> `b 0x83704A30`; `sub_837045B8` -> `b 0x8375B9D0`;
  `sub_837A6B98` -> `b 0x837A6BC8`; `sub_837AA858` -> `b 0x837AA88C`; `sub_837B7280` -> `b
  0x837B72B0`; `sub_82BCBE88` -> `b 0x82BCBDB8`; `sub_831A11C0` -> `b 0x831A11B8`;
  `sub_8323FBD8` -> `b 0x8323FB38`; `sub_8211A178` -> `b 0x8211A170` (default); `sub_82744AD0`,
  `sub_82F4FF40`, `sub_82F4FF70`, `sub_828B12B8`, `sub_828AE890`, `sub_828AE898`, `sub_828B0078`
  and `sub_833581A8` for the remainder.
* the raw image contains a `b`/`bc` to all 83, overwhelmingly a **conditional** branch just before
  the address (shared-tail / dispatch-target pattern).

Consequence: **none of the 83 is unreferenced.** An empty stub that returns immediately while
retaining the caller's registers is therefore a silently wrong path whenever any of the 22 emitted
call sites fires.

### Item 2 - full disassembly (control-flow walk, not the 6-of-10 heuristic) (VERIFIED)

Walker: control flow from the entry, bounded by the next generated entry and by 0x800 bytes,
following fall-through and conditional targets, stopping on `blr`/`bctr`/out-of-range `b`.
Results (all 83; `round13_item12_out.txt` holds the full listing):

* bodies are **small**: 1 instruction (`0x83327ACC`, `0x83433410`, `0x83704A30`, `0x8375B9D0`),
  mostly 2-6, with three outliers (`0x82744AF4` 27, `0x83439DDC` 22, `0x83439DE0` 21,
  `0x837B72B0` 19, `0x837A6BC8` 18, `0x837AA88C` 13).
* terminators: **71 end in `blr` only**; 12 do not -
  `0x8211A170`, `0x82BCBDB8`, `0x831A11B8`, `0x837045C0`, `0x83704A30`, `0x8375B9D0`,
  `0x837A6BC8`, `0x837AA88C`, `0x837B72B0` end in a tail `b`, and `0x82A63768`, `0x82ADF698`,
  `0x82ADF6B0` end in `bctr`.
* **stores to a package-factory field: exactly one stub**, and it is offset 0, not 0x64:
  `0x8386C848` = `stw r4, 0(r11)`. No stub writes `+0x64`, `+0x08`, `+0x0C`, `+0x10`, `+0x14` or
  `+0xAC`.
* loads from those field offsets: 7 stubs (offsets 0 or 0xC only).
  => the 83 are **not** the producer of the missing `+0x64` pointer (VERIFIED), consistent with
  Round 11's write-history of three stores.

### Item 3 - the SDK logic behind the two messages (VERIFIED from source, quoted)

"has no blocks" - emitted body (`src/codegen/function_graph.cpp:356-373`):
```cpp
  // --- Empty stub for functions with no blocks ---
  if (blocks().empty()) {
    REXCODEGEN_WARN("Function 0x{:08X} has no blocks - generating stub", base());
    ...
    emit_println(out, "// STUB: Function at 0x{:08X} has no discovered code blocks", base());
    emit_println(out, "DEFINE_REX_FUNC({}) {{", name);
    emit_println(out, "\tREX_FUNC_PROLOGUE();");
```
"cannot seal" (`function_graph.cpp:1051-1066` and `canSeal` at `:120-130`):
```cpp
bool FunctionNode::canSeal() const {
  if (state_ != FunctionState::kDiscovered) return false;
  if (isImport()) return true;              // Imports can seal without blocks
  if (blocks_.empty()) return false;        // Non-imports must have blocks
  if (!unresolvedJumps_.empty()) return false;
  return true;
}
...
        REXCODEGEN_DEBUG("FunctionGraph::sealAllReady: 0x{:08X} ({}) cannot seal ({} unresolved)",
                         base, node->name(), node->unresolvedJumps().size());
```
So **"(0 unresolved)" means the failure is *not* unresolved branches - it is the empty block list**
(the message always prints the unresolved count, which is 0 here). `sealAll()`'s own reason string
for the same state is `"has 0 blocks (non-import)"` (`:1085-1086`).

**Why real code ends up with no blocks** - measured, not guessed:
* the complete console log (`codegen_console.log`, the 21 MB full run) contains **92,659**
  `DISCOVERED with N blocks` lines and exactly **83** `cannot seal (0 unresolved)` lines, and
  **zero** occurrences of either discovery-failure message (`"no blocks found for function"` from
  `phase_discover.cpp:102`, `"not in any code region"` from `:93`).
* the aggregate line is `FunctionGraph::sealAllReady: sealed 86551 functions, 82 could not seal`
  in the fifadllzf stage-6 run - **82**, exactly the fifadllzf stub count; with the single default
  stub, 83. The identity "the 83 stubs == the 83 non-sealable functions" is therefore **VERIFIED**.
* `phase_discover.cpp:53-56` shows a node whose blocks were never attempted is left in
  `kRegistered`, which `canSeal()` rejects - and it still gets a stub at emission.
* **VERIFIED:** the 83 addresses are never mentioned in the log before the seal step and were
  therefore added silently after the last `discoverPendingFunctions` call (`phase_gapfill.cpp:225`
  is the last one; `GapFill` runs after `Discover`: the phase order in the log is
  Register -> Scan -> Discover -> **GapFill** -> Merge -> Validate -> Write).
* **INFERRED (strong):** they are the `bl` targets that `discoverFunction` registers as
  `addFunction(target, 4, DISCOVERED, true)` (`phase_discover.cpp:116-122`) *while discovering the
  GapFill segments* - that snapshot loop (`phase_discover.cpp:424-432`) cannot discover functions
  added during its own pass, and no further pass runs. It matches every observation: no discovery
  attempt logged, no mention before "cannot seal", tiny declared size, and bodies that are really
  1-27 real instructions (`discoverBlocks` never ran, so the block list stayed empty while the code
  itself is intact). The declared size is irrelevant to the emitted stub.
* Consequence (**INFERRED, testable without touching the runtime**): giving any of these addresses
  an `end` in `fifadllzf_overrides.toml` makes it a CONFIG function, which `discoverFunction`
  explicitly discovers using its declared size (`phase_discover.cpp:72-74`) - i.e. the fix path for
  this class is an override, exactly as the Stage 6 note assumed.

### Override schema keys `parent` and `share_registers` (VERIFIED from source, quoted)

Parsed in `src/codegen/config.cpp:195-200`:
```cpp
      FunctionConfig fcfg;
      fcfg.size = (*table)["size"].value_or(0u);
      fcfg.end = (*table)["end"].value_or(0u);
      fcfg.name = (*table)["name"].value_or(std::string{});
      fcfg.parent = (*table)["parent"].value_or(0u);
      fcfg.shareRegisters = (*table)["share_registers"].value_or(false);
```
Declarations (`include/rex/codegen/config.h:44-62`):
```cpp
struct FunctionConfig {
  uint32_t size = 0;    // Explicit size in bytes (mutually exclusive with end)
  uint32_t end = 0;     // End address, exclusive (mutually exclusive with size)
  std::string name;     // Custom symbol name (empty = auto-generate sub_XXXXXXXX)
  uint32_t parent = 0;  // Parent function address (0 = standalone, non-zero = chunk)
  // Keep non-volatiles in ctx instead of localizing them. Marks an MSVC SEH
  // funclet, which reads the registers its owner left live and would see a zero
  // from a local. Callers sync their localized copies across the call site.
  bool shareRegisters = false;
  ...
  // Returns true if this is a discontinuous chunk belonging to a parent function
  bool isChunk() const { return parent != 0; }
```
* `parent` makes the entry a **discontinuous chunk of a named parent** (`isChunk()`), i.e. a piece of
  another function's body that is not contiguous with it (shared tail / split block). It is for
  addresses that are fragments, not for standalone functions.
* `share_registers` keeps non-volatiles in `ctx` rather than localising them; it exists for **MSVC
  SEH funclets** that read the registers their owner left live. Nothing else needs it.

Which form is right for these entries (**INFERRED from the disassembly**): **`end` (or `size`) only,
standalone** - every one of the 83 decodes as a complete unit that ends in `blr`/`bctr`/tail `b`, so
none is a fragment needing `parent`, and there is no evidence of an SEH funclet needing
`share_registers`. This is also the form of the 266 existing entries.

Does it match the `0x835F7700` situation (an entry inside another function's range)? **Partly, and
the distinction matters (VERIFIED from the two records):** `0x835F7700` sat in a *gap* - the
registered `0x835F76D8` ends exactly at `0x835F7700` and the next registered function starts at
`0x835F7718` - so it was *adjacent* to, not inside, another function, and it needed no `parent`.
The 83 here are entries whose addresses are *also* not inside a registered function's declared
range (the Stage 6b criterion checked exactly that for its 184-entry sibling set); they are
registered-but-never-analysed, which is a different defect from "inside another function". If a
genuine interior address ever needs to be callable, `parent` is the schema-correct mechanism;
it is not the right mechanism for these 83.

### Item 4 - proposed execute-breakpoint shortlist (NOT RUN - waiting for OK)

Same tool slot semantics as before: DR0-DR3 are the four breakpoints, `R/W = 00` (execute),
`LEN = 00`; the host address goes in DR0-3 verbatim. Batch 1 (4 at a time), with host VAs
(host = guest + 0x8000_0000) and evidence:

| # | guest (host) | evidence |
|---|---|---|
| 1 | `0x837045C0` (`0x1037045C0`) | called by `sub_82D94AA0` (`b`); same `0x8370xxxx` cluster as the worker startup chain `0x837018D0`; tail `b` to `0x8375B9E8` |
| 2 | `0x83704A30` (`0x103704A30`) | called by `sub_82D91128`; 1-instruction body ending in tail `b 0x8375C040` |
| 3 | `0x8375B9D0` (`0x10375B9D0`) | called by `sub_837045B8` - a *registered* function inside the worker cluster; 1 instruction + tail `b 0x83781C78` |
| 4 | `0x82BCBDB8` (`0x102BCBDB8`) | the only stub in the `0x82BCBxxx` island, 62 KB before the sole `+0x64` setter `sub_82BDB2F8`; table-referenced **and** called by `sub_82BCBE88` |

Batch 2 (if batch 1 shows no hit before the AV):
`0x831A11B8` (`0x1031A11B8`, table + called), `0x8323FB38` (`0x10323FB38`, table + called),
`0x82E45604` (`0x102E45604`, 2 emitted call sites), `0x83439DE0` (`0x103439DE0`, 4 emitted call
sites, 21-instruction body).

Batch 3: `0x8211A170` (`0x10211A170`, the only default stub), `0x82744AF4` (`0x102744AF4`,
27-instruction body), `0x837A6BC8` (`0x1037A6BC8`), `0x837AA88C` (`0x1037AA88C`).

Planned DR7 (4 execute breakpoints, L0-L3 enabled, all RW=00/LEN=00): **`0x00000055`**.

What this buys: if any of these stubs *executes* before the AV, we learn that the faulting run
walks a path through a body that codegen turned into a no-op - a concrete, non-speculative link
between the stub class and the crash. If none executes, the stub class is exonerated for this
crash, and the search moves to the `bctr` dispatch question (Round 11 item 3/n-m).

### Override-change procedure (kept, not used)

No override file was read-modify-written this round. If any of the 83 is ever added, the procedure
stays: write **both** copies (Installer template + stage-4 workspace config) with identical bytes,
verify SHA-256 equality, and take a timestamped copy into `D:\FWC10\_backups\` first.

---

# Round 14 (2026-10-17): the 83 - classify, emission semantics, override proposal

No rebuild, no override edit, no codegen rerun, no Xenia launch. Work was analysis of the existing
generated sources, the two decomressed images, the shipped binaries and the SDK source. Two earlier
errors are corrected first. VERIFIED/INFERRED marks throughout.

Artifacts: `round14_classify.py` + `round14_classify_out.txt` (8.3 s), `round14_sites.py` +
`round14_sites_out.txt` (291.7 s - it scans every generated .cpp), `round14_proposal.py` +
`round14_proposal_out.txt`. Nothing in the project tree changed except this file.

## Item 0 - two corrections (both VERIFIED)

**0a. The memory translation rule.** Round 13's edit to this file ("host = guest + 0x8000_0000")
was **wrong** and has been withdrawn above. The rule the runtime actually uses is visible in its own
log text, in every run, 30+ times:

```
Unhandled guest access violation: read of guest 0x0006C6B8 (host 0x000000010006C6B8)
```

i.e. **`host = base + guest`**, where `base` is a runtime-allocated, 4 GB-aligned guest memory base:
`0x1_0000_0000` in every logged run but one, which used `0x2_0000_0000`
(`boot_watch1_runtime.log:1449` -> `host 0x000000020006C6B8`). The generated load/store macros agree:

```c
#define REX_PHYS_HOST_OFFSET(addr) (((u32)(addr) >= 0xE0000000u) ? 0x1000u : 0u)
#define REX_LOAD_U32(x) __builtin_bswap32(*(volatile u32*)(base + (u32)(x) + REX_PHYS_HOST_OFFSET(x)))
```
(`codegen_pch_h.inja.h:133,142`). There is **no masking of the 0x80000000 window** anywhere in the
generated code. The value `0x103A4648C` that Round 13 quoted as a "mirror" of guest `0x83A4648C` is
therefore **UNVERIFIED** - it came from a masked-window hypothesis, never from a logged translation.
It must not be used until re-measured. The `+0x1000` bump applies only for guest >= `0xE0000000`.

**0b. Execute breakpoints cannot use memory addresses at all.** `PPCFuncMapping` is
`{ size_t guest; PPCFunc* host; }` (`func.h:57`) and the codegen emits one entry per function in
`PPCFuncMappings[]` (`codegen_init_cpp.inja.h:37`). The recompiled bodies are *host* code inside the
shipped binaries, so the address of "the code of guest function X" is the `host` field resolved at
runtime, not `guest + base`. Measured (static, from the shipped files, all 64-bit LE `{guest,host}`
pairs in the mapping table):

| module binary | image base | example |
|---|---|---|
| `worldcup2010_fifadllzf.dll` | `0x180000000` | guest `0x837045C0` -> host `0x184924900` (rva `0x4924900`) |
| `worldcup2010.exe` (entrypoint/default) | `0x140000000` | guest `0x8211A170` -> host `0x140214810` (rva `0x214810`) |

The rva is `host - image base`; the runtime address is `load_base + rva` (INFERRED: plain PE
relocation, not observed at runtime this round). This is the mechanism Round 13 item 4 was missing -
that item remains **not run** and is now superseded.

## Item 1 - classify the 83 (VERIFIED)

Walked each stub's CFG from its entry inside its own image (following fall-through, conditional
branches and *internal* unconditional branches; stopping at `blr`/`bctr` and at unconditional
branches to another registered function = tail call). Extent = `max(reachable) + 4`.

**1a. epilogue/tail fragment vs leaf:** **71 leaf, 12 epilogue/tail fragment** (the 12 are exactly
the earlier "non-blr" set). Flags found: `mtlr` (LR restore), `stack_restore_addi`/`_from_mem`
(r1 restore), `load_from_stack_into_nonvolatile` (r14-r31 restore), and onward `b`/`bctr`.
Additionally and importantly: **not one of the 83 reads an incoming non-volatile register**
(no body reads r14-r31 before writing it). Their only register inputs are r3-r12. That is the
measurement item 2's safety verdict rests on.

**1b. the 12 non-blr stubs, their skipped destinations, and whether those are registered:**

| stub | class | onward destination(s) | destination registered? |
|---|---|---|---|
| `0x8211A170` (default) | epi | `b 0x82118AB8` | **yes** (`0x1404D3DC0`) |
| `0x82A63768` | epi | `bctr` | CTR-sourced (indirect, not statically resolvable) |
| `0x82ADF698` | epi | `bctr` | CTR-sourced |
| `0x82ADF6B0` | epi | `bctr` | CTR-sourced |
| `0x82BCBDB8` | epi | `b 0x8267EB98` | **yes** |
| `0x831A11B8` | epi | `b 0x8319FB28` | **yes** |
| `0x837045C0` | epi | `b 0x8375B9E8` | **yes** |
| `0x83704A30` | epi | `b 0x8375C040` | **yes** |
| `0x8375B9D0` | epi | `b 0x83781C78` | **yes** |
| `0x837A6BC8` | epi | `b 0x82A8A1E0` (x2) | **yes** |
| `0x837AA88C` | epi | `b 0x82A8A1E0`, `b 0x837FF750` | **yes**, **yes** |
| `0x837B72B0` | epi | `b 0x82A92468`, `b 0x837B7300`, `b 0x82A8A1E0` | **yes**, no, **yes** |

Every destination except `0x837B7300` is a registered function; `0x837B7300` is not a function entry
but lies *inside* `0x837B72B0`'s own CFG extent (`end = 0x837B7304`), i.e. it is an internal label of
that fragment, so it resolves as `goto loc_` and not as an unknown branch. So declaring these stubs
introduces **no unresolved branch target** (no `REX_FATAL`) - that is the check that makes item 3
safe for the 12.

## Item 2 - what the generated code does with these targets (VERIFIED, quoted)

Two deciders, both in the SDK source. First `classifyTarget` (`src/codegen/function_graph.cpp`):

```cpp
// Case 1: Target is an import - always a call/tail-call
// Case 2: target == caller's own entry: bl -> Function, b -> InternalLabel
// "A block discovered in this caller stays local even if a shared-tail entry
//  is registered at the same address later during iterative discovery."
  if (callerFn && callerFn->isLabel(target) && callerFn->containsAddress(target))
    return TargetKind::InternalLabel;
// Case 3: Target is a DIFFERENT function's entry point - this is a call/tail-call
  if (isEntryPoint(target)) return TargetKind::Function;
// else inside caller -> InternalLabel, otherwise Unknown
```

Then the emitter, for *conditional* and unconditional branches alike
(`src/codegen/builders/helpers.h`, `emitBranchWithBoundsCheck`):

```cpp
    case TargetKind::InternalLabel:
      ctx.println("\tif ({}) goto loc_{:X};", condition, target);   break;
    case TargetKind::Function:
    case TargetKind::Import:
      ctx.println("\tif ({}) {{", condition);
      ctx.emit_function_call(target);
      ctx.println("\t\treturn;");
      ctx.println("\t}}");                                          break;
    case TargetKind::Unknown:
      REXCODEGEN_ERROR("Unresolved {} target 0x{:08X} from 0x{:08X}", ...);
      ctx.println("\tif ({}) REX_FATAL(\"Unresolved branch ...\");", ...);  break;
```

So: **a branch whose target the caller's own blocks already contain becomes `goto loc_X`** (the body
is emitted *there*, inside the caller); **a branch to a different function's entry becomes a real
call + return** (`sub_X(ctx, base); return;`). Both forms were observed in the sources:

```cpp
// sub_82744AD0 (inside its own body):        // sub_82D94AA0 (tail b to a function):
	// beq 0x82744b08                           // b 0x837045c0
	if (ctx.cr0.eq) goto loc_82744B08;          sub_837045C0(ctx, base);
	                                            return;
// sub_827C04D4 (conditional, target is a function):
	// bgt 0x827c0488
	if (ctx.cr0.gt) {                           <- emitted as a CALL, not a goto
```

**Non-volatile sync at a call site.** `emit_function_call` flushes the caller's localized
non-volatiles into `ctx` - and reads them back - **only when the target `sharesRegisters()`**:

```cpp
  // ... the owner left live, so hand it the localized copies through ctx and take
  // them back afterwards. Only registers already localized here can be live at this point
  if (cfg.nonVolatileRegistersAsLocalVariables && ...) { ... ctx.r{} = r{}; ... }
```

Measured: an exhaustive search of every generated `fifadllzf_xeX` `.cpp` finds **zero** occurrences
of the `ctx.rNN = rNN;` sync form - no call site in this module targets a `share_registers` function -
and item 1a shows no stub reads an incoming non-volatile in the first place. **Verdict: a standalone
entry is safe for these 83; `parent = <address>` is not needed** (and would be wrong: a chunk/parent
entry is emitted as a label inside the parent, not as a callable function, so an indirect call could
never reach it - which is the very failure we are fixing).

**Which stubs are actually reached as calls (the authoritative split).** Classified every emitted
branch site in the generated sources by target (comment `// <mnem> 0x<target>` -> the following emitted
lines): of 83 stubs, **14 have at least one real `sub_X(ctx, base)` call site** and **69 are reached
only by `goto loc_X`** (so their body is already emitted inside the caller; the empty stub is dead
weight but harmless). No stub has zero sites and none emits `REX_FATAL`.

## Item 3 - the override proposal (checks VERIFIED, not applied)

Existing `fifadllzf_overrides.toml` holds 266 entries. For each of the 83 I computed the CFG-validated
`end` and checked it against (i) every registered function entry in the generated entry list,
(ii) the other stubs, (iii) the 266 existing override ranges, (iv) duplicates:

- **79 pass every check** (78 fifadllzf + 1 default); **0 duplicates**, **0 overlap with the 266**.
- **4 conflict**: the CFG extent genuinely contains a *sibling* registered entry, so no single
  contiguous `end` both covers the reachable code and avoids overlapping:
  `0x82744AF4` (end `0x82744B60`, contains `0x82744B08`), `0x83358280` (contains `0x83358288`),
  `0x83433404` (contains `0x83433410`), `0x83439DDC` (contains `0x83439DE0`).
  Truncating to the sibling (e.g. `0x82744AF4 end = 0x82744B08`) pushes real branches
  (`0x82744B10`, `0x82744B4C`) outside the function - those are not entries, so `classifyTarget`
  would return `Unknown` -> `REX_FATAL` at runtime. **All 4 are in the harmless `goto`-only set.**

**Tier 1 - the 14 called stubs (13 fifadllzf + 1 default). These are the actual bugs; all clean:**

| stub | end (exclusive) | span | class | host pointer (static) / rva |
|---|---|---|---|---|
| `0x8211A170` *(default)* | `0x8211A178` | 8 | epi | `0x140214810` / `0x214810` (exe) |
| `0x82A63768` | `0x82A6377C` | 0x14 | epi | `0x182F8FD00` / `0x2F8FD00` |
| `0x82ADF698` | `0x82ADF6B0` | 0x18 | epi | `0x186CF3230` / `0x6CF3230` |
| `0x82ADF6B0` | `0x82ADF6C8` | 0x18 | epi | `0x18499D5C0` / `0x499D5C0` |
| `0x82BCBDB8` | `0x82BCBDCC` | 0x14 | epi | `0x185388710` / `0x5388710` |
| `0x82DA6148` | `0x82DA6154` | 0xC  | leaf | `0x1802D78B0` / `0x2D78B0` |
| `0x831A11B8` | `0x831A11C0` | 8 | epi | `0x1801E05A0` / `0x1E05A0` |
| `0x83232D58` | `0x83232D6C` | 0x14 | leaf | `0x182DF2F60` / `0x2DF2F60` |
| `0x8323FB38` | `0x8323FB48` | 0x10 | leaf | `0x1860A0B90` / `0x60A0B90` |
| `0x8323FB6C` | `0x8323FB7C` | 0x10 | leaf | `0x181B3F530` / `0x1B3F530` |
| `0x8323FB8C` | `0x8323FBA0` | 0x14 | leaf | `0x180EF6B40` / `0xEF6B40` |
| `0x837045C0` | `0x837045CC` | 0xC  | epi | `0x184924900` / `0x4924900` |
| `0x83704A30` | `0x83704A34` | 4 | epi | `0x183772BA0` / `0x3772BA0` |
| `0x8375B9D0` | `0x8375B9D4` | 4 | epi | `0x18690FB00` / `0x690FB00` |

Ends are the CFG-validated extents (max reachable + 4), not "first terminator": e.g. `0x82A63768`'s
first terminator is a conditional branch but the extent runs to `0x82A6377C`. All 4 table-referenced
stubs (`0x82BCBDB8`, `0x831A11B8`, `0x8323FB38` and default `0x8211A170`) are in this tier.

**Tier 2 - 65 goto-only clean stubs.** Entries for them are no-ops (the body is already emitted in the
parent as `loc_`), which matches the standing policy in the file header ("add one at a time only if a
boot crash points at it"). Prepared on request, but not recommended as a batch - they cannot change
the AV.

**Tier 3 - the 4 conflicting stubs.** `parent =` cannot make them callable; a shortened `end` is fatal.
Recommendation: leave them (all 4 are goto-only/harmless).

**What the default module needs (separate from the 82).** The entrypoint module is linked into
`worldcup2010.exe` (no default DLL), its mapping table is in that exe (verified: `{ 0x8211A170,
sub_8211A170 }` at `generated/default/...init.cpp:3729`; host `0x140214810` in the exe). Its manifest
section is generated by `Installer/BuildWorldCup2010.ps1` and currently has no includes:

```toml
[entrypoint]
file_path = "$gameDataUnix/default.xex"
out_directory_path = "generated/default"
includes = []                      # <- must become ["config/default_overrides.toml"]
```

So the default module needs (a) a new `config/default_overrides.toml` with the single entry
`"8211A170" = { end = 0x8211A178 }` written to **both** copies, and (b) that one-line include added to
the build script's `[entrypoint]` heredoc (line ~148). Both config dirs currently hold the identical
5 files and **no** default override file (verified).

### Item 3 appendix - the full prepared list (all 82 fifadllzf stubs; also in `round14_proposal_out.txt`)

Tier 1 - **recommended** (13; real `sub_X(ctx, base)` call sites exist today). Append to the 266:

```
"82A63768" = { end = 0x82A6377C }
"82ADF698" = { end = 0x82ADF6B0 }
"82ADF6B0" = { end = 0x82ADF6C8 }
"82BCBDB8" = { end = 0x82BCBDCC }
"82DA6148" = { end = 0x82DA6154 }
"831A11B8" = { end = 0x831A11C0 }
"83232D58" = { end = 0x83232D6C }
"8323FB38" = { end = 0x8323FB48 }
"8323FB6C" = { end = 0x8323FB7C }
"8323FB8C" = { end = 0x8323FBA0 }
"837045C0" = { end = 0x837045CC }
"83704A30" = { end = 0x83704A34 }
"8375B9D0" = { end = 0x8375B9D4 }
```

(default module, separate file `config/default_overrides.toml`:)
`"8211A170" = { end = 0x8211A178 }`

Tier 2 - **prepared, not recommended** (65; `goto loc_X` only, so the body is already emitted in the
caller; these entries are no-ops unless an indirect call reaches the address):

```
"826B37E0" = { end = 0x826B37E8 }   "82744A9C" = { end = 0x82744AA4 }
"82744B08" = { end = 0x82744B10 }   "8277F7BC" = { end = 0x8277F7C4 }
"8277F7C8" = { end = 0x8277F7D0 }   "827B642C" = { end = 0x827B6434 }
"827C03EC" = { end = 0x827C03F4 }   "827C0488" = { end = 0x827C0490 }
"827C0498" = { end = 0x827C04A0 }   "827DA51C" = { end = 0x827DA524 }
"827DA8D8" = { end = 0x827DA8E0 }   "828032DC" = { end = 0x828032E8 }
"82813FF0" = { end = 0x82813FF8 }   "82E45604" = { end = 0x82E4560C }
"82F0E8B0" = { end = 0x82F0E8B8 }   "82F31D2C" = { end = 0x82F31D48 }
"82F31ECC" = { end = 0x82F31EE8 }   "82F321DC" = { end = 0x82F321F8 }
"82F4FF4C" = { end = 0x82F4FF54 }   "82F4FF7C" = { end = 0x82F4FF84 }
"82FA4938" = { end = 0x82FA4940 }   "82FA4998" = { end = 0x82FA49A0 }
"830125F8" = { end = 0x8301260C }   "830128C8" = { end = 0x830128DC }
"83012A88" = { end = 0x83012A9C }   "83045F68" = { end = 0x83045F7C }
"83058078" = { end = 0x8305808C }   "83058158" = { end = 0x8305816C }
"83061ACC" = { end = 0x83061AE0 }   "830CDD58" = { end = 0x830CDD60 }
"831FCB9C" = { end = 0x831FCBA4 }   "8320F940" = { end = 0x8320F954 }
"8320FBB0" = { end = 0x8320FBC4 }   "83214094" = { end = 0x832140A8 }
"832144AC" = { end = 0x832144C0 }   "8321F038" = { end = 0x8321F040 }
"83220458" = { end = 0x8322046C }   "8322066C" = { end = 0x83220680 }
"8322080C" = { end = 0x83220814 }   "83220F40" = { end = 0x83220F54 }
"83227EB0" = { end = 0x83227EBC }   "83227EBC" = { end = 0x83227EC4 }
"832323C4" = { end = 0x832323D8 }   "832324A0" = { end = 0x832324B4 }
"832326A4" = { end = 0x832326B8 }   "83232860" = { end = 0x83232874 }
"83237760" = { end = 0x83237774 }   "8323F9AC" = { end = 0x8323F9BC }
"8323F9CC" = { end = 0x8323F9E0 }   "83327ACC" = { end = 0x83327AD0 }
"83347230" = { end = 0x83347238 }   "83358288" = { end = 0x83358290 }
"83433410" = { end = 0x83433414 }   "8343341C" = { end = 0x8343342C }
"834334B4" = { end = 0x834334C8 }   "83439DE0" = { end = 0x83439E34 }
"83442534" = { end = 0x8344253C }   "83442588" = { end = 0x83442590 }
"8369E7F4" = { end = 0x8369E7FC }   "836A4C14" = { end = 0x836A4C1C }
"8374B770" = { end = 0x8374B778 }   "837A6BC8" = { end = 0x837A6C18 }
"837AA88C" = { end = 0x837AA8C8 }   "837B72B0" = { end = 0x837B7304 }
"8386C848" = { end = 0x8386C85C }
```

Tier 3 - **do not add as standalone `end` entries** (4; the CFG extent contains a sibling entry, and a
truncated `end` would make real branches point outside the function -> `Unknown` -> `REX_FATAL`):

```
0x82744AF4  extent end 0x82744B60  contains 0x82744B08
0x83358280  extent end 0x8335840C  contains 0x83358288
0x83433404  extent end 0x83433414  contains 0x83433410
0x83439DDC  extent end 0x83439E34  contains 0x83439DE0
```

## Item 4 - not applied (procedure ready, awaits approval)

Nothing was written; the file count and hashes of both override copies are unchanged. When approved:
1. backup per the standing rule (both override copies + SHA-256 + timestamped copy under
   `D:\FWC10\_backups\`);
2. write **both** copies identically: 14 new entries appended to the 266 in
   `fifadllzf_overrides.toml`, and the new `default_overrides.toml`;
3. add `includes = ["config/default_overrides.toml"]` to the `[entrypoint]` heredoc in
   `Installer/BuildWorldCup2010.ps1`;
4. verify SHA-256 equality of both copies;
5. rebuild **once** (record wall time and the codegen console log); verify
   * each of the 14 `DEFINE_REX_FUNC(sub_XXXX)` bodies is non-empty,
   * fifadllzf codegen: `cannot seal (0 unresolved)` **82 -> 68** and `sealed 86,551 -> 86,565**
     (predicted; the default run 1 -> 0), or report the actual numbers instead,
   * the registered-function count rises by 14 (+1 default),
6. boot and report whether the AV changes (same address / new address / none).

**Honest expectation, stated before the run:** item 2 of Round 13 showed no stub writes `+0x64`, and
only 14 of the 83 are reached as calls, so this change is **unlikely to remove the `+0x64` AV by
itself**. What it can do is delete a class of silent no-ops (real call sites that currently return
immediately) and thereby change what the game does before the AV - which is itself a useful result.
Verified vs inferred will be reported as always.

## ICF / inlining - evidence for the "a no-hit would not exonerate" objection (VERIFIED)

`DEFINE_REX_FUNC` marks every generated function `noinline` (`codegen_pch_h.inja.h`), so the stubs are
not inlined. The stub bodies are byte-identical empties (`{ REX_FUNC_PROLOGUE(); }`, and the prologue
expands to nothing in this build), which *would* make them ICF candidates, so it was measured in the
shipped binary: every stubbed function's `PPCFuncMappings` host pointer sampled (14 Tier-1 + 10
siblings/nearby = 24 addresses) is **distinct**; **no two share a host address**, including the two
empty twins `0x82744AF4` (`0x181185800`) and `0x82744B08` (`0x18112D770`) and both conflicting sibling
pairs. So this build did **not** fold these stubs, and a per-stub execute breakpoint would be
specific (if it were run - it is not). Scope: 24 of 83 sampled; it says nothing about ICF elsewhere in
the binary.

---

# Round 15 (2026-10-17) - Tier-1 no-block stub bodies applied, one rebuild, one boot

**Status: DONE. The change works exactly as recorded; the `+0x64` AV is unchanged.**

Approval (verbatim conditions): tier 1 (the 14 called stubs) + default-module plumbing, under the
Round-14 recorded procedure; (1) reconcile the expected counts first - tier 1 is 13 fifadllzf + 1
default, so "cannot seal" is **82 -> 69** (not 68) and sealed **86,551 -> 86,564** (not 86,565);
state the corrected numbers and the default module's own counts before building; (2) back up
`BuildWorldCup2010.ps1` and the manifest template along with both override copies (timestamped,
SHA-256); (3) tiers 2 and 3 stay out. After the rebuild: verify the 14 bodies are non-empty, verify
the counts, boot once, compare against the last boot log, report whether the AV changes or anything
crashes earlier, stop if a new earlier crash appears. Time-box the build. Verified vs inferred.

## Item 0 - count reconciliation before the build (user's correction was right)

Measured baselines (from the UTF-16 `codegen_console.log` of the combined two-module run):

| Module | baseline "sealed" | baseline "could not seal" | expected now |
|---|---|---|---|
| `default` (entrypoint) | 4,727 | 1 | **4,728 / 0** |
| `fifadllzf_xex` | 86,550 in that run (**86,551** in the stage-6 run whose output is the tree we analysed) | 82 | **86,564 / 69** |
| total | - | 83 no-block stubs | **83 -> 69 no-block stubs** |

The user's correction is right and mine was wrong: 82 - 13 = 69 (I had subtracted 14, wrongly counting
the default module's stub against the fifadllzf counter). The default module's stub was never in
those numbers; it has its own counter (1 -> 0).

**Correction to the Round-14 plan (my error):** the *registered* count does **not** rise. All 14 were
already registered functions - that is exactly how their `PPCFuncMappings` host pointers could be read
in Round 14. The override gives an existing registered function a body. So the count that moves is
"no blocks"/"cannot seal", never the registry; "registered count +14/+1" is withdrawn.

## Item 1 - backup (before any write)

`D:\FWC10\_backups\20261017-183737\` (`SHA256SUMS.txt` inside, `LAST_BACKUP.txt` updated):

| file | SHA-256 |
|---|---|
| `fifadllzf_overrides.template.toml` | `FFB03BFC9CF50E0932E8A1FDA40CC8D1950E9063A26C81329A05430D62A7787D` |
| `fifadllzf_overrides.workspace.toml` | `FFB03BFC...A7787D` (identical) |
| `BuildWorldCup2010.ps1` | `15DFEFCC170438466B904281D6192A52CCF9C1978F23B28153A55D652896C477` |
| `worldcup2010_manifest.template.toml` | `CDFCB992BB54CEE7A7D8DDA39FC4329C85377E7557346A5A93464DAE85DCCA0C` |
| `worldcup2010_manifest.workspace.toml` | `F7C986AA343A9B8C288B30034216D836F6E06C76F9CA69AD33393BE104697CFB` |
| pre-build `worldcup2010.exe` | `0E390E38972174695E61D74296B4396A32051E96815785628774BBC68270F66A` |
| pre-build `worldcup2010_fifadllzf.dll` | `9B7E64F38B3AC9DE3585101CE3CD51462A6ED4323315A9E8360CDE02415002A7` |

The template and workspace override copies were byte-identical before the change (same SHA-256), and
they are byte-identical after it - the two destinations are filled from one staged file, so identity
is by construction.

## Item 2 - the change (tiers 2 and 3 untouched)

- `config/fifadllzf_overrides.toml`: 13 entries appended (266 -> **279 entries**), LF endings
  preserved, comments mark the batch and record why tiers 2/3 are excluded. Both copies:
  SHA-256 `6D8797AEAD31BD75E3D6681F83DB9785C32DF1A4BF95D0F7FC9573E3BA1D9CE5` (12,877 bytes).
- `config/default_overrides.toml`: **new in both config dirs**, one entry
  (`"8211A170" = { end = 0x8211A178 }`), same header/schema documentation style as the fifadllzf file.
  SHA-256 `8086CBB503C9D61B44650D04B7A20BD64E358DDFD8F50E338A6D999F9C5EFFFE` (868 bytes).
- `Installer/BuildWorldCup2010.ps1` line 151: `[entrypoint]` `includes = []` ->
  `includes = ["config/default_overrides.toml"]` (only that hunk changed; PowerShell parser reports
  0 errors). New SHA-256 `701689E41D8C53067C370F03DCC8F83FF6345F7D629A0C50F5A04118E01003C6`.
- The build script copies `recomp-template\*` over the workspace with `-Force` (line ~122), so the
  template copy is authoritative and its `config\` lands in the workspace before codegen runs.

## Item 3 - the rebuild (one, time-boxed 45 min; actual 860 s)

Recorded command, unmodified; exit code 0. Wall **860 s (14.3 min)**: codegen `done default.xex
(381.0s)`, `done fifadllzf.xex (394.8s)`, `Done in 395.5s`; then compile + link.

Ninja recompiled exactly the expected translation units and nothing else meaningful:

```
worldcup2010_fifadllzf.dll : recomp.{0,3,38,74,128,133,155,207,209,238,275,299,311}.cpp   (13)
worldcup2010.exe           : generated/default/worldcup2010_recomp.5.cpp                  (1)
+ Linking CXX shared library worldcup2010_fifadllzf.dll
+ Linking CXX executable worldcup2010.exe
```

Those 14 files are precisely the files holding the 14 Tier-1 functions (e.g. `0x82DA6148` is in
`recomp.3.cpp`, `0x83704A30` in `recomp.155.cpp`, `0x8211A170` in `default/recomp.5.cpp`).

**Anomaly, recorded not explained:** the run's own summary line reads `Codegen summary: 0 written,
706 unchanged, 0 deleted, 0 module(s) up to date`, while the generated content demonstrably changed
(next item) and 14 TUs were recompiled. In earlier runs the same line read `706 written, 0 unchanged`.
The counters do not reflect reality and are not used as evidence anywhere below; the marker counts
are.

Post-build binaries changed: `worldcup2010.exe` `5492C6A5C9503C1F262F6CA51A207E7573BF03B1802B562872A7AA7A88800BAB`,
`worldcup2010_fifadllzf.dll` `2BE449A13BC927D2E28D79E2CD220007F2FC4CD185C4A64CA5E4BC464D7ECDBD`
(written 18:52-18:53).

## Item 4 - verification (all of the user's checks)

**1. The 14 bodies are non-empty (VERIFIED).** All 14 `DEFINE_REX_FUNC` bodies now carry real
instructions; all 14 are absent from the no-block set:

| address | module / file | instructions |
|---|---|---|
| `0x82A63768` | fifadllzf `recomp.133.cpp` | 5 |
| `0x82ADF698` | fifadllzf `recomp.311.cpp` | 6 |
| `0x82ADF6B0` | fifadllzf `recomp.209.cpp` | 6 |
| `0x82BCBDB8` | fifadllzf `recomp.238.cpp` | 5 |
| `0x82DA6148` | fifadllzf `recomp.3.cpp` | 3 |
| `0x831A11B8` | fifadllzf `recomp.0.cpp` | 2 |
| `0x83232D58` | fifadllzf `recomp.128.cpp` | 5 |
| `0x8323FB38` | fifadllzf `recomp.275.cpp` | 4 |
| `0x8323FB6C` | fifadllzf `recomp.74.cpp` | 4 |
| `0x8323FB8C` | fifadllzf `recomp.38.cpp` | 5 |
| `0x837045C0` | fifadllzf `recomp.207.cpp` | 3 |
| `0x83704A30` | fifadllzf `recomp.155.cpp` | 1 |
| `0x8375B9D0` | fifadllzf `recomp.299.cpp` | 1 |
| `0x8211A170` | default `recomp.5.cpp` | 2 |

**2. The counts (VERIFIED at warning level, the level common to all build-script runs).** In the build
script's own transcript `build.log.native`: the previous full two-module codegen run logged **83**
`has no blocks - generating stub` warnings; this run logged **69**. The set difference is *exactly* the
14 Tier-1 addresses, with **0 added** (computed address-by-address, not by count alone). The generated
tree now contains **69** `// STUB: Function at` markers = the 65 Tier-2 + 4 Tier-3, and none of the 14.
This is the same quantity the debug-level `cannot seal` counter reports (in the Oct-16 debug run: 83
`has no blocks` and 83 `cannot seal`, identical sets), so fifadllzf "cannot seal" went **82 -> 69** and
the default module's went **1 -> 0** - the user's corrected prediction.

**3. The registered count did not rise** - as explained in item 0; the 14 were registered all along.

**4. The tail-`b` prediction is confirmed (VERIFIED).** The Round-14 prediction was that a conditional
or unconditional tail `b` into another function is emitted as `sub_X(ctx, base); return;`, which is
exactly why the empty stub silently skipped its target. Two of the applied bodies:

```cpp
DEFINE_REX_FUNC(sub_83704A30) {          DEFINE_REX_FUNC(sub_8211A170) {
	REX_FUNC_PROLOGUE();                     REX_FUNC_PROLOGUE();
	// b 0x8375c040                          // addi r3,r3,8
	sub_8375C040(ctx, base);                 ctx.r3.s64 = ctx.r3.s64 + 8;
	return;                                  // b 0x82118ab8
}                                            sub_82118AB8(ctx, base);
                                             return;
                                         }
```

**5. The run's own `sealed ... could not seal` summary was NOT emitted this run** (the new run wrote
71 warning-level lines and no debug lines, so the debug-only counter is absent from its log). The
figures **86,564 / 4,728 sealed are therefore INFERRED** by the same +13/+1 arithmetic, using the
verified no-block drop as the anchor; they are not directly observed. Everything else in this item is
measured.

## Item 5 - one boot, compared against the previous boots

Boot 18:55:13 (`--log_level=debug`, fresh log `boot_round14_runtime.log`), process exited by itself
after ~4.4 s.

- **One AV: `18:55:17.029 [error] [sys] Unhandled guest access violation: read of guest 0x0006C6B8
  (host 0x000000010006C6B8) on thread 0xF8000350`** - the *same guest address, same host address,
  same fault class* as every previous run. Immediately preceded, as always, by
  `SetThreadName(35, rw45_pkg_factory_seg)`.
- **Nothing crashes earlier, nothing new crashes.** No `REX_FATAL`, no "unregistered function", no
  error or warning before the AV that the baselines do not also have.
- Work done before the AV: 687 logged lines (baselines 722 and 767) and 165 distinct message
  templates (baseline 164). The entire delta is per-run identities (handle numbers `F80003xx`,
  native thread ids) plus the count of timing-dependent `apu XMA: Write to unknown register` debug
  lines; `Creating graphics pipeline` appears in all runs (7-93 times depending on shader-cache
  timing). **No behavioural difference.**
- Both baseline logs used for the comparison are single runs extracted from `boot_item1b_runtime.log`
  (first run, 15:27) and `boot_item3_runtime.log` (first run, 16:49).

**Conclusion.** The Tier-1 body fix is applied, verified and repeatable, and it changes **nothing**
observable about the crash: `singleton+0x64` is still null at the read in `sub_82CBD7E0`. This
matches the honest expectation stated before the run. The remaining 69 no-block stubs are the
`goto`-only set (harmless) and the 4 conflicting extents, so **this line of work is exhausted**; the
next discriminating experiments are the ones already listed as Round 14/15 next moves (throttle
inverted, callers/data references of `sub_82BDB2F8`, resolving the 12 `bctr` sites).

## Files changed in Round 15

| File | Change | SHA-256 after |
|---|---|---|
| `Installer/recomp-template/config/fifadllzf_overrides.toml` | +13 entries (266 -> 279) | `6D8797AE...D9CE5` |
| `C:\FWC10B\fwc10stage4\WorldCup2010Rex\config\fifadllzf_overrides.toml` | same bytes | `6D8797AE...D9CE5` |
| `Installer/recomp-template/config/default_overrides.toml` | new, 1 entry | `8086CBB5...EFFFE` |
| `C:\FWC10B\fwc10stage4\WorldCup2010Rex\config\default_overrides.toml` | new, same bytes | `8086CBB5...EFFFE` |
| `Installer/BuildWorldCup2010.ps1` | `[entrypoint] includes` (1 hunk) | `701689E4...003C6` |

Backup of all of them (plus both manifests): `D:\FWC10\_backups\20261017-183737\`.

---

## Files Intentionally Unchanged

| File | Reason |
|---|---|
| `Installer/recomp-template/config/verify_ctr_region.py` | FIFA Street addresses; not called by build |
| `Installer/recomp-template/config/verify_allocation_region.py` | FIFA Street addresses; not called by build |
| `Installer/recomp-template/config/fifadllzf_overrides.toml` | **Now holds 279 entries** (Stage 6 + 6b-6d + Round-15 Tier 1); SHA-256 `6D8797AE...` identical in both copies |
| `Installer/recomp-template/src/native_libc_hooks.cpp` | `#if 0`; no confirmed addresses for this binary |
| Generated `.cpp` files | Never edit generated files |

---

# Round 16 - Xenia guest-address breakpoint capability; FEThread kernel-call comparison; `sub_82BDB2F8` references; the 12 `bctrl` sites

**Box:** user's 60-minute box for items 1-2, 30 minutes each for 3a/3b. **No rebuild** (no codegen
wall time to report), **no override change**, **nothing launched** (neither the original Xenia nor
a copy), `D:\FWC10\xenia` untouched, no new data staged. Every claim below is marked
**VERIFIED** (read out of a file/byte-level artifact this round) or **INFERRED**.

Tools: `round16_fethread.py`, `round16_kernelclass.py`, `round16_item3.py`, `round16_faultwin.py`,
`xenia_dbg_caps.py` + `round16_*_out.txt` (all in `%TEMP%\opencode`).

## Item 1 - Can Xenia Canary (on a copy) break on a guest address? YES

**VERIFIED** from the shipped config + binary strings (nothing executed):

* `[CPU]` of `xenia-canary.config.toml` (lines 19-28) has exactly this facility:
  * `break_on_instruction = 0` - comment: *"int3 before the given guest address is executed"*,
  * conditional filter: `break_condition_gpr = -1`, `break_condition_op = "eq"`,
  `break_condition_value = 0`, `break_condition_truncate = true`,
  * `break_on_start = false` (*"Break into the debugger on startup"*), `break_on_debugbreak`,
  `break_on_unimplemented_instructions`.
* The exe contains an **integrated guest debugger** (host-side, at PPC guest addresses - not the
  guest xbdm path): `xe::debug::ui::DebugWindow`, `.?AVDebugWindow@ui@debug@xe@@`,
  `X64Backend::InstallBreakpoint`, `Processor::StepIntoGuestBranchTarget`, `ThreadDebugInfo`,
  `Xenia Debugger`, `Debugger Loaded`, `&Break and Show Guest Debugger`, `&Break into Host Debugger`,
  `Add a code breakpoint for either PPC or x64.`, `##breakpoints_pane`, `##add_code_breakpoint`,
  `##add_data_breakpoint`, `##add_kernel_breakpoint`, `##add_gpu_breakpoint`,
  `Remove breakpoint at this address.`, `Clear all breakpoints.`, `Toggle all breakpoints.`,
  `Guest attempted to trigger a breakpoint!`, `Breaking into debugger because of --break_on_start...`,
  `Disabling --debug due to lack of stack walker`, `You need a debugger attached or this will crash!`.
* `C:\Windows\System32\dbghelp.dll` exports everything the stack-walker check needs
  (`StackWalk64`, `SymInitialize`, `SymFromAddr`, `SymLoadModuleEx`, `SymCleanup`,
  `MiniDumpWriteDump`) - so the *"Disabling --debug due to lack of stack walker"* path is
  **INFERRED** not to trigger here (the loader check itself is not verified without launching).

**Exact steps (prepared, NOT run - waiting for the user's OK):**

1. Copy the whole install to a work dir, e.g. `C:\FWC10B\xenia_dbg` (the original stays read-only).
2. Edit the **copy's** `xenia-canary.config.toml`, `[CPU]`: `break_on_instruction = 2194397196`
   (= 0x82CBD80C; TOML also accepts the literal `0x82CBD80C`). Optionally `[General] debug = true`.
3. Launch the copy: `xenia_canary.exe "D:\FWC10\2010 World Cup.iso" --debug` with
   cwd = the copy's dir (so cache/content stay in the copy). `--break_on_instruction=0x82CBD80C`
   can be passed on the command line instead of editing the file.
4. Read the "Xenia Debugger" window at the break: registers `r3`, `r11`; memory pane at `r3+0x64`
   (and, per item 3b, at `r3+0x6C6B8`). The breakpoint pane is the equivalent GUI route
   ("Add a code breakpoint for either PPC or x64" -> `0x82CBD80C`).
5. Decisive variant - break only in the *failing* case:
   `--break_condition_gpr=3 --break_condition_op=eq --break_condition_value=0`.
   If Xenia **never** breaks with that condition but does without it, then Xenia reaches the
   instruction with **r3 != 0** - the direct answer to the question asked.
6. Caveat: `break_on_instruction` alone (without `--debug`) sends the int3 to the *host* debugger;
   with none attached the exe's own string says *"You need a debugger attached or this will crash!"*.
   Use `--debug` (the integrated window **is** the debugger).

## Item 2 - FEThread (guest 26) kernel-call sequence, Xenia level-3 vs ours

**Alignment (VERIFIED).** Xenia's log id column is the **guest thread handle**, not a native tid.
The FEThread is the thread that owns guest id 26 (`SetThreadName(26, FEThread)`, line 15577, logged
by handle `F8000008` = main) **and** creates/names/resumes worker 35: handle **`F8000330`**
(`XThread::Execute thid 26 (handle=F8000330, 'FEThread', native=00004DAC)` line 15590; then
`ExCreateThread(..., 40103E40, 1)` 17876, `SetThreadName(35, rw45_pkg_factory_seg)` 17881,
`NtResumeThread(F80003BC, 708EF040(00000000))` 17888). Ours is host thread **`t12808`** - the
thread that logs `SetThreadName(35, rw45_pkg_factory_seg)` (line 687) and then the AV (line 688).

**Sizes:** Xenia FEThread = **862** log lines (15590-196197). Ours = **2** lines. **Our log is not a
kernel-call trace.**

**What our runtime logs / does not log (VERIFIED).** 764 parsed rows, 153 distinct templates, tags
`apu 552, krnl 93, core 44, sys 40, fs 19, gpu 16`. It logs: `SetThreadName`; XAM calls that carry
their own log statement (`XamNotifyCreateListener`, `XamContentCreateEnumerator`, ...); module load
and procedure lookups (the port's `FIFA TRACE` lines, at *error* level); `NtCreateFile`
**failures only**; stub hits; and `XThread::Execute` **only for runtime-created threads**
(Kernel Dispatch, XMA Decoder, Audio Worker, GPU Commands, GPU VSync - all with the `<host>`
suffix), never for guest-created ones. It does **not** log kernel entry points otherwise:
`KeTlsSetValue`, `ObReferenceObjectByHandle`, `ObDereferenceObject`, `ExCreateThread`,
`NtResumeThread`, `KeSetBasePriorityThread`, `KeSetAffinityThread`,
`RtlInitializeCriticalSection`, `KeQuerySystemTime`, `NtCreateSemaphore`, `RtlInitAnsiString`,
`RtlRaiseException`, successful `NtCreateFile`. A source classifier over the 56 kernel files
(`src/kernel/**`) found each of those is a real `REX_EXPORT` implementation with **no log call in
the function**. So their absence from our log is **not** evidence they did not run.

**Our stubs are not silent (VERIFIED, `ReXGlue\include\rex\hook.h:52-56, 76-78`):**
`REX_EXPORT_STUB(n)` -> `REX_STUB(n)` -> `REXKRNL_WARN("{} STUB", #n)`. Whole run: **exactly one**
stub hit, `__imp__XUsbcamGetState STUB - returning 0x0`. So a call to any registered stub
(including every `XamBackgroundDownload*`) **would** appear as a warning.

**First divergence: none at kernel-call level, because the two logs are not comparable.** At the
level of signals **both** runtimes log there is **no divergence at all up to and including the
naming of worker 35**:

| signal | Xenia | ours | verdict |
|---|---|---|---|
| `SetThreadName` | 24 entries | 22 entries | **Xenia's first 22 are exactly ours** - same guests, same names, same order; extras are guests 36/38 `MoviePlayer2 Decode Thread`, after our crash point |
| `XexLoadImage` | `fifadllzf.xex` then `xam.xex`, flags 9, min_version 0 | same two, same flags | identical |
| `XexGetProcedureAddress` | ordinals `0xAFF, 0xB00, 0xB0B, 0xB10, 0x305, 0x30B` (then 1 for fifadllzf) | `0xAFF, 0xB00, 0xB0B, 0xB10, 0x305, 0x30B`, then 1 | **identical order**; only the resolved values differ (ours = the port's thunk block, e.g. `0x838D8DB4`; Xenia = its `0x80050000+` import thunks) |
| `XamNotifyCreateListener` | masks `1,1,0xEF,1,0x80,1,0x20,2,3,1,2` | same sequence (+ returned handle) | identical |
| file probes | every path our run reports as `NtCreateFile FAILED` is probed by Xenia too | 15 paths | **same probe set (VERIFIED)**; same *result* is INFERRED (Xenia logs attempts with args, ours only failures) |

So the **first observable divergence is the fault itself**: ~1 ms after `SetThreadName(35, ...)` our
FEThread takes the read of guest `0x6C6B8` and dies, while Xenia's FEThread continues with the
worker setup `ObReferenceObjectByHandle(F80003BC) -> KeSetBasePriorityThread(301E5010, 1) ->
ObDereferenceObject -> ObReferenceObjectByHandle -> KeSetAffinityThread(301E5010, 0x10,
out=83AEA830) -> ObDereferenceObject -> NtResumeThread(F80003BC, out=00000000)` and then a long loop
(784 x `NetDll_XNetGetTitleXnAddr`, 16 x `RtlInitializeCriticalSection`, 12 x `NtCreateSemaphore`,
11 x `KeQuerySystemTime`). **Whether our run performed that same setup before faulting cannot be
decided from the logs** (we do not log those calls) - it is exactly what item 1's breakpoint would
settle.

**Correction - `XamBackgroundDownloadSetMode`.** It appears **once** in Xenia's log, line 11432:
`F 82300590 838D7E8C 9C4 (2500) !! XamBackgroundDownloadSetMode`. That is a row of the
**`fifadllzf.xex` import-table dump**, and `!!` is Xenia's marker for an **unimplemented import on
Xenia's side too** - it is **not a call** in Xenia's log. Our run has **0** occurrences, and ours
registers it (`src/kernel/xam/xam_misc.cpp:303-318`, all `REX_EXPORT_STUB`), so a call would have
logged `XamBackgroundDownloadSetMode STUB`. Therefore the guest calls it in **neither** runtime
(VERIFIED via the logging-stub rule + zero occurrences). Xenia's `!!` rows total ~33 unimplemented
imports across both modules (INFERRED from the dump) - useful, because whatever Xenia leaves
unimplemented cannot explain why Xenia gets further.

## Item 3a - `sub_82BDB2F8`: every reference

**Body (VERIFIED from the image):** `0x82BDB2F8  stw r4, 100(r3)` / `0x82BDB2FC  blr` - a bare
field setter `obj->[0x64] = r4`.

* **Direct callers: 0.** Every exec section of `default.dec.bin` and `fifadllzf.dec.bin` scanned for
  `b`/`bl` targeting that address: none. Generated recompiled sources: **0** call sites.
* **Data references: exactly 1 (VERIFIED).** `.rdata` **`0x8241690C`**, which is **index 17** of a
  31-word run `0x824168C8..0x82416944` (`.rdata`) in which **31/31 words resolve inside the image**
  and all point into `.text`: a **function-pointer table**.
* **The table is an accessor/dispatch table of member getter/setter pairs (VERIFIED, decoded):**
  `[16] 0x832BF128 = lwz r3, 100(r3)` (get `+0x64`) is immediately followed by
  `[17] 0x82BDB2F8 = stw r4, 100(r3)` (set `+0x64`); `[18] 0x832BF140 = lwz r3, 104(r3)` /
  `[19] 0x82BDB300 = stw r4, 104(r3)` (get/set `+0x68`); also `[20] 0x8365C350 = lwz r3, 92(r3)`,
  `[21] 0x82BDB308 = lbz r3, 96(r3)`, `[24] 0x82B06560 = blr`. Entries `[0-7, 11-13, 22, 23, 25-28,
  30]` are AltiVec-prologue functions (`mfspr r12, spr256` = VRSAVE).
* **Consequence (VERIFIED):** `sub_832BF128` - the exact function in our fault chain that executes
  `*(r3+0x64)` - **is table index 16**, and the setter for that same field **is index 17**. The read
  that returns 0 in our run is therefore a **table-driven accessor call**, and the matching setter is
  a table entry, not a directly-called function.
* **INFERRED:** the setter's guest address *is* an intended indirect target (it is reachable only via
  this table). However the table has **0 `lis`+`addi` materialisation sites** anywhere in either
  image, so it is reached indirectly (via another pointer/table or a computed base) - **not resolved
  this round**. This is consistent with the earlier write-history finding: `+0x64` is ever only
  written 0 (memset-zero, memset-poison `0xCDCDCDCD`, ctor) and never a valid pointer.

## Item 3b - the 12 `bctrl` sites in `sub_82CBD7E0`, resolved through their pointer tables

All 12 are `mtctr rX; bctrl`, i.e. **indirect dispatch**; 11 of them are the classic
`lwz r11, 0(r3)` (object vtable) + `lwz r11, <slot>(r11)` + `mtctr r11` + `bctrl` sequence. So the
"guest pointer table" for each site is the **vtable of the object in `r3`** - a per-object runtime
table, not a static image table:

| site | table it dispatches from | slot |
|---|---|---|
| `0x82CBD874` | `*(r3)` vtable | `+4` |
| `0x82CBD890` | `*(r3)` vtable | `+4` |
| `0x82CBD8A0` | `*(r3)` vtable | `+16` |
| `0x82CBD9AC` | `*(r3)` vtable | `+0` |
| `0x82CBD9C0` | `*(r3)` vtable | `+12` |
| `0x82CBDAD4` | `*(r31+8)` (frame object; not written in the preceding 120 insns) | - |
| `0x82CBDB78` | `*(r31+0xAC)` then `*(+0x8C)` (two-level) | - |
| `0x82CBDBB4` | `*(r3)` vtable | `+4` |
| `0x82CBDBD0` | `*(r3)` vtable | `+4` |
| `0x82CBDBE0` | `*(r3)` vtable | `+16` |
| `0x82CBDC00` | `*(r3)` vtable | `+4` |
| `0x82CBDC1C` | `*(r3)` vtable | `+12` |

**Entry correction (VERIFIED):** the function entry **is** `0x82CBD7E0` -
`SetFunction(0x82CBD7E0, sub_82CBD7E0)` in `worldcup2010_register.cpp:34925`,
`{ 0x82CBD7E0, sub_82CBD7E0 }` in `worldcup2010_init.cpp:34936`, body in
`worldcup2010_recomp.322.cpp:12356`. So the AV instruction `0x82CBD80C` is at **+0x2C**, not
"+0x236", and **0** indirect calls exist in `0x82CBD5D6..0x82CBD80C`. **The crash is straight-line
code in the function's entry block; none of the 12 indirect calls lies on the failing path.**

**Fault window (VERIFIED, disassembled from the image, big-endian):**

```
0x82CBD7E0  mfspr r12, spr256        ; AltiVec VRSAVE prologue
0x82CBD7E4  bl 0x828328DC            ; VMX save helper (called before the frame)
0x82CBD7E8  stwu r1, -144(r1)
0x82CBD7EC  mr r31, r3               ; r31 = this
0x82CBD7F0  bl 0x82C501D0            ; r3 = *(0x83A4648C)     <- global getter
0x82CBD7F4  bl 0x832BF128            ; r3 = *(r3 + 0x64)      <- accessor table index 16
0x82CBD7F8  lis r11, 0x0006
0x82CBD7FC  lbz r10, 19(r31)
0x82CBD800  addi r29, r0, 0
0x82CBD804  ori r11, r11, 0xC6B8     ; r11 = 0x0006C6B8
0x82CBD808  cmpli cr0, 0, r10, 0
0x82CBD80C  lwzx r28, r3, r11        ; <== AV: reads *(r3 + 0x6C6B8); r3 = 0
0x82CBD810  bc -> 0x82CBD820
0x82CBD814  mr r3, r31
0x82CBD818  bl 0x82CBC610
0x82CBD81C  stb r?, 19(r31)
0x82CBD820  lwz r11, 4(r31)          ; state counter
0x82CBD840  mtctr r11                ; computed dispatch on *(this+4)
```

So the faulting statement is a **plain member read** `r28 = *(accessor_16(this) + 0x6C6B8)` where
`accessor_16(this) = *(*(0x83A4648C) + 0x64)` returned 0 - the most precise picture of the fault so
far, and it confirms the two-call chain plus the `0x6C6B8` offset exactly.

## Item 4 - reworded

The claim at the Round-13 section ("Xenia's thread 35 runs **past** the exact point where ours
faults") now carries a **ROUND 16 CORRECTION** note in place: it is **INFERRED from the ordering of
kernel calls in a level-3 log, NOT VERIFIED** for the instruction itself, and this round measured
the matching limitation on our side (no kernel-entry logging), so neither log can decide whether
`0x82CBD80C` executes in Xenia or what `r3`/`*(r3+0x64)` are there.

## Open / next

1. Item 1's breakpoint is prepared; **awaiting the user's OK** to copy the install and launch the
   copy with `--debug --break_on_instruction=0x82CBD80C` (and the `r3 == 0` condition variant).
2. Item 3a leftover: how `0x824168C8` (0 materialisation sites) is reached - pointer-flow walk or a
   runtime watch on the table slot.
3. Nothing else was changed; no codegen time consumed this round.

---

# Round 17 - the Xenia breakpoint check, executed (approved): Xenia *does* execute `0x82CBD80C`, and its `r3` there is non-zero

**One line.** With `break_on_instruction` on the guest address we fault on, Xenia breaks ~46-50
times per second; adding the condition `r3 == 0` to the *same* breakpoint suppresses **every** hit
while the run stays otherwise identical - so Xenia reaches that instruction with a **non-zero `r3`**,
i.e. the pointer our build reads as `0` is valid there. The divergence is before this instruction and
is a value difference, not a null-tolerant read.

Status: COMPLETE (3 runs, ~4 min of emulator time, well inside the 45 min box). Nothing was rebuilt,
no override changed, no game data re-staged, our runtime untouched, no GUI used in these runs.

## Scope as approved
- Work only on a copy; verify the original afterwards (sizes **and** timestamps).
- Run A: `break_on_instruction = 2194397196` (`0x82CBD80C`), **no** condition.
- Run B: same breakpoint plus `--break_condition_gpr=3 --break_condition_op=eq
  --break_condition_value=0`. Report whether it triggers.
- Attach our own debugger so no GUI interaction is needed. Do **not** read guest registers out of the
  host `CONTEXT` (not verified how Xenia stores them).
- Say clearly whether the breakpoint can be missed. Report verified vs inferred. Update this file with
  the A/B outcome table.

## Setup (everything inside the copy)
- `robocopy D:\FWC10\xenia C:\FWC10B\xenia_dbg /E` - 17 files / 38,778,717 bytes, byte-identical on
  both sides. `D:\FWC10\xenia` was never written to.
- The copy's `xenia-canary.config.toml` was patched with 8 anchored single replacements:
  `break_on_instruction 0 -> 2194397196`; `break_on_debugbreak true -> false`;
  `break_on_unimplemented_instructions true -> false`; `[General] debug false -> true`;
  `log_to_stdout true -> false`; `storage_root` / `cache_root` / `content_root` -> the copy's own
  directories, so nothing could fall back into the read-only install.
  **Xenia rewrote this file itself during run C** (mtime 18:36:25, back to 65,968 bytes / 548 lines);
  a diff against the original shows exactly those 8 lines, all values still in place, and the copy
  config's SHA-256 is now `FAA02515...` (original `A576FB7C...`, untouched).
- The copy's `cache_host\` was renamed to `cache_host_orig\` before run A so no pre-existing artifact
  took part. The runs wrote only `cache\modules\<hash>\executable_addr_flags.bin` (19.4 MB + 1.2 MB)
  and `cache\shaders\shareable\*` **inside the copy**. Run C - which ran *after* A and B, with all of
  that present - still fired the breakpoint, so **no cached artifact can suppress the break**
  (VERIFIED, and this was one of the two miss mechanisms to rule out).
- `C:\Users\<user>\AppData\Local\Temp\opencode\round17_dbglaunch2.py` (SHA-256 `14BC4BAD...`) launches
  the copy with `DEBUG_ONLY_THIS_PROCESS`, consumes every debug event, and reports
  `EXCEPTION_BREAKPOINT`s whose RIP is **not** in a `MEM_IMAGE` region. Xenia's x64 code cache is a
  `MEM_MAPPED` RWX region around `0xA0xxxxxx`, **not** `MEM_PRIVATE`, so "not MEM_IMAGE" is the JIT
  test; the loader's own breakpoint (RIP in `ntdll.dll`) is reported separately and never counted.
  On the first JIT hit the tool samples the guest log, to place the hit against guest milestones.
  Guest registers were **not** read from the host `CONTEXT`.
- Every run: `"<copy>\xenia_canary.exe" "D:\FWC10\2010 World Cup.iso" --log_file=<copy>\run_X.log
  --log_level=3`, cwd = the copy, killed at its own deadline. No `--debug`, so no window.

## Table of outcomes (the A/B table)

| Run | deadline | `break_on_instruction` | break condition | JIT int3 hits | first hit | host address |
|-----|----------|------------------------|-----------------|---------------|-----------|--------------|
| **A** | 100 s | `0x82CBD80C` (2194397196) | none (`break_condition_gpr = -1`) | **5,029** (last 99.99 s, ~50/s) | **15.37 s** | `0xA0DD42F4` |
| **B** | 80 s | `0x82CBD80C` (2194397196) | `r3 == 0` (`--break_condition_gpr=3 --break_condition_op=eq --break_condition_value=0`) | **0** | - | - |
| **C** (control, added this round) | 80 s | `0x82CBD80C` (2194397196) | none | **3,674** (last 79.99 s, ~46/s) | **16.87 s** | `0xA0DCC674` |

Run C was added because A and B are not a clean pair on their own (A ran 100 s and logged ~6x more
audio lines per second), so B needed its own same-setup control. The host address differs per run
(fresh JIT code cache) - like tids, it must not be compared across runs.

Guest-log comparison (all three: favourite level 3, `debug = true`, same ISO, same copy):

| signal | A (100 s) | B (80 s) | C (80 s) |
|--------|-----------|----------|----------|
| `run_X.log` bytes / lines | 32,362,358 / 550,663 | 14,023,414 / 240,247 | 14,080,202 / 240,908 |
| `SetThreadName(35` | 1 | 1 | 1 |
| `rw45_pkg_factory_seg` | 2 | 2 | 2 |
| `XThread::Execute thid 26` / `thid 35` | 1 / 1 | 1 / 1 | 1 / 1 |
| `RtlInitializeCriticalSection` (fixed boot marker) | 865 | 865 | 865 |
| `ObReferenceObjectByHandle` | 20,941 | 6,899 | 6,959 |
| `NtCreateFile` | 68 | 65 | 65 |
| `NetDll_XNetGetTitleXnAddr` | 15,668 | 11,413 | 11,228 |
| `XmaContext` | 73,527 | 8,646 | 9,722 |
| first-chance AVs seen by the debugger | 9,574 (95.7/s) | 7,621 (95.3/s) | 7,730 (96.6/s) |
| exit code | killed at deadline | killed at deadline | killed at deadline |

**B and C match**: 0.4% apart on log size, 0.5% on line count, *exactly* on the fixed boot marker
(865), and ~1% on the per-frame XNet poll - the guest did the same work in both. A is the outlier
(20 s longer, ~6x the audio logging rate) but its int3 *rate* matches C's, i.e. the same code ran,
just for longer.

## Findings

VERIFIED (measured in these runs)
1. `break_on_instruction = 0x82CBD80C`, with every other int3 source disabled
   (`break_on_debugbreak = false`, `break_on_unimplemented_instructions = false`,
   `break_on_start = false`), makes Xenia raise `EXCEPTION_BREAKPOINT` in JIT (`MEM_MAPPED` RWX) code
   **5,029 times in 100 s (A)** and **3,674 times in 80 s (C)**, first at 15.37 s / 16.87 s, then
   steadily ~46-50/s to the end, always on one host thread. No other int3 source was enabled, so
   these are the tagged guest instruction being reached and executed.
2. Run B - the *same* breakpoint plus `r3 == 0` - fires **zero** times in 80 s, in a run whose guest
   log is the same size and shape as control C's. The condition was the only difference, so the
   suppression is the comparison itself: **at every execution of `0x82CBD80C`, Xenia's `r3` is
   non-zero.**
3. In run C the guest log **already contains `SetThreadName(35, ...)`, `rw45_pkg_factory_seg` (x2)
   and `XThread::Execute thid 35`** at the instant of the first hit (log sampled then: 710,386 bytes
   / 11,125 lines). Xenia's FEThread therefore reaches `0x82CBD80C` within a fraction of a second
   after naming worker 35 - the same relationship our runtime has between the naming and its
   first-chance AV (0-1 ms). This also upgrades the Round-16 correction: the "runs past the fault
   point" claim is now measured, not inferred from kernel-call ordering.
4. The original install is unchanged: an inventory of all 17 files (path, size, UTC mtime) taken
   before the copy is identical to one taken after the last run.
5. Method note worth keeping: the CONFIG DUMP Xenia writes into its log is emitted **before**
   command-line parsing - it shows `break_condition_gpr = -1` and `log_level = 2` even in runs that
   demonstrably used the CLI condition and level 3. So the dump cannot confirm CLI cvar arguments;
   their effect must be shown behaviourally (as done here).

INFERRED (not directly observed)
- Host address -> guest address: `0xA0DD42F4` (A) / `0xA0DCC674` (C) are the JIT'd host code for
  guest `0x82CBD80C`. This rests on "the only enabled int3 source is that guest address" plus the
  cvar semantics ("int3 before the given guest address is executed"), not on reading Xenia's
  translation tables. The address changes every run.
- `r3 != 0` means `singleton+0x64 != 0`: `r3` at this instruction is the return of the getter
  `0x832BF128` = `*(X+0x64)` in our image, and the same guest binary is running, so the same
  instruction is expected to do the same thing.
- The condition is "guest GPR 3 == 0, truncated to 32 bits" because that is what the cvars document
  (`# GPR compared to` / `# comparison operator` / `# truncate value to 32-bits`). What is *verified*
  is the behavioural pair: no condition -> 5,029/3,674 hits, `eq 0` -> 0 hits. If Xenia compared some
  other value, the "`r3 != 0`" reading would be wrong - which is exactly why the direct GUI read the
  user asked for next still matters.
- That the one host thread executing the breakpoint is the FEThread (guest 26) follows from it being
  the thread that names worker 35 and the only one seen running this code; a guest-handle-to-host-tid
  mapping was not verified.

## Can the breakpoint be missed? (question 5)

- **JIT timing is not a miss here.** The cvar is read at startup, before any translation, so nothing
  can be "translated too early"; and run C fired in the same copy *after* A and B, with every cache
  file those runs wrote present, which rules out cached pre-translated code suppressing the break.
- **Other int3 sources were disabled** in the copy, and the loader's breakpoint is in `MEM_IMAGE`
  (`ntdll.dll`) and reported separately, so a reported hit can only be the tagged address.
- **Condition semantics work in both directions** (no condition -> thousands of hits; `eq 0` ->
  none). Caveat above: this proves the *comparison* is what suppresses, not which value is compared.
- **The one real way to be missed:** if the guest never reaches the instruction, the breakpoint never
  fires and looks exactly like "the condition was false". For run B I cannot prove from the log alone
  that the guest reached it; the evidence is control C's 3,674 steady hits in an otherwise identical
  80 s run (same boot markers, same log shape, same AV rate). Next step 2 below removes even that
  doubt.
- One behavioural note: a debugger attached means `IsDebuggerPresent()` is true inside Xenia, so its
  own int3 handling may take a different branch - but any int3 landing in JIT code still means the
  guest reached the instruction, which is what was measured.

## How to read `r3`, `r11` and `*(r3+0x64)` in Xenia's debugger window (for the screenshots)

1. The copy is already armed (`break_on_instruction = 2194397196`, `break_condition_gpr = -1`).
   Launch the copy with `--debug`, cwd = the copy directory, same ISO. The debugger window opens at
   startup; the guest reaches `0x82CBD80C` ~15-17 s later (15.4 s and 16.9 s in these runs) and the
   window breaks there.
2. The guest register file is the pane labelled **PPC** (the exe contains the tab labels `PPC ` and
   `x64 `) - read **r3** and **r11** in that pane. This is INFERRED from those strings plus Xenia's
   known debug UI; it was deliberately not exercised in these runs (no GUI, per the conditions).
3. For `*(r3+0x64)`: open the memory viewer and enter the address `r3 + 0x64` - either computed (e.g.
   `r3 = 0xBF3C57D0` -> `0xBF3C5834`) or, if the address box evaluates expressions, `r3+64`. The 4
   bytes there are the pointer we want; the guest is **big-endian**, so read them accordingly. That
   is the field that is `0` in our runtime.
4. Screenshots that settle it: the PPC pane showing `r3`/`r11` at the break, plus the memory view at
   `r3+0x64`. The breakpoint fires ~46-50/s, so it stops on the first of many - Continue once or
   twice to see whether `r3` changes between hits.

## Open / next (each needs approval, both ~80 s, no rebuild)

1. `break_on_instruction = 2193470200` (`0x82BDB2F8`, the bare `+0x64` setter that our images only
   reference through the accessor table `0x824168C8`): if it fires, Xenia *calls* that setter and the
   write mechanism exists; if it never fires, the field is populated some other way in Xenia - the
   actual contradiction to chase.
2. `break_on_instruction = 2200695080` (`0x832BF128`, the getter entry of the fault chain): it must
   fire in a B-like run regardless of `r3`, which removes the last "was the path even executed" doubt
   about run B.
3. GUI-free alternative to the debug window: sweep the same breakpoint with `--break_condition_gpr=3
   --break_condition_op=eq --break_condition_value=<value>` to bracket `r3` numerically.

## Files intentionally unchanged
Our runtime, `dist\Output\*` (`worldcup2010.exe` 17:53:04, `worldcup2010_fifadllzf.dll` 17:52:58),
both override copies (17:38:00), `BuildWorldCup2010.ps1` and the generated sources were not touched;
no codegen time was consumed. No override change, so the backup/dual-copy SHA-256 procedure was not
needed. Only the throwaway Xenia copy was modified, and the read-only original was verified
unchanged.

---

# Round 18 - ordering runs: setter, getter, ctor, publish (one 80 s run each, same copy)

**One line.** The accessor-table setter Round 16 flagged as the `+0x64` writer **never runs in Xenia**
(0 hits, and 0 direct call sites); the ctor and publish each run **exactly once** in the boot phase
before worker 35 exists; the getter and `0x82CBD80C` each run ~58/s starting **after** the naming and
after the worker's first `RtlInitializeCriticalSection`. So `+0x64` is not written through the
accessor setter, and it is already valid when the FEThread's per-frame path reads it.

Status: COMPLETE - 5 runs of 80 s (~8 min of emulator time) on the same copy, no rebuild, no override
change, our runtime untouched. `D:\FWC10\xenia` VERIFIED unchanged (17 files, size + UTC mtime, same
inventory diff as Round 17).

## Runs

Every run: the address patched into the copy's `xenia-canary.config.toml` (`break_on_instruction`,
read back before launch, config 65,968 bytes each time), then
`round17_dbglaunch2.py <copy-exe> <copy> run_<label>.log 80`, `--log_level=3`, cwd = the copy. The
last run re-armed a known-good address as a **positive control** so that the 0-hit result cannot be a
method failure.

| run | guest address | hits | first hit | log lines at first hit | log at end |
|-----|---------------|------|-----------|------------------------|------------|
| setter | `0x82BDB2F8` (2193470200) | **0** | - | - | 298,267 lines |
| getter | `0x832BF128` (2200695080) | **3,367** (57.9/s) | 21.90 s | 10,993 | 183,299 lines |
| ctor | `0x82C50EF0` (2193952496) | **1** | 18.01 s | 7,654 | 205,495 lines |
| publish | `0x82C6AFC8` (2194059208) | **1** | 11.92 s | 7,511 | 282,384 lines |
| control (`0x82CBD80C`) | 2194397196 | **3,573** (57.9/s) | 18.32 s | 11,272 | 226,018 lines |
| earlier: R17 run C (`0x82CBD80C`) | 2194397196 | 3,674 (57.9/s) | 16.87 s | 11,125 | 240,907 lines |
| earlier: R17 run A (`0x82CBD80C`) | 2194397196 | 5,029 (~50/s) | 15.37 s | (v1 tool, no sample) | 550,663 lines |

All hits are `EXCEPTION_BREAKPOINT` in `MEM_MAPPED` RWX memory (the x64 code cache), never in a module.
The control run fired 3,573 times with the same patch-and-run method, so the setter's 0 hits is a real
negative.

## Order (per-run line offsets; the gaps)

Absolute line numbers shift between runs (log volume varied 183k-298k lines for the same 80 s), so each
hit is placed against its **own** log's milestones. Within-run gaps are reliable; cross-run gaps only
as far as the boot path's log volume is reproducible.

| hit / milestone | run | log line | vs `thid26` | vs `thid35` | vs worker's 1st critsec |
|---|---|---|---|---|---|
| publish `0x82C6AFC8` | publish | 7,511 | +1,443 | -3,111 | -3,185 |
| ctor `0x82C50EF0` | ctor | 7,654 | +1,517 | -3,589 | -3,675 |
| **getter** `0x832BF128` | getter | 10,993 | +4,907 | **+247** | **+154** |
| **fault** `0x82CBD80C` | control | 11,272 | +5,206 | **+289** | **+211** |
| **fault** `0x82CBD80C` | R17 C | 11,125 | +5,065 | **+244** | **+166** |
| setter `0x82BDB2F8` | setter | never fired | - | - | - |

`thid26` = `XThread::Execute thid 26` (FEThread start) in that run, `thid35` = `XThread::Execute thid 35`,
worker's 1st critsec = first `RtlInitializeCriticalSection` on the handle that `SetThreadName(35, ...)`
came from (worker handles this batch: `F80003C0`, `F80003C4`, `F80003BC` - per-run, as always).

Order (established): publish entry -> ctor -> FEThread (`thid26`) -> names worker 35 -> worker's first
critsecs -> getter -> faulting read. Setter: never.
Gaps that matter and are reproducible: the fault happens **+244/+289 lines after naming worker 35** and
**+166/+211 lines after the worker's first critsec** (three independent runs, same ballpark); the ctor
and publish both precede the FEThread by thousands of lines.

Caveat: the cross-run 74-line gap between publish (+1,443) and ctor (+1,517) is *not* evidence on its
own - but the statics below fix that ordering independently.

## Static checks

Decoder ground truth first: `0x82BDB2F8` decodes as `stw r4, 100(r3)` / `blr` / `stw r4, 104(r3)`,
matching Round 16 exactly, so the VA -> file-offset mapping (mapped layout, offset = VA - image base)
and the branch decoder are right.

Whole-code-range scan of direct branches (opcode 18), `fifadllzf` image:

- setter `0x82BDB2F8`: **0 sites** -> dead code, agreeing with 0 runtime hits (two independent methods).
- ctor `0x82C50EF0`: **1 site**, a `bl` from `0x82C6AFF0` - inside the publish function.
- publish `0x82C6AFC8`: 1 site, a `bl` from `0x8265EF7C` - inside the starter `sub_8265EF40` (+0x3C).
- fault function `0x82CBD7E0`: 1 site, a `bl` from `0x82CA1DC4`.
- getter `0x832BF128`: **311 sites** (310 `bl`, 1 `b`) -> a widely used shared accessor, not an address
  used only by our fault chain. Spot checks show the same idiom at other sites
  (`bl 0x82C501D0` then `bl 0x832BF128`), and `0x82CBD7F0`/`0x82CBD7F4` is that same idiom.

The publish prologue - the strongest result of the round:

```
0x82C6AFE0  li r3, 0xC4          ; 196 bytes
0x82C6AFE4  bl 0x82A64018        ; allocator
0x82C6AFE8  cmplwi r3, 0
0x82C6AFEC  beq ...
0x82C6AFF0  bl 0x82C50EF0        ; the ctor, on the freshly allocated object
0x82C6AFF4  lis r11, 0x83A4
0x82C6AFF8  stw r3, 25740(r11)   ; PUBLISH: *(0x83A4648C) = obj  (0x83A40000 + 0x648C)
0x82C6AFFC  b ...
```

So `0x83A4648C` - our singleton global - is written by publish right after the ctor. The ordering
publish entry -> ctor is therefore *verified statically*, not merely inferred from line offsets, and
the singleton object is 0xC4 = 196 bytes.

Fault function entry (re-confirms Round 16): `bl 0x82C501D0` (singleton) -> `bl 0x832BF128`
(the `+0x64` accessor) -> `lis/ori r11 = 0x6C6B8` -> `lwzx r28, r3, r11` at `0x82CBD80C`.

Dead end recorded: a plain `stw ..., 100(rX)` sweep is **not** discriminating - 3,821 sites in
`fifadllzf` and 275 in `default.xex`, the majority being the stack slot `100(r1)` - so the real
`+0x64` writer cannot be found that way.

## What each result means (verified vs inferred)

VERIFIED
- The accessor table's setter is **dead**: 0 hits in 80 s in Xenia and 0 direct branch sites in the
  image. Round 16 item 3a's reading of it as the intended `+0x64` producer is withdrawn.
- The ctor runs exactly once, the publish runs exactly once, both before worker 35 exists; the publish
  calls the ctor at publish+0x28 and then stores the object into `0x83A4648C`.
- The getter and `0x82CBD80C` execute **after** worker 35 is named and after its first
  `RtlInitializeCriticalSection` (+154 to +211 lines), reproduced in three runs.
- The positive control fired 3,573 times with the same method, so the setter negative stands.

INFERRED
- One getter call per execution of the faulting entry block: the getter's and the fault instruction's
  observed rates are equal to three significant figures (57.9/s each), which is what that relation
  predicts; but the image has 311 getter call sites, and any contribution from the others in this
  phase is not separated by this measurement.
- Wall-clock first-hit times (11.9-21.9 s across runs) are dominated by host/debugger stalls (~96
  first-chance `AV` round-trips per second in every run) and by per-run audio logging volume, so they
  must not be used for ordering; log-line offsets are the usable proxy, and they are a proxy for guest
  progress, not guest time.
- The `+0x64` writer is a path our port never executes: consistent with everything measured (the field
  is 0 in ours and non-zero in Xenia, the ctor/publish/populate all run in both), but the writer is
  **not identified** by this round.

## Register reads in the debug window (item 4)

The setter never runs, so arming `0x82BDB2F8` in the GUI will never break - there is nothing to read
there. The equivalents that do break, same method as Round 17 (PPC pane; guest is big-endian):

- `0x832BF128` (getter entry): `r3` = the object whose `+0x64` is read (Xenia's singleton), `r4` = the
  incoming argument (not the field), `LR` = the return address into the fault function. Read
  `*(r3+0x64)` in the memory view - that is the field as the getter sees it, i.e. the value the fault
  instruction will load.
- `0x82CBD80C` (the faulting read, still the most direct): `r3` = the accessor's return = the field
  value itself, `r11` = `0x6C6B8`, `LR` = the caller. Steps as in Round 17.
- Xenia's debug UI can hold more than one code breakpoint (the exe's own string: "Add a code breakpoint
  for either PPC or x64"), so `0x832BF128` and `0x82CBD80C` can be armed together and both contexts
  read. Pane names and the memory view's expression support stay INFERRED (no GUI run, per instruction).

## Files intentionally unchanged + verification
Original `D:\FWC10\xenia`: unchanged (17 files, sizes + UTC mtimes identical to the Round-17
pre-copy inventory). Copy config after this round: `break_on_instruction = 2194397196`,
`break_condition_gpr = -1` (left from the control run). Our runtime, `dist\Output\*`, both override
copies, `BuildWorldCup2010.ps1` and the generated sources: untouched, no codegen time consumed, no
override change so no backup round needed.

## Open / next (needs approval)

1. **Trace functions in Xenia.** The binary contains the cvars `trace_functions`,
   `trace_function_references` and `disassemble_functions`; if `trace_functions` logs guest function
   execution, one run would yield the set of guest functions Xenia actually executes, to diff against
   our port's never-executed set (the 69 no-block stubs and anything else that never runs). That
   directly targets the missing `+0x64` producer, and it is one 80 s run.
2. Otherwise: one 80 s breakpoint run per candidate producer function, chosen from that diff.
3. Recorded dead end: the setter path and the plain `stw ..., 100(rX)` sweep.

---

# Round 19 - static only, the `+0x64` writer identified: `sub_82C9A4B0` allocs `0x6C6D0`, `sub_82C8D278` constructs, `stw r3,100(r31)` publishes into the singleton

**Box.** 45 min, no runs, no rebuild, no Xenia process, no override change. Method: read both
decompressed images (`xexdump\{fifadllzf,default}.dec.bin`, mapped layout, offset = VA - base, bases
`0x82300000` / `0x82000000`) and the generated entry list (92,058 `SetFunction(0x...)` entries
extracted from `generated\**\*.cpp`: 4,875 default + 87,183 fifadllzf; cached in
`round19_entries.json`). Everything with new throwaway scripts; **no file under `D:\FWC10\xenia` or
`C:\FWC10B\xenia_dbg` was launched, read or written** (the original was re-inventoried anyway: 17
files, size + UTC mtime identical to `round17_orig_inventory.txt`, `diffs=0`).

**Result in one paragraph.** The null field is filled by a textbook `new` sequence in
`sub_82C9A4B0`: `obj = alloc(0x6C6D0, 0, <rw45 tag>)`; `if (obj) obj = ctor(obj)` (`bl 0x82C8D278`,
returns `this`); `this->[+0x64] = obj` (`stw r3,100(r31)` @ `0x82C9A4F8`), with `r31 = this` set by
`mr r31,r3` on entry. Its only two call sites, `0x82D03D4C` and `0x82D1F234`, each execute
`bl 0x82C501D0` (the singleton getter, `r3 = *(0x83A4648C)`) **immediately** before, with no move of
`r3` in between - so `this` is the singleton and the field is `*(0x83A4648C)+0x64`. The size
`0x6C6D0 = 0x6C6B8 + 0x18` is the *only* allocation in either image inside `0x6C600..0x6C800`, and it
is exactly large enough for its last field to be the `+0x6C6B8` element count that the faulting `lwzx`
reads. Our own build's DR write history of `+0x64` (3 stores, all zero/poison) proves this call has
never happened in our build - and because the alloc-failure arm (`li r3,0`) falls into the *same*
store, the absence of a 4th store means the call, not merely the success path, is missing.

## Item 1 - all references to `+0x6C6B8` and to the 8144 stride, grouped by class

Method: every aligned word of both code ranges; accept `lis rD,6` completed within 8 instructions by
`ori rD,rD,0xC6B8` (or the equivalent `lis rD,7` + `addi rD,rD,-14664`) with no intervening rewrite of
`rD`; for the stride accept `mulli rD,rA,8144`, `li rD,8144`, `ori rD,rD,0x1FD0`. Each site is mapped
to the containing generated entry (nearest entry <= VA).

Counts: **default.xex: 0 and 0. fifadllzf: 164 sites of `+0x6C6B8` (in 162 functions - two functions,
`sub_82C7FC08` and `sub_82D988B8`, have 2 sites) and 48 sites of stride 8144** (all `mulli` except
`0x83477A38` (`ori`) and `0x83500C1C` (`li`)).

Decoded, the cluster is a "big inline array with a count" layout (this corrects the Round-12 wording
"the segment owns the big array at +0x6C6B8"):

| addr | decoded | meaning |
|---|---|---|
| `0x82C71858` | `lwz r11,4(r3)` / `mulli r10,r4,8144` / `add r3,r10,r11` / `blr` | `return this->[+4] + idx*8144;` - element accessor; **`+4` is the array base pointer** |
| `0x82C71740` | `lwzx r4,r3,r11(0x6C6B8)` / `lwz r3,0(r3)` / `mulli r11,r4,8144` / `add r5,r11,r10` | `end = this->[+4] + this->[+0x6C6B8]*8144` -> **`+0x6C6B8` is the element COUNT** |
| `0x82C718D0` | `stwx r4,r3,r11(0x6C6B8)` / `blr` | the count **setter** (2 call sites: `0x82CE7330`, `0x82CE8C78`) |
| `0x82C71868` | count used as a sub-index into a stride-**2036** table (`mulli r11,r11,2036`, `+1561`) | a second, smaller inline table |
| `0x82C71890` | compares an incoming value against the count (`cmplw` -> `li r11,0` / `li r11,1`) | bounds test |
| `0x82C718B8` | `add r11,r4,r3` / `ori r10,r10,0x6C6BC` | access to `+0x6C6BC`, 4 past the count |

Classification of the 164 sites by what follows the constant: **160 loads, 3 stores, 1 value-built.**
The three stores (the count writers) are `0x82C718D0` (setter), `0x82C7FC5C` in `sub_82C7FC08`
(`stwx r30,r31,r11`) and `0x82C933EC` in `sub_82C933E0` (`stwx r31,r3,r11`) - the latter two store a
value already in a register, not a fresh allocation. Callers: `sub_82C7FC08` <- `0x82C935A0`,
`0x82C93648`, `0x82C9AF80`; `sub_82C933E0` <- `0x82D9C2B0`.

**Grouping by class** (proxy: a maximal run of consecutive code pointers in `.rdata` is a dispatch
array; 1,663 such runs of >=3 pointers exist). Of the 173 functions in the union list assembled for
this grouping (the full `0x6C6B8` list, the stride-8144 users decoded by hand, the producer, the ctor),
159 are referenced from `.rdata`, 77 sit inside a run of >=3, and 96
do not. The 14 runs that hold them:

```
run@0x82471808 len=111 : 82D9DC90 82D9E6B8 82D9F7D0 82D9F928 82D9FB40 82DA00B8 82DA0D50 82DA10C0
                         82DA1150 82DA15E8 82DA2758 82DA27F8 82DA2868 82DA28F8 82DA2EF0 82DA2F40 ...
run@0x824707B8 len=137 : 82D8B8C0 82D8BAF8 82D8BFC8 82D8C0E0 82D8D1F0 82DC9540 82DC99F0 82DDEB00
                         82E006A0 82E20AD8 82E20D30
run@0x82470B78 len=21  : 82DBA510 82DBA5A8 82DBA5F0 82DBA688 82DBA6D0 82DBA8D8
run@0x82471648 len=77  : 82D95918 82D95B38 82D95C08 82D95CE8 82D95E60 82D984B8
run@0x8244CD0C len=66  : 82D3DE38 82D3DEA8 82D3E1D8 82D43E38 82D43EE8
run@0x82471248 len=255 : 82DBF9D0 82DC0B58 82DC0E38 82DD7480 82DE7550
run@0x824719C8 len=25  : 82DA5FF0 82DD0718 82E111E0 82E126D0
run@0x82453BF8 len=16  : 82D436B8 82D437B8 82D438A0
run@0x82453950 len=17  : 82D3BB28 82D3BC10
run@0x824537C0 len=14  : 82D3AE08
run@0x82453B14 len=56  : 82D3A110
run@0x82470CE0 len=50  : 82D988B8
run@0x82470EA8 len=231 : 82DF8BC0
run@0x82471C28 len=54  : 82DB9858
```

96 union functions are in no run of >=3 (14 of them have no `.rdata` reference at all) - including the
whole accessor cluster `0x82C71740 / 0x82C71858 / 0x82C71868 / 0x82C71890 / 0x82C718D0` and the fault
function `0x82CBD7E0` itself. Conclusion: **`+0x6C6B8` is a shared layout offset, not one class** -
~14 dispatch groups plus 96 non-virtual users all have an inline 444 KB region whose last field is a
count of 8144-byte elements. The class that matters here cannot be named from the offset; it is named
by its instance size and ctor (item 2).

`sub_82C71858` callers: **192 `bl` sites in 142 distinct functions** (one each; e.g. `0x82CB43B8`,
`0x82CB43F8`, `0x82CB451C`, `0x82CB5048`, `0x82CB89C8`, `0x82CC5098`, `0x82CC512C`, `0x82CD6BDC`,
`0x82CD7D70`, `0x82CE669C`, `0x82CE76E8`, `0x82CE9DC4`, ...) - none of them is on our fault stack.
Its neighbour `sub_82C71770` (the stride-2036 lookup) is called 68 times from 15 functions
(`0x82D9DEE0` x20, `0x82D9E7A8` x10, `0x82D9F108` x6, `0x82D9EF18` x5, `0x82D9F2E8` x5, ...).

Tool find while doing this: the `.rdata` region `0x8260_4xxx`-`0x8260_7xxx` holds
`{u32 func, u32 0x4000_0000|(instr_count<<8)|flags}` pairs, i.e. per-object **function extent
tables**; they agree exactly with the generated entry list (e.g. `0x82C8D278` sized 0x88 to the next
entry `0x82C8D300`). `sub_82C9A4B0` sits in the table at `0x826049E0`, its ctor `0x82C8D278` in the
one at `0x82604578` (with `0x82C8D410` @ `0x82604590`, `0x82C8D8B0` @ `0x826045A8`).

## Item 2 - the constructor and every allocation of that size (the decisive find)

Every `bl 0x82A64018` (the generic 3-argument RW allocator `(size, 0, file:line)`) in both images with
a constant size in `r3` materialised nearby: **229 sites**. Exactly **one** has a size in
`0x6C600..0x6C800`:

```
fifadllzf  alloc@0x82C9A4E0  size=0x6C6D0 (444112)  ->  stw r3,100(r31)@0x82C9A4F8   in sub_82C9A4B0
```

`0x6C6D0 = 0x6C6B8 + 0x18`. Raw instruction stream from the function head:

```
0x82C9A4C4  3D608243  lis   r11, 0x8243            ; rw45 file:line pool  -> r11 = 0x82430000
0x82C9A4C8  7C7F1B78  mr    r31, r3                ; r31 = this
0x82C9A4CC  3BCBB7C4  addi  r30, r11, -18492       ; r30 = 0x8242B7C4
0x82C9A4D0  3C600006  lis   r3, 6
0x82C9A4D4  38800000  li    r4, 0
0x82C9A4D8  6063C6D0  ori   r3, r3, 0xC6D0         ; size = 0x6C6D0
0x82C9A4DC  38BEECD7  addi  r5, r30, -4905         ; tag = 0x8242A49B
0x82C9A4E0  4BDC9B39  bl    0x82A64018             ; obj = alloc(size, 0, tag)
0x82C9A4E4  28030000  cmpli cr0, r3, 0
0x82C9A4E8  4182000C  beq   0x82C9A4F4             ; alloc failed -> keep NULL
0x82C9A4EC  4BFF2D8D  bl    0x82C8D278             ; obj = ctor(obj)   (this returned in r3)
0x82C9A4F0  48000008  b     0x82C9A4F8
0x82C9A4F4  38600000  li    r3, 0
0x82C9A4F8  907F0064  stw   r3, 100(r31)           ; this->[+0x64] = obj    <<< THE PRODUCER
```

All other `+0x64` store candidates are excluded: the image has 192 `bl T ; stw r3,100(rY)` sites in
total (full list in `round19_item2_out.txt`), and only `0x82C9A4F8` stores an *allocator + ctor*
result; every other site stores either into `r1` (a stack temp, e.g. `0x8285E09C`, `0x8291EFD8`) or
into the `+0x64` of a different class (e.g. `0x82668580`, `0x82A4C598`, `0x82AB63E0`, `0x82AE3D64`).

The ctor is `sub_82C8D278` (extent `0x82C8D278..0x82C8D300`, 0x88 bytes; exactly **1** `bl` caller,
the allocator site above). It builds sub-objects at `+16` and `+1504` (`bl 0x8325FC60`), initialises
the self-linked list heads at `+7460/+7464/+7468`, passes `this+0x5BB18` to `0x82C71648`, and calls
`0x82C58B68` at the end. Its complete store list is `+7460, +7464, +7468` plus one `stwx` at
`+0x1D24`-style offsets - and it **never writes offset 0**, so the object has no vtable pointer at
`+0` (RW 4.5, RTTI stripped). That is the screenshot signature to check (item 4).

Where the pointer goes, with proof of identity: only `stw r3,100(r31)` @ `0x82C9A4F8`, and

```
0x82D03D48  bl 0x82C501D0     ; r3 = *(0x83A4648C)   (singleton getter)
0x82D03D4C  bl 0x82C9A4B0     ; -> stores into *(0x83A4648C)+0x64
0x82D1F230  bl 0x82C501D0     ; same pair
0x82D1F234  bl 0x82C9A4B0
```

so `*(0x83A4648C)+0x64` is the `0x6C6D0` object. (The accessor table getter `0x832BF128` that
delivers it is referenced from three flat `.rdata` tables - `0x82414B3C`, `0x82415084`, `0x82416908`,
each with `0x832BF110` / `0x832BF128` / `0x832BF140` adjacent - i.e. a shared accessor table, not a
per-class vtable. INFERRED.)

Allocation sizes for context (top of the table): 444112 (ours), 165392, 165104, 160688, 160528,
160448, 160432 x5, 160416 x3, 158096, 88092 (`0x82CA157C` -> `stw r3,76(r31)`), 34144, 32580, 18816,
14972, 7664, 7600, 6144, 6120 (`0x1DF0` - note the near-miss with `8144`, not a multiple), 6096, ... No
other site matches `0x6C6B8 + N*8144`, and the 8144-stride array itself is **never separately
allocated** - it lives behind the `this->[+4]` base pointer.

## Item 3 - is any of this reached in our build?

From our own runtime data (nothing new run):

- **DR write history of `singleton+0x64`: 3 stores, all zero/poison** (memset 0, memset-poison
  `0xCDCDCDCD`, ctor 0) - never a valid pointer (header line 27). The producer's store at
  `0x82C9A4F8` is reached on *both* arms of the alloc test, so its absence means the **call never
  happened** (VERIFIED for our build).
- **PC data we have**: the faulting thread's own stack walk (minidump, `PPCFuncMappings[]`):
  `sub_82CBD7E0` <- `sub_82CA1B50` <- `sub_82A64EC8` <- `sub_8265E158` <- `sub_8265E810` <-
  `sub_82A70B30` <- `sub_8265F5F0` <- `sub_8267CAD8` <- `sub_82836038 / sub_828360B8 / sub_8282FD10`.
  None of the producer's callers (`0x82D03C90`, `0x82D1F100`, `0x82D03E68`, `0x82D03EB8`, `0x82D21D38`,
  `0x82D22390`) is on it.

The guards standing between our build and the producer, per call site:

- `0x82D03D4C` (in the state step `sub_82D03C90`): reached only from case **8** of
  `switch (this->[+24])` - `0x82D03CD4 cmpi cr6,r11,8` / `0x82D03CD8 bc(eq) -> 0x82D03D14` - and then
  a **one-shot gate byte**: `0x82D03D14 lbz r11,35(r30)` / `0x82D03D18 cmpli cr0,r11,0` /
  `0x82D03D1C bc(eq) -> 0x82D03E50` (skip when the byte is 0) / `0x82D03D24 stb r11(0),35(r30)` (clear
  it) -> `bl 0x82C501D0` -> producer. The step is called by `sub_82D03E68`, which is the generic
  setter `this->[+24] = r4; step(this);`.
- `0x82D1F234` (in `sub_82D1F100`): on its `+0x24 == 9` arm (`0x82D1F14C lwz r11,24(r31)` /
  `0x82D1F150 cmpi cr6,r11,9` / `0x82D1F154 bc(ne) -> 0x82D1F3BC`), additionally behind
  `bl 0x82664D90(...) == 1` and a non-null `*(r30-140)` (INFERRED).
- The chain is entered through a **dispatch table, not a call**: the root `sub_82D22390` has **0
  direct `bl` callers** and is referenced only from `.rdata` at `0x8244CE10` and `0x82607418`
  (VERIFIED). Tree: `sub_82D22390` -> `sub_82D21D38` / `sub_82D03EB8` -> `sub_82D1F100` /
  `sub_82D03E68` -> `sub_82D03C90` -> producer.
- Setters of the one-shot gate byte `+0x23` (43 `stb rX,35(rY)` sites in 41 functions; the ones
  writing 1 are `0x82D0CD40` in `sub_82D0CD20` and `0x82D1FD34` in `sub_82D1FB78`, plus
  `0x82CE8390`, `0x82CE8AF0`, `0x82CFFDF8`, `0x835F9030`, `0x835F9500`, `0x835F9FD0`) are the trigger
  side of the same machine.

**Verdict.** For this field there is exactly one producer, and it is **not reached** in our build
(DR-verified). The candidate guards are now two instructions (`0x82D03CD8` state==8, `0x82D03D1C`
gate-byte==0) plus the table slot at `0x8244CE10` / `0x82607418` that starts the chain. Which one
excludes us is the only open question, and it is **not decidable statically** from the data in hand.

## Item 4 - what to look for when the screenshots arrive

Read the first words of the object at `r3` (of `0x832BF128`, or of `0x82CBD80C` - `r3` there *is* the
field) and compare with the `0x6C6D0` object found here:

- `+0`: expect **not** a code pointer (the ctor never writes it). If it *is* one, this allocation is
  not the one Xenia took and the class must be re-derived from the words.
- `+4`: the base pointer of the 8144-byte-element array (a heap pointer, e.g. `0xBF3Cxxxx`).
- `+0x18` / `+0x24`: the state fields the two caller state machines switch on (small ints).
- `+0x1D24 / +0x1D28 / +0x1D2C` (7460/7464/7468): the self-linked list heads.
- `+0x5BB18`: passed to `0x82C71648` by the ctor.
- `+0x6C6B8`: the element count. In Xenia it must be readable; at our `0x82CBD80C` it is irrelevant
  because `r3` itself is 0 there.
- Also still wanted at `0x82CBD80C`: `r3` (should be a heap pointer), `r11 = 0x6C6B8`, `LR`.

## Verified vs inferred

| claim | status |
|---|---|
| `*(0x83A4648C)+0x64` is written by `stw r3,100(r31)` @ `0x82C9A4F8` | VERIFIED (raw words) |
| `r31` there is the singleton: both call sites run `bl 0x82C501D0` immediately before, `r3` unmoved | VERIFIED (raw words) |
| class instance size `0x6C6D0 = 0x6C6B8 + 0x18`, ctor `sub_82C8D278`, only alloc site in range | VERIFIED |
| `+0x6C6B8` = element count, `+4` = array base, stride 8144, setter `0x82C718D0` | VERIFIED (decoded) |
| the store has never executed in our build | VERIFIED (Round-12/13 DR write history) |
| the chain root `sub_82D22390` has 0 `bl` callers, only `.rdata` `0x8244CE10` / `0x82607418` | VERIFIED |
| `+0x6C6B8` is a shared layout: ~14 dispatch runs + 96 non-run users | VERIFIED (counts); class semantics INFERRED |
| getter `0x832BF128` lives in a flat shared accessor table, not a class vtable | INFERRED |
| the `0x82D1F234` arm needs `bl 0x82664D90(...)==1` and non-null `*(r30-140)` | INFERRED |
| which guard (state==8 / gate byte / table slot) excludes our build | **OPEN** |

## Tooling written this round (temp dir only)

`round19_item12.py` (constant + stride sweep, load/store classification, allocator table,
`bl T ; stw r3,100(rY)` sweep, entry-list cache), `round19_item2.py` (alloc-size window, producer and
ctor disassembly, caller tree, `.rdata` refs, generated-corpus check), `round19_item3.py` (same +
accessor-table dump), `round19_item4.py` (raw words, caller-site guards, class-descriptor and `.rdata`
dumps, caller root climb), `round19_item5.py` (`.rdata` run grouping, caller-function grouping, ctor
stores), `round19_flag.py` (gate-byte setters); outputs `round19_*_out.txt`, cache
`round19_entries.json`. No file outside `C:\Users\<user>\AppData\Local\Temp\opencode\` was written.

## Files intentionally unchanged + verification

Our runtime, `dist\Output\*`, both override copies, `BuildWorldCup2010.ps1` and the generated sources:
untouched; **no codegen time consumed**; no override change, so the dual-copy SHA-256 + timestamped
backup procedure was not needed. `D:\FWC10\xenia` was re-verified this round (17 files, size + UTC
mtime identical, `diffs=0`); `C:\FWC10B\xenia_dbg` was neither launched nor modified.

## Open / next (each needs approval)

1. **Screenshots (user)** - the item-4 word list is the ready cross-check for `r3` and `*(r3+0x64)`.
2. **Static, free, no runs**: callers of the gate setters `sub_82D0CD20` / `sub_82D1FB78`, and of
   whatever populates `.rdata` `0x8244CE10` / `0x82607418`, diffed against the executed set. Cheapest
   way to turn the OPEN line into a named branch.
3. **One 80 s Xenia run (approval)**: `break_on_instruction = 2194252976` (`0x82C9A4B0`) to confirm the
   producer fires in Xenia before the `0x82CBD80C` read; optionally `0x82D03D4C` for the exact guard.
   (`trace_functions` dropped per instruction - our port has no execution trace to diff.)
4. **Our own GUI run**: would show which of the two guards our path stops at (same words as item 4).

---

# Round 20

**Box:** 60 min, no rebuild, no codegen, no override change. One Xenia batch on the throwaway copy
(`C:\FWC10B\xenia_dbg`, `D:\FWC10\xenia` untouched - verified afterwards: 17 files, sizes + UTC
mtimes identical to `round17_orig_inventory.txt`, `diffs = 0`) of **4 x 80 s, one guest address per
run**, plus **one run of our build** with DR0-DR3 execute breakpoints. Wall times: Xenia runs
124 s / 143 s / 123 s / 124 s (80 s deadline + log flush + kill), batch ~8.4 min; our build 5.3 s
(process exits 0xC0000005 before the 60 s deadline). Commands and tools are the ones in
`round20_dbg.py`, `round20_xdrv.py`, `round20_parse.py`, `round20_dr.py`, `round20_static*.py`,
`round20_maps.py`, `round20_dec.py` under `%TEMP%\opencode`.

## Item 1 - which object owns `0x82D03CD8` / `this+0x23`, and where it is created

**Function starts containing the two call sites (VERIFIED, entry list + decode):**

| call site the task names | instruction there | containing function |
|---|---|---|
| `0x82D03D48` | `bl 0x82C501D0` (singleton getter) | **`sub_82D03C90`** |
| `0x82D03D4C` | `bl 0x82C9A4B0` (the "producer") | `sub_82D03C90` |
| `0x82D1F230` | `bl 0x82C501D0` (getter) | **`sub_82D1F100`** |
| `0x82D1F234` | `bl 0x82C9A4B0` (producer) | `sub_82D1F100` |

`0x82C501D0` decodes to `addis r11,r0,-31836 ; lwz r3,25740(r11) ; blr` = `r3 = *(0x83A4648C)` - the
singleton global (VERIFIED). `0x832BF128` decodes to `lwz r3,100(r3) ; blr` - the `+0x64` getter
(VERIFIED; it is entry 19 of the 8-byte-spaced getter block `0x832BF0C0..`, each
`lwz r3,N(r3); blr`).

**A = `sub_82D03C90`** is a switch on `this+0x18` (`lwz r11,24(r3)`, `mr r30,r3`), cases
2,3,4,6,7,8,9; the byte at `0x82D03CD8` is `beq cr6 -> 0x82D03D14` for **state == 8**, and case 8
starts with the one-shot **gate `lbz r11,35(r30)` (`this+0x23`)**, returns if zero, else clears it
(`stb 0,35(r30)`), then `bl 0x82C512E8`, `bl 0x82C501D0` (getter), **`bl 0x82C9A4B0`** (producer),
logging via `0x82A63278`/`0x82A63578`, and finally the global `0x83A46984` (one-shot, = 1). So the
producer is reached only when `this`'s state is 8 **and** `this+0x23` is armed.

**B = `sub_82D1F100`** is a switch on `this+0x24` (`lwz r11,36(r31)`, `mr r31,r3`; it first stores
`-1` there and `3` at `this+0x1C`), case 1 calling getter + producer; it ends by writing
`singleton+0x94` (`stb r28,148(r3)` after the getter) - i.e. it writes into the singleton while
`this` is a different object.

**ROOT = `sub_82D22390`** is the manager's command dispatcher: `sub_82D22390(this, msg, arg)`
switch on `r4` (=1,9,0xD,0x17,0x2A,0x2B,0x30,0x46,0x4B,0x4C,0x54). **Case `msg == 1` initialises
exactly the field set of the object we are chasing** (VERIFIED disassembly):

```
0x82D22464  addi r11,r0,0 ; addi r10,r0,-1 ; addi r9,r0,3 ; addi r8,r0,1
0x82D22470  stw r11,24(r31)   ; +0x18 = 0      (A's state)
0x82D2247C  stw r9, 28(r31)   ; +0x1C = 3
0x82D22480  stb r11,32(r31)   ; +0x20 = 0
0x82D22484  stb r11,33(r31)   ; +0x21 = 0
0x82D22488  stb r11,34(r31)   ; +0x22 = 0
0x82D2248C  stb r8, 35(r31)   ; +0x23 = 1   <-- the gate, armed
0x82D22490  stw r10,36(r31)   ; +0x24 = -1    (B's state)
0x82D22494  stw r10,40(r31)   ; +0x28 = -1
0x82D22478  stw r11,44(r31)   ; +0x2C = 0     (accumulator, used by 0x82D21D38)
```
with `r31 = this` (`mr r31,r3` at `0x82D223A4`). ROOT case 9 -> `bl 0x82D21D38` (the caller of B);
ROOT also `bl 0x82D03EB8` (which calls A's driver); `0x82D21D38` adds into `this+0x2C`.

**It is NOT the singleton; it is a separate polymorphic manager (VERIFIED by constructors):**

- The singleton is the 0xC4-byte object built by ctor `0x82C50EF0`: `addi r11,r0,0` then
  `stw r11,0(r3) .. stw r11,192(r3)`, `blr` - **a pure POD, no vptr at all** (`+0` is written
  `obj-8` later per Round 19). It therefore cannot be the object ROOT/A/B operate on, because that
  object's `+0` is a **vptr**.
- The state/gate object's ctor is **`0x82D041B8`**: `alloc(68,0,"rw45 tag")` at `0x82D17CB0` inside
  the factory **`sub_82D17A50`**, `bl 0x82D041B8` at `0x82D17CC4`, and the ctor stores
  `0x8244CE04` into `+0(r3)` (`stw r9,0(r3)` at `0x82D041E4`) - i.e. **vptr = `.rdata 0x8244CE04`**.
  It initialises exactly `+0x04,+0x0C,+0x10,+0x14,+0x18,+0x1C,+0x20..0x23,+0x24,+0x28,+0x2C,+0x30,
  +0x34,+0x38,+0x3C,+0x3D,+0x3E,+0x3F,+0x40` - the same layout, 68 bytes.
- The sibling 0x80-byte object (ctor `0x82D04048`, alloc(128) at `0x82D17C90`, `bl` at
  `0x82D17C9C`, vptr `0x8244CDFC`) has the identical `+0x18 / +0x1C / +0x20..0x23 / +0x24` pattern
  (`stw r11,24(r31)`, `stw r11,28(r31)`, `stb r11,35(r31)` at `0x82D040DC`), so the family shares
  this layout; the factory also builds a 0x20-byte object (ctor `0x82D03F48`) and several
  4-byte vptr-only objects.
- **Reached how:** the factory `sub_82D17A50` is called from `0x82D17EC0` (5 callers) and
  `0x82D17F28` (9 callers). The **state driver `0x82D03E68`** (`stw r4,24(r3)` = set state, then
  `bl 0x82D03C90` = run A) has 9 direct `bl` callers: `0x82D03EB8`, B x5 (`0x82D1F160/170/2E8/314/374`),
  `0x82D21D38` x2, and **ROOT x1 (`0x82D223E8`)**. `0x82D21D38` is called only by ROOT
  (`0x82D22440`), and `0x82D03EB8` only by ROOT (`0x82D224EC`). So ROOT is the single entry that
  drives both the driver/A and B, and ROOT itself is reached only as a **virtual method** (below).

## Item 4 - `.rdata 0x8244CE10` and `0x82607418`

- **`0x8244CE10` is a vtable slot (VERIFIED).** `0x8244CDF4`, `0x8244CDFC`, `0x8244CE04` are three
  overlapping vtable bases inside one `.rdata` run of code pointers:
  `0x8244CE04..0x8244CE10 = [0x82D03810, 0x82D1FB78, 0x82D03810, 0x82D22390]` - **ROOT is slot 3 of
  the vtable at `0x8244CE04`** (offset `+0x0C`), which is exactly the vptr the 0x44-byte manager's
  ctor `0x82D041B8` installs. `0x8244CDFC..0x8244CE10 = [0x82D05920, 0x82D1F708, 0x82D03810,
  0x82D1FB78, 0x82D03810, 0x82D22390]` puts ROOT at `+0x14` of the 0x80-byte sibling (installed by
  `0x82D04048`); `0x8244CDF4` is the base whose slots 0/2 (`0x82D058D0`, `0x82D05920`) are the two
  deleting-destructor variants that re-install these vptrs (`0x82D03FE0`, `0x82D04160`). Nothing
  "populates" the slot at runtime: the vtables are static `.rdata` and the loader relocates them;
  **the dispatch is an ordinary virtual call** through the object's vptr (INFERRED for the exact
  call site - no direct caller of ROOT exists in either image, consistent with a `lwz/mtctr/bctr`
  dispatch). Note `0x82D1FB78` (slot 1/3 of the same family, listed in Round 19) is itself a
  `stb rX,35(rY)` gate writer, which independently confirms the class identity.
- **`0x82607418` is NOT a dispatch vector.** It is ROOT's own entry in the guest's static
  **function-extent table**: a contiguous run of 16-byte `{code ptr, 0x4000_0000|(ninstr<<8)|flags}`
  pairs over consecutive functions (`0x82D218A8`/`0x40008A03`, ..., `0x82D21D38`/`0x40005305`,
  `0x82D22390`/`0x40006B05`, `0x82D22540`, ...), agreeing with the generated entry list. It is
  constant `.rdata`; the value `0x82D22390` there is ROOT's own metadata, not a caller - which is
  why Round 19's "0 `bl` callers, only `.rdata` refs" reading was a false lead.

## Item 2 - the Xenia batch (4 x 80 s, one address per run)

Host tids from the debug events were mapped to guest threads with each run's own
`XThread::Execute thid N (handle=..., 'name', native=XXXX)` lines.

| armed guest address | int3 hits | first hit | guest thread(s) | order vs the run's own milestones |
|---|---|---|---|---|
| `0x82C9A4B0` producer | **0** | - | - | **never executed in 80 s** |
| `0x82D03C90` A | 6 | 21.74 s, log line 10910 | **26 FEThread** x6 | +4905 from thid26, +213 after `SetThreadName(35` (10697) |
| `0x82D1F100` B | 2 | 22.17 s, log line 12955 | **26 FEThread** x2 | +6860 from thid26 (after the read) |
| `0x82D22390` ROOT | **30,670** | 15.56 s, log line 9105 | **26 FEThread x30,667**, **6 Main XThread x3** | +3029 from thid26 (before the read) |
| `0x82CBD80C` (Round 18 control) | 3,573+/run | 18.32 s, log line 11272 | **26 FEThread** (host tid 13956 = native 0x3684) | +5206 from thid26, +297 after `SetThreadName(35` |

So in Xenia the instruction that kills our port runs on **guest thread 26 / FEThread**, and ROOT
(30,670x) and A (6x) run **before** the first read, while B first runs after it. The producer runs
**zero times** - so A's gate-protected call at `0x82D03D4C` is **not taken** in Xenia within 80 s,
i.e. either `this+0x23 == 0` or the state is never 8 at those 6 calls.

## Item 3 - our build, one run, DR0-DR3 on the same four functions

- Resolution was done **at runtime from the module's own table**: the DLL was found by scanning
  loaded modules for the `PPCFuncMappings` signature at `rva 0x7313000` (`.data`, 87,183 entries of
  `{u64 guest, u64 host}`; the same table is also locatable in the shipped file). Measured:
  `base = 0x7FFC9A180000`, `0x82C9A4B0 -> 0x7FFC9C49D0F0` (rva 0x231D0F0),
  `0x82D03C90 -> 0x7FFC9CF5DAB0` (0x2DDDAB0), `0x82D1F100 -> 0x7FFCA09585B0` (0x67D85B0),
  `0x82D22390 -> 0x7FFCA05D52D0` (0x64552D0).
- Breakpoints were installed with `SetThreadContext` on all 34 existing threads at 1.12 s and on
  every subsequent `CREATE_THREAD` event (the DLL is loaded dynamically, so the initial loader
  breakpoint is too early - the first attempt at 0.03 s found nothing).
- **Result: 0 hits on DR0..DR3.** The only exception before exit is the runtime's own guest fault:
  `Unhandled guest access violation: read of guest 0x0006C6B8 (host 0x000000010006C6B8)` at 3.26 s,
  guest thread handle `0xF8000354`, then `EXIT_PROCESS code=0xC0000005` at 5.26 s. So **in our build
  the read at `0x82CBD80C` is reached without A, B, ROOT or the producer ever having run**, on a
  path (`sub_82CA1B50 -> sub_82CBD7E0`) that does not contain any of them.
- Reliability of an absence: the producer, A and B each have **only direct `bl` call sites**
  (`0x82D17CC4`-style `bl`, at `0x82D03D4C`, `0x82D1F230` etc.), and the generator emits one host
  function per guest function with `bl` becoming a real call, so their absence is reliable **unless
  the generator inlined them into the caller** (no evidence of inlining in the generated sources
  read so far; to be confirmed by checking whether the caller's host body contains the callee's
  code). ROOT is the weakest: it has no `bl` caller at all and is reached only indirectly through
  its vtable slot, so its absence is reliable only if the runtime routes the indirect call through
  the same table entry - absence here is **not** proof that no virtual dispatch happened.

## The contradiction this round establishes

Round 19 concluded the producer `sub_82C9A4B0` is the writer of `singleton+0x64`. Round 20 shows
**in Xenia the producer never runs in 80 s**, while the same instruction (`0x82CBD80C`) that dies in
our port executes thousands of times there and the game keeps running. Two explanations survive:

1. **Xenia's field is non-zero from some other writer.** Then Round 19's "only writer" scan is
   incomplete (a `stwx`/accessor/`memcpy` path, or a writer in the `default.xex` image). Evidence
   for: Round 17's `break_condition_gpr` test on `r3 == 0` at `0x82CBD80C` fired **0 times**.
2. **Xenia's field is also 0 and the read is harmless there.** Xenia commits guest pages lazily on
   access (its log contains repeated `BaseHeap::AllocFixed attempting commit on unreserved page`),
   and guest `0x6C6B8` is a normal low guest address in Xenia, so `lwzx r28,0,0x6C6B8` returns
   memory instead of faulting; our runtime instead reports `Unhandled guest access violation` for
   the **uncommitted** page of its 4 GB arena (`virtual base 0x0000000100000000`), i.e. the port's
   guest memory does not fault-in the page Xenia would. Evidence for: the producer and B's
   producer call are never taken in Xenia either, and Round 17's condition-test semantics were
   explicitly **INFERRED** (the notes flag that the cvar may not compare guest GPR r3).

Explanation 2 would make the root cause the runtime's arena/commit behaviour, not a missing guest
call. Neither is proven; the smallest decider is already queued:

1. **User-run GUI read (Xenia `--debug`)**: at the breakpoint on `0x82CBD80C` (or on `0x832BF128`)
   read guest `r3` and `r3+0x64` big-endian, and the word at `0x83A4648C+0x64` via the memory pane.
   A non-zero `r3`/`+0x64` proves (1); zero proves (2).
2. **Sanity-check the `break_condition_gpr` cvar** on a value known to be zero/non-zero (e.g.
   arm `0x82CBD80C` with `gpr = 4, value = 0` if r4 is provably non-zero) - cheap, but needs one
   more approved Xenia run.
3. **Static, free**: re-scan both images for *every* store to `singleton+0x64` (all `stw`/`stwx`
   with base provably from `0x83A4648C`, plus `memcpy`-shaped writers), and check whether the
   runtime's arena commit path differs from Xenia's. No run needed.

Nothing in Rounds 7-19 is withdrawn by this round other than the *claim* that the producer is the
writer being "identified" - it is now "identified statically, **not** exercised by Xenia in 80 s".

---

# Round 21 - the Round 20 contradiction is RESOLVED: `singleton+0x64` is 0 in Xenia too, and the
# fault is our runtime's virtual-heap access-violation handling

**Box.** 60-minute box for the request's items 1-2; item 3 time-boxed to ~30 min; item 4 answered as
a proposal only (nothing run). No rebuild, no codegen, no override change, no game data re-staged, no
GUI launched. Xenia ran **only on the copy** `C:\FWC10B\xenia_dbg` (2 x 80 s). `D:\FWC10\xenia`
re-verified after the round: 17 files, sizes **and** UTC mtimes identical to
`round17_orig_inventory.txt` (`diffs = 0`). Every claim below is marked VERIFIED or INFERRED.

Tools (all in `%TEMP%\opencode`): `round21_xdrv.py` (condition driver: config-file delivery +
read-back of all five breakpoint keys), `round20_dbg.py` (int3 counter + host-tid attribution,
reused unchanged), `round21_static.py` / `round21_static2.py` / `round21_static3.py` + `*_out.txt`,
`round20_origcheck.py`. Run logs: `C:\FWC10B\xenia_dbg\run_r21_gpr11_eq_6C6B8.log`,
`run_r21_gpr3_ne_0.log`.

## Item 1 - the conditional-breakpoint oracle was broken; the right oracle says `r3 == 0` in Xenia

### 1a. Mechanism, from the Xenia source (VERIFIED, read this round)
`xenia-canary/canary_experimental`:
* `src/xenia/cpu/ppc/ppc_hir_builder.cc:202` `PPCHIRBuilder::MaybeBreakOnInstruction(address)`:
  `if (address != cvars::break_on_instruction) return;` then
  `if (cvars::break_condition_gpr < 0) { DebugBreak(); return; }`; otherwise
  `left = LoadGPR(gpr)`, `right = LoadConstantUint64(value)`, both `Truncate(.., INT32_TYPE)` when
  `break_condition_truncate`, then
  `TrapTrue(CompareEQ/NE/SLT/SLE/SGT/SGE/ULT/ULE/UGT/UGE(left, right))`; any other op string ->
  `assert_always()`.
* `ppc_hir_builder.cc:541` `Value* PPCHIRBuilder::LoadGPR(uint32_t reg) { return
  LoadContext(offsetof(PPCContext, r) + reg * 8, INT64_TYPE); }` -> the compared operand is the
  **guest PPCContext GPR, 0-based**.
* `src/xenia/cpu/hir/hir_builder.cc:840-858`: `Trap(trap_code)` -> `OPCODE_TRAP`;
  `TrapTrue(cond, trap_code)` -> `OPCODE_TRAP_TRUE` (constant-folded: a constant-true condition
  becomes an unconditional `Trap`).
* `src/xenia/cpu/backend/x64/x64_emitter.cc:403` `DebugBreak() { db(0xCC); }` = an **inline int3 in
  the JIT page**. But `x64_emitter.cc:441` `Trap(0)` -> **`CallNative(TrapDebugBreak, 0)`**, and
  `x64_emitter.cc:431` `TrapDebugBreak` does `XELOGE("tw/td forced trap hit! This should be a
  crash!")` and then `if (cvars::break_on_debugbreak) xe::debugging::Break();`.

**Consequence.** The unconditional path (`break_condition_gpr = -1`) int3s and is countable; the
**conditional** path never int3s - it emits a native call that only logs (it int3s only when
`break_on_debugbreak` is true, which Round 17 deliberately set **false** in the copy). So counting
int3 cannot see a conditional hit at all, and *every* "conditional breakpoint = 0 hits" measurement
in Rounds 17-20 measured an artefact. The correct oracle is the log line, which `TrapDebugBreak`
emits unconditionally.

### 1b. The two control runs (VERIFIED)
Config-file delivery (anchored byte-regex + read-back of all five keys before launch; 65,973 B and
65,962 B), `break_on_instruction = 2194397196` (`0x82CBD80C`), `break_condition_truncate = true`;
80 s each (wall 154.0 s / 132.4 s), copy only, our debugger attached (int3 count). The file's
condition lines were re-read after each run and still held the patched values (Xenia rewrites its
config with the loaded in-memory values), corroborating that they were applied. Logs re-read after:

| run | condition | int3 hits | `tw/td forced trap hit!` lines |
| --- | --- | --- | --- |
| Round 21 run 1 | `r11 == 0x6C6B8` | 0 | **3,873** |
| Round 21 run 2 | `r3 != 0` | 0 | **0** |
| Round 17 run A (no condition, 100 s) | - | 5,029 | 0 |
| **Round 17 run B (existing log, re-read now)** | `r3 == 0` (CLI) | 0 | **3,618** |
| Round 17 run C (no condition, 80 s) | - | 3,674 | 0 |

`r11 == 0x6C6B8` is **provably true** at that instruction: the decode of `sub_82CBD7E0` is
`0x82CBD7F4 bl 0x832BF128` (`lwz r3, 100(r3)`) -> `0x82CBD7F8 addis r11, r0, 6` ->
`0x82CBD804 ori r11, r11, 0xC6B8` -> `0x82CBD80C lwzx r28, r3, r11` (VERIFIED). So run 1 is a true
positive: the mechanism fires, and `LoadContext` sees live values at that point (r11 is read as
exactly what the two preceding instructions set, so there is no staleness hole). Run 2 is its exact
negation: 0. Therefore **at every execution of `0x82CBD80C` in Xenia, `r3 == 0`** - independently
confirmed by Round 17's run B (3,618 x `r3 == 0` true).

The counts are condition-driven, not guest `tw`/`td` traps: runs A and C (no condition, same content,
same length) produce **0** such lines, and the only difference in the condition runs is the
condition.

### 1c. What this does to the Round 20 contradiction
Explanation (1) (a second writer fills `+0x64`) is **dead** and explanation (2) is **confirmed**: the
field is 0 in Xenia too, the guest takes the same null-field read, and the runtimes differ only in
what happens to guest virtual `0x6C6B8`. Round 20's "the producer never runs" and Round 21 item 3's
"no writer exists" are now consistent with a *tolerated* null read rather than a missing value.

Xenia commits on demand during these runs - `BaseHeap::AllocFixed attempting commit on unreserved
page` **x3** in each 80 s log and **0** "access violation" lines - i.e. Xenia's guest AVs are routine
and recovered, while ours are fatal.

## Item 2 - the `--debug` GUI route (for the user; now a confirmation, not the decider)

The question it was built for is already answered by the log oracle (1b), so this is a
screenshot-level confirmation plus one genuinely new datum: what Xenia has at guest `0x6C6B8`.

Preconditions in `C:\FWC10B\xenia_dbg\xenia-canary.config.toml`: `[General] debug = true`;
`[CPU] break_on_instruction = 2194397196` (`0x82CBD80C`); `break_on_start = false`;
`break_on_unimplemented_instructions = false`; and **`break_condition_gpr = -1`** - a condition must
NOT be set, because a conditional breakpoint emits no int3 at all (item 1a). Alternative, if the GUI
should stop on the conditional path itself: keep `break_condition_gpr = 3`, `op = "eq"`, `value = 0`
and set `break_on_debugbreak = true`, which turns the trap into `xe::debugging::Break()`.

Command (this one is the user's to run - we must not launch the GUI ourselves):

```
cd /d C:\FWC10B\xenia_dbg
xenia_canary.exe "D:\FWC10\2010 World Cup.iso" --log_file=C:/FWC10B/xenia_dbg/gui_r21.log --log_level=3 --debug
```

Steps once it stops (the `break_condition_gpr = -1` path int3s *before* executing the guest
instruction, so the reported PC is `0x82CBD80C` and the register values are the incoming ones):
1. Read the PPC pane: `r3` and `r11`. Expect `r11 = 0006C6B8` and `r3 = 00000000`.
2. Memory pane, address `83A4648C`, 4 bytes, big-endian -> that word is the singleton pointer `P`
   (expect a non-zero `B...` value). Then address `P + 0x64`, 4 bytes -> that must equal `r3`
   (expect `00000000`).
3. **The new datum:** memory pane at `0006C6B8`, 4 bytes, big-endian - that is exactly what the
   `lwzx` returns in Xenia (expect `00000000`). If the pane offers a physical view, read physical
   `0x6C6B8` too.
4. Screenshot the PPC pane plus reads (2) and (3).

## Item 3 (VERIFIED, static, ~30 min box) - no writer of `singleton+0x64` exists in either image

Scanned `xexdump\fifadllzf.dec.bin` (base `0x82300000`) and `xexdump\default.dec.bin` (base
`0x82000000`) together with the guest's static function-extent table (92,058 entries,
`0x82050000..0x838D85BC`; 87,183 of them inside fifadllzf).

Origins of the singleton pointer (the only ways to obtain it):
* `lis rX, 0x83A4` sites: **5,471**; of those, `lwz rD, 25740(rX)` ("slot reads"): **176** (forward
  window from the `lis`) / **353** (backward window from the `lwz`); `stw rS, 25740(rX)` ("slot
  writes"): **exactly 3**:
  * `0x82C6AFF8` in the publish `0x82C6AFC8` - **sets** it. Body decoded:
    `addi r3, r0, 196; bl 0x82A64018` (alloc 0xC4) -> `cmpli r3, 0; bc 12,2,..` (alloc-failure arm)
    -> `bl 0x82C50EF0` (ctor) -> `addis r11, r0, -31836; stw r3, 25740(r11)`.
  * `0x82C6B008`, in the same function's tail: `addi r11, r0, 0` -> `stw r11, 25740(r10)` =
    **clears**.
  * `0x82C86108` in `0x82C860C8` (destroy path: `lwz r31, 25740(r30)`, tests it, calls a teardown,
    then `li r11, 0; stw r11, 25740(r30)`) = **clears**.
  The getter used by the code we fault in, `0x82C501D0`, is `addis r11, r0, -31836;
  lwz r3, 25740(r11); blr` (VERIFIED) - the same slot; the `+0x64` field is then read by
  `0x832BF128` = `lwz r3, 100(r3); blr`.

Ways to write `singleton+0x64` that the old `stw rX,100(rY)`-shaped search could miss - all nets came
back empty:

| net | count scanned | with a provably-singleton base |
| --- | --- | --- |
| `stw/stwu/stb/sth/stfs/stfd` with displacement `0x64` | **5,368** | **0** |
| indexed stores (`stwx/stwux/stbx/sthx/stfsx/stfdx/stwcx.`), incl. index = constant 100 | **11,343** | **0** |
| `stmw` whose register span covers `+0x64` | 4,530 (11 covering) | **0** |
| `bl` with size arg (r5) = 100/196/`0x6C6D0` within 4 instructions | 146 (6 of them 196) | **0** |
| inlined block copies of >=20 words covering `+0x64` | 86 candidates | **0** |

The six 196-byte size-arg callers (`0x82CBEBE0`, `0x82CBF6F0`, `0x82E57CFC`, `0x82E57D0C`,
`0x82E57D4C`, `0x82ECB4C8`) all have r3 = addi/const/call, never the singleton.

Forward net (the directly-answering one): from **every** site that obtains the pointer (**2,981**
origins = 353 slot reads + 2,628 `bl 0x82C501D0`), follow it forward 48 instructions (tracking
`mr`/`or`, `addi` offsets, invalidating at calls and on redefinition) and list every store it
reaches: **13 stores, all at displacements 0x94/0x95/0x96/0x98/0x9C/0xA0/0xA8 - none at `0x64`,
none indexed**. The same walk reports every `bl` reached with the pointer in r3/r4/r5: **2,617
calls, 0 with an offset of `0x64`** (top callees `0x832BF0D0` x424, `0x832BF128` x295 - the `+0x64`
accessor itself, `0x83325928` x279, `0x82BD2A28` x276, `0x832BF0E8` x206). So there is no
`memcpy`/`memset(singleton+0x64, ...)` either.

**Conclusion: no store to `singleton+0x64` exists anywhere in either image, so the field is 0 in any
faithful execution of this code** - exactly what Xenia measures (item 1) and what our build shows.
Round 19's "producer identified statically" is doubly superseded: the writer it named stores into
`+0x64` of a *different* object (Round 20), and the real `+0x64` has no writer at all.

Also decoded this round, for the fault chain: `r28` is **not** dead - `0x82CBD8FC mr r4, r28` ->
`0x82CBD918 bl 0x82D3A108` - so whatever Xenia reads at guest `0x6C6B8` is passed as a call argument;
the read only stays harmless if that value is benign (expected 0; INFERRED until item 2 step 3 is
read).

## Item 4 - proposal (nothing run): prove the page, then fix the runtime's virtual-heap fault path

Root cause, with citations from our own runtime (VERIFIED by reading the source):
* `ReXGlue\src\system\xmemory.cpp:177-201` - `virtual_membase_ = mapping_base_`,
  `physical_membase_ = mapping_base_ + 0x100000000`; heaps `v00000000`/`v40000000` are
  **`kGuestVirtual`** (guest `0x00000000`/`0x40000000`), `v80000000`/`v90000000` are `kGuestXex`,
  the physical heap at `physical_membase_` plus `0xA0000000`/`0xC0000000`/`0xE0000000` are
  `kGuestPhysical`. Guest `0x6C6B8` -> `v00000000`, type `kGuestVirtual`.
* `xmemory.cpp:534-551` `Memory::AccessViolationCallback`: for a fault inside
  `[virtual_membase_, physical_membase_)` it looks the heap up and
  `if (!heap || heap->heap_type() != memory::HeapType::kGuestPhysical)` logs `Unhandled guest access
  violation: ...` and **returns false** (fatal). The only on-demand commit path is
  `xmemory.cpp:1013` (`!has_committed && heap_type_ == kGuestPhysical && ...`).
* Our codegen reads through `base + guest` (`REX_LOAD_U32`), so this read lands at host
  `0x1_0006_C6B8` in the *virtual* heap, and that page was never committed; the runtime's only
  recovery arm is gated to `kGuestPhysical`. Xenia instead walks the guest page table from a
  virtual-heap fault and commits the physical page (its recurring
  `BaseHeap::AllocFixed attempting commit on unreserved page`).

Proposed experiments, smallest first (each needs the user's go-ahead; none is a rebuild):
1. **Read-only probe (cheap, decisive for the diagnosis), our build + our debugger:** on the
   first-chance AV for `read of guest 0x6C6B8`, `VirtualQueryEx` the faulting page
   (`0x1_0006_C000`) and a neighbouring page known to be live (e.g. the singleton's
   `0x1_83A4_6000`) and report `State`/`Protect`. Expect the fault page `MEM_RESERVE` and the live
   page `MEM_COMMIT` -> proves "uncommitted, not unmapped", i.e. a commit-policy difference.
2. **Fault-injection (how far does the guest get?):** in the same debugger, when the AV is a read in
   `[virtual_membase_, physical_membase_)` whose page is `MEM_RESERVE`, do
   `VirtualAllocEx(hProc, page, 0x1000, MEM_COMMIT, PAGE_READWRITE)` and continue (`DBG_CONTINUE`;
   the read re-executes). Keep the four `PPCFuncMappings` DRs armed to see how far execution goes.
   Cap it (e.g. <= 32 pages), then stop and report. Risks: it masks the real defect; a zero-filled
   page fabricates state (Xenia's value is probably also 0, but that is an assumption); more pages
   may fault as the guest walks a structure; it can collide with the runtime's own bookkeeping of
   reserved/committed ranges; the protection may need to match what the codegen expects; and if the
   runtime's own handler makes the AV fatal before we see it the experiment is moot (Round 20
   verified that we *do* see first-chance AVs, so it is not moot).
3. **The actual fix (needs approval + rebuild):** give the virtual heaps the same on-demand commit /
   page-table-mapping recovery that `kGuestPhysical` already has - i.e. drop or widen the
   `heap_type() != kGuestPhysical` guard (or add a virtual-heap arm that commits the page). That is a
   runtime change of a few lines, not an override and not game data. Which arm is correct depends on
   whether the runtime maintains a guest page table for the low virtual range; the codegen's identity
   `base + guest` read suggests the low range is meant to be identity-mapped, in which case
   committing on demand would be sufficient.

Nothing else in Rounds 7-20 is withdrawn, except the two claims explicitly marked retracted above
(Round 17's `r3 != 0`, and Round 19's "writer identified").

**Copy state left behind.** After the two runs, the copy's `[CPU]` breakpoint cvars were restored to
the shipped reference values (`break_on_instruction = 0`, `break_condition_gpr = -1`,
`break_condition_op = "eq"`, `break_condition_value = 0`, read back); `break_on_debugbreak = false`,
`break_on_unimplemented_instructions = false` and `[General] debug = true` are left as the copy's
working set from Rounds 16-17. The read-only reference `D:\FWC10\xenia` was never written
(`diffs = 0`).

---

# Round 22 - probes 1-2 (measured), the proposed runtime change (not applied), upstream check

Box: 45 min, as agreed. **Nothing was rebuilt; nothing in the SDK was modified.** The only host writes
are the two `worldcup2010.exe` runs under our own debugger, their runtime logs, the patch file and the
backup directory listed below.

## Item 1 - probe 1: page state on the first-chance AV (VERIFIED)

Tool `round22_probe.py probe1 25` (our build under `DEBUG_ONLY_THIS_PROCESS`, DR0-DR3 armed on the four
Round-20 entry points, cwd `dist\Output`, no commit). Log: `C:\Users\<user>\AppData\Local\Temp\opencode\r22_probe1.txt`.

- AV #87/#88 (same address, twice): `tid=7184 pc=0x7FFCA122D096 read fault=0x10006C6B8
  guest=0x0006C6B8 LOW-VIRT`.
- `VirtualQueryEx` of the faulting page `0x10006C000`:
  `base=0x10006C000 alloc=0x100000000 allocprot=PAGE_READWRITE size=0x2FF94000
  MEM_RESERVE/0/MEM_MAPPED`.
- `VirtualQueryEx` of `0x100000000` (guest 0), for contrast:
  `base=0x100000000 alloc=0x100000000 allocprot=PAGE_READWRITE size=0x10000
  MEM_COMMIT/PAGE_NOACCESS/MEM_MAPPED`.
- Arena base derived from the fault = `0x1_0000_0000`, matching the runtime's own startup line
  (`Guest memory arena mapped: virtual base 0x0000000100000000, physical base 0x0000000200000000`
  in `worldcup2010_009.log`) - now VERIFIED from two independent sources.
- Exit `0xC0000005`, ~5.4 s wall (~3.6 s to the AV). DR hits: **0** (same as Round 20).

Reading: **(a)** the fault page is **MEM_RESERVE inside the MEM_MAPPED arena view** - the 4 GB arena is
a `SEC_RESERVE` file mapping ("all reserved but uncommitted", `xmemory.cpp:137-149`), so an uncommitted
page is host-*reserved*, not merely page-protected; a `Protect`-only recovery cannot fix it (the page
would keep faulting). **(b)** the fault page's whole region up to the end of the 1 GB view is one
767 MB (`0x2FF94000`) reserved block, so the runtime has **< 432 KB** of `v00000000` committed (the
eager 64 KB plus ~368 KB of early guest allocations): the guest never committed the block containing
`0x6C000`. **(c)** the "live" page picked (guest 0) is `PAGE_NOACCESS` because of `protect_zero` - a
better live-page pick would be guest `0x80000000`.

## Item 2 - probe 2: commit the page, continue, keep the DRs armed (VERIFIED)

Tool `round22_probe.py probe2 100`; log `r22_probe2.txt`; runtime log `worldcup2010_010.log`.

- One page fixed, on the first and only low-virtual fault:
  `>>> fixed page 1: host 0x10006C000 guest 0x0006C6B8 via VirtualAllocEx(MEM_COMMIT,RW) ;
  4B at fault addr = 0x00000000 (guest BE 0x00000000)`.
  `VirtualProtectEx` was not applicable (the region is `MEM_RESERVE`), so the `MEM_COMMIT` path ran.
- Continued (`DBG_CONTINUE`); the four DRs were re-armed on every `CREATE_THREAD` (DR hits still **0**).
- **How long it ran:** the old crash point is ~3.3 s; with the page committed the process ran **~33 s**
  and exited by itself (`exit reason=exit`, not the deadline). Runtime log `21:14:21.7 .. 21:14:54.8`
  shows real progress (`d:\data\loc\eng_us_upd.db`, `d:\BigFile_CheckpointA`).
- **What stopped it** - a different, later wall:
  `[cpu] INVALID INDIRECT CALL: target=83884CA0 LR=838852BC CTR=83884CA0 r1=708EE940 r2=BAADF000
  r3=B414C1A0 r11=B40ADEE0 r12=83886630`, then
  `[critical] [core] [FATAL] Call to invalid or unregistered function at guest address 0x83884CA0`,
  exit `0xC0000409`. That is the missing-recompiled-function class, not a memory fault.
- Fault inventory for the whole run: 2,280 AVs = 2,279 physical-alias **writes** (the runtime's own
  watch mechanism, `guest 0xB3E....` in `vA0000000`, passed through unchanged) + **1** low-virtual
  read (ours). No other guest-virtual page needed a commit.
- The 4 bytes the guest's `lwzx` loads at `0x6C6B8` after the commit read back as **0** (`r28 = 0`).

So: **yes, it gets past the old crash point**, by ~30 s, and then stops at unrecompiled guest
`0x83884CA0`. This is a *probe* result (a raw `VirtualAllocEx` in the debuggee), not a runtime fix.

## Round 21's causal claim is RETRACTED (VERIFIED from source)

Round 21 (and this file's header before this round) said Xenia survives because "a fault in its virtual
heap walks the guest page table and lazily commits the page (`BaseHeap::AllocFixed attempting commit on
unreserved page`, 3x per 80 s run)". **Wrong on both parts.**

- Xenia's own `Memory::AccessViolationCallback`
  (`xenia-canary/canary_experimental src/xenia/memory.cc:598-624`) has the identical early-out -
  `if (heap->heap_type() != HeapType::kGuestPhysical) return false;` - followed only by
  `PhysicalHeap::TriggerCallbacks`. It cannot commit a virtual page. Our version is that same code plus
  the arena-base log line upstream added in `bc34338135`.
- The 3x `attempting commit on unreserved page` per Xenia run are **kernel-init allocation lines**, not
  the guest read: in `run_control_82CBD80C.log` all three sit adjacent at log offset `00000EDC`, next to
  `HostPathDevice::ResolvePath()` and `Added handle:F8000000 for class xe::kernel::XObject`. Our runtime
  logs that warning **0** times in any run (`dist\Output\logs\*.log`) because ReXGlue's init allocates
  differently - a startup difference, not the fault.
- Xenia's `BaseHeap::AllocFixed` does tolerate a commit-only call on an unreserved page and promotes it
  (`memory.cc:1118-1124`); our file has the same code at `xmemory.cpp:1377-1384`. That promotion is not
  the missing piece either.
- `ShouldSkipHostCommit` (`memory.cc:106-116`) returns true only when the **host** page size > 4 KB
  (macOS/ARM), so on Windows both runtimes do host commits.

What remains: Xenia must have `0x1_0006_C000` host-committed at that moment (its AV path cannot
recover it, and Round 17's oracle shows that instruction executing 3,618-5,029 times per run without
dying), but **which code commits it is still UNKNOWN**. Two candidates, both outside `xmemory.cpp`:
(i) an HLE/allocation path in Xenia's kernel that commits low-heap pages, where ReXGlue's equivalent
differs; (ii) a difference in how the arena section/view is created. One cheap decisive probe is listed
under "Next".

## Item 3 - proposed runtime change (PROPOSAL ONLY, not applied, not built)

Patch: `D:\FWC10\world-cup-2010-pc-port\patches\round22_xmemory_guest_virtual_commit.patch`
(4,389 B, LF, SHA-256 `9A80434CFC00BE2F36FD9C1E87EABEFF2E7FFD025F42123CBE85B24536971EF1`), against
`ReXGlue\src\system\xmemory.cpp` (97,533 B, LF, SHA-256 `9B5319DC...CF1A3`). Two hunks: `#include
<atomic>`, and one block at the top of `Memory::AccessViolationCallback`. Verified as a real patch:
applied to a pristine copy of the current file with `git -c core.autocrlf=false apply -p1` -> exit 0,
and the result is **byte-identical** to the intended file (101,208 B). It is **not** applied to the
checkout.

Design, as requested (on-demand commit for `kGuestVirtual`, safe scope, one log line per page, fatal
path kept):

- **Scope:** only `heap_type() == kGuestVirtual` **and** `virtual_address` inside that heap. `kGuestXex`
  (XEX image) faults and everything physical stay on the existing path, which still ends in
  `Unhandled guest access violation` + `return false`.
- One page, aligned to `heap->page_size()` (4096 for `v00000000`; 64 KB for `v40000000`, which is how
  `AllocFixed` already behaves).
- **Commit:** `BaseHeap::AllocFixed(page, size, size, kMemoryAllocationCommit, read|write)` - commit-only,
  exactly what a guest commit call does; on a reserved page it commits in place, on an unreserved page it
  takes the existing "attempting commit on unreserved page" promotion. Because the request is
  commit-only, the region-descriptor rewrite at `xmemory.cpp:1406-1413` is skipped for pages that are
  already reserved, so a page inside a larger reserved region is not corrupted.
- **Zero-filled:** first touch of a `SEC_RESERVE` page is zero-filled by the OS - verified in probe 2
  (the fresh page read 0). No `memset` is inserted on purpose: `BaseHeap::Decommit`
  (`xmemory.cpp:1558-1580`, from Xenia's `memory.cc:1383-1412`) deliberately leaves the host page intact
  ("mapped memory cannot be decommitted"), so Xenia returns the *old* bytes after a decommit+recommit;
  a blanket `memset` would diverge from that.
- **Thread-safe:** the callback already runs holding the global critical region (a `std::recursive_mutex`,
  `xmemory.h:270-271`), and `AllocFixed` re-takes it plus `heap_mutex_`; recursive re-acquisition on the
  same thread is safe and is what the existing `PhysicalHeap::TriggerCallbacks` path does. The counter is
  a file-static `std::atomic<uint32_t>` (one runtime per process).
- **Bounded + logged:** limit 4096 pages (16 MB of 4 KB pages) per process; at the limit, or if
  `AllocFixed` fails, it logs `REXSYS_ERROR` and falls through to the existing fatal path. Every committed
  page logs `REXSYS_WARN("Guest virtual {read|write} of 0x... (host 0x...) committed on demand as page
  0x... (first touch|recommit); total N")`.
- **Not a cvar:** keeping it `constexpr` keeps the patch to one file (the cvar registry is generated
  elsewhere). Promote to a `REXCVAR_GET` kill switch if wanted.

**Which variant matches Xenia, and how Xenia differs.** Honest answer: Xenia has **no on-demand commit
for virtual heaps at all**; this variant is a behavioural approximation of Xenia's *observable* result
(the guest read succeeds and returns the page's contents, which for a never-written page is 0), not a
copy of a Xenia code path. It is the same shape the runtime already uses for the eagerly committed
regions of the same heap (`Memory::Initialize` commits the first 64 KB of `v00000000` and the whole
GPU/physical windows up front) - i.e. one page moves from "fatal" to "committed like the others". It does
*not* explain why Xenia's committed set is larger than ours; that stays the open root-cause question above.

Risks, ranked:

1. **Silent divergence if Xenia's page is not zero.** We fabricate a zero page; probe 2 shows our guest
   reads 0. If Xenia's `0x0006C6B8` is non-zero, the guest will diverge later. Settled by the optional
   GUI read (item 6) or a Xenia-side `VirtualQueryEx`.
2. **Masking a real bug.** If the guest asked the runtime to commit that page and the request was lost,
   the honest fix is in that path and this patch hides it. Probe 1 shows the page table says "never
   reserved" (no request recorded), which is also consistent with a lost request.
3. **`v40000000` (64 KB pages):** a fault there commits 16 host pages at once - correct, but a wild
   pointer could commit a 64 KB granule per fault. The cap and the per-page log line make it visible.
4. **Cost:** one AV + commit per touched page, once. Zero for already committed pages.
5. **Semantics:** the guest's page table stays "unreserved" for the committed page; a later guest
   commit/`AllocFixed` promotes it normally (and decrements `unreserved_page_count_`), so bookkeeping
   stays consistent; `Decommit`/`Release` are unaffected. A `Protect`-only recovery variant was
   considered and **rejected**: the page is `MEM_RESERVE`, so restoring protection cannot make it
   accessible - the guest would fault forever (probe 1).

## Item 4 - backup before any SDK change (done: SHA-256 + timestamped)

`D:\FWC10\_backups\20261017-212022\` (also appended to `LAST_BACKUP.txt`): `xmemory.cpp.before`
(97,533 B, `9B5319DC...CF1A3`), `round22_xmemory_guest_virtual_commit.patch` (`9A80434C...71EF1`),
`git-HEAD.txt` (`c94f5eb`, branch `main`), `git-status-porcelain.txt` (the checkout's 90
modified/untracked entries), `README.txt`, `SHA256SUMS.txt`.
The SDK was **not** modified: `xmemory.cpp` SHA-256 unchanged (`9B5319DC...CF1A3`), `git status` still 90
entries, HEAD still `c94f5eb`. `dist\Output\worldcup2010.exe` (8,022,528 B, 17:53:04Z) and
`worldcup2010_fifadllzf.dll` (123,051,520 B, 17:52:58Z) are untouched. `D:\FWC10\xenia` re-verified after
the box: 17 files, sizes + UTC mtimes identical to `round17_orig_inventory.txt` (`diffs = 0`).

## Item 5 - does newer upstream ReXGlue handle this? No (VERIFIED)

- The pinned `c94f5ebdcb3c9d1a460ca48e04f9758448f8d518` ("Release v0.10.0", 2026-08-21T22:11:28Z) **is the
  current upstream tip**: `GET /repos/rexglue/rexglue-sdk/commits?per_page=1` returns exactly that SHA.
- The raw file at both `main` and `master`
  (`raw.githubusercontent.com/rexglue/rexglue-sdk/{main,master}/src/system/xmemory.cpp`, fetched
  2026-10-17, both 96,520 chars) still contains the fatal early-out
  `if (!heap || heap->heap_type() != memory::HeapType::kGuestPhysical) { REXSYS_ERROR("Unhandled guest
  access violation: ..."); return false; }` - identical to ours in that function.
- `GET /repos/rexglue/rexglue-sdk/commits?path=src/system/xmemory.cpp`, newest entry:
  `bc34338135 fix(system): report the guest arena base and unhandled access violations` (2026-08-14) -
  the *last* change to this file is the one that added the "Guest memory arena mapped: virtual base ...
  physical base ..." line we now see in our own logs; nothing after it, and nothing that handles
  `kGuestVirtual` faults.
- Our local file is 44 lines larger than upstream's, and that difference is the pre-existing local work
  in `InitializeFunctionTable`/`DestroyFunctionTable` (`git diff --stat`: 61 insertions / 17 deletions),
  unrelated to this fault.

Conclusion: there is no upstream fix to port; the change must be ours.

## Item 6 - optional GUI (`--debug`) - still not run

Unchanged from Round 21; the one thing it would add that now matters most is the **value Xenia has at
guest `0x0006C6B8`** (risk 1). Command and key list are unchanged (Round 21 item 2).

## Verification vs inference (this round)

- **VERIFIED:** the fault page's host state (`MEM_RESERVE/MEM_MAPPED`, `alloc=0x1_0000_0000`) and the
  767 MB reserved region after it; the arena base (probe + runtime log); that exactly one guest-virtual
  page needed a commit; the zero value read; ~33 s of progress; the new stop (`0x83884CA0`, exit
  `0xC0000409`); Xenia's AV callback source; that Xenia's 3 warning lines are kernel-init; that the patch
  applies byte-identically; that the SDK, `dist\Output` and `D:\FWC10\xenia` are unchanged; that upstream
  has no fix.
- **INFERRED:** that Xenia's page is committed (strong: its AV path cannot recover it and thousands of
  executions of that instruction complete); that the guest reads 0 there in Xenia too (follows from a
  fresh-commit zero page plus "no writer", but not measured in Xenia).
- **UNKNOWN:** what commits that page in Xenia; whether the post-fix stop at `0x83884CA0` is the natural
  next blocker or an artefact of the fabricated zero page.

## Next (needs your call)

1. `0x83884CA0` is a *missing recompiled function* - the normal override/codegen question, not a memory
   question. Not touched. Round 14's override tooling is the route.
2. Cheap decisive probe for the remaining unknown: in our runtime log every `BaseHeap::AllocFixed`/`Alloc`
   call whose guest range lies in `v00000000`, and `VirtualQueryEx`-enumerate the low view's committed
   regions at the moment of the fault; then do the same page check on the Xenia side.
3. The fix itself: on your word I apply the patch and rebuild (~860 s, codegen ~395 s); the
   `D:\FWC10\_backups\20261017-212022` backup is already in place.

## Tooling note (reusable)

`round22_probe.py` (our-build debugger + DRs + AV handling) had a first-version bug worth remembering: in
a `DEBUG_EVENT` the exception record starts at offset **16** (the union is 8-byte aligned, 4 bytes of
padding after `dwThreadId`), so `EXCEPTION_RECORD.ExceptionInformation[0]` is at **+48** and `[1]` at
**+56** - not +40/+48 (those are `NumberParameters` / `info[0]`); the first run therefore read the access
*type* as the address and saw nothing. Fixed and re-run; both logged results above are from the fixed
build. Also: `powershell > file` writes UTF-16 (use `cmd /c` or `Out-File -Encoding utf8`).


# Round 23  (2026-10-17, single 45-min box, exactly one rebuild)

## Item 1 - is `0x83884CA0` real code reached through a vtable?

**Answer: yes on both counts; override entry added.**

Decode (`round23_target.py`, `round23_chain.py`, `round23_site.py` over the mapped-layout dump):

- `0x83884CA0` is inside `fifadllzf` `.text` (exec), 4-byte aligned, section offset `0x1234CA0`.
- Not a registered entry: absent from 87,183 `fifadllzf_xex` starts, 92,058 `round19_entries.json` dump,
  279 override entries, Stage-6b/6c backups.
- CFG extent `0x83884CA0..0x83884CEC`, 19 insns, class `leaf`, no runaway; every path ends at the
  single `blr` at `0x83884CE8` (four exit branches target `0x83884CEC`). No registered entry strictly
  inside. Previous registered `0x83884BA8` ends exactly at `0x83884CA0`. Next registered `0x83884CEC`
  is a 2-instruction function (`addi r3,r9,1` / `blr`), so `end` is exclusive there.
- Body: 16-bit character scan (`mr r9,r5` / loop `lhzu r11,-2(r10)` / checks for 32/45/10/13 /
  `mr r3,r5` / `blr`).
- **Pointer provenance**: unique `lis r9,0x8388` / `addi r9,r9,0x4CA0` at `0x836D3320/24`; stored
  `stw r9,36(r11)` (`obj+0x24`) at `0x836D3354`. Crash call site `0x838852B8` loads
  `*(this+0x44)` → `r11`, then `*(r11+0x24)` → `r9`, `mtctr`/`bctrl`. No 32-bit occurrence of the
  value anywhere in either image; no direct `bl` to it.
- Not an artefact of the zero page: the target is a constant built by `lis/ori`, not a value read from
  the fabricated page (that would be 0).

Entry added (both template + workspace, identical SHA-256 `D69ADAA0...5684A`, 13,962 B):
`"83884CA0" = { end = 0x83884CEC }` (Stage 6e block in `fifadllzf_overrides.toml`).

Mechanical validation (`round23_overlap.py`): 280 entries parsed; new range `0x83884CA0..0x83884CEC`;
overlapping override entries: **none**; registered starts inside: **none**; nearest registered below
`0x83884BA8` / above `0x83884CEC`; no direct branch to it; endpoints 4-byte aligned in executable `.text`.

Residual risk (INFERRED): the four exit branches target `0x83884CEC` (a *registered* function) —
this body tail-jumps into a neighbour; ReXGlue's codegen must model those edges as cross-function
branches. The alternative `end = 0x83884CF4` would cover the shared block but *overlap a registered
function*, which was ruled out.

## Item 2 - apply workaround + override, rebuild, boot, report

**Patch applied:** `round22_xmemory_guest_virtual_commit.patch` (SHA-256 `9A80434C...EF1`) to
`ReXGlue/src/system/xmemory.cpp` (pre-patch 97,533 B, post-patch 101,208 B, SHA-256
`48D8EF09...BE9`). Backup: `D:\FWC10\_backups\20261017-213039-r23` (xmemory.cpp.before, both override
copies, BuildWorldCup2010.ps1, git HEAD/status, SHA256SUMS, README).

**Rebuild:** VS 18 x64 env + VS-bundled CMake/Ninja + LLVM clang; `powershell -ExecutionPolicy Bypass
-File Installer\BuildWorldCup2010.ps1 -GameData ... -Workspace C:\FWC10B\fwc10stage4 -SourceBuild
-Jobs 2`. **Wall time 437 s** (codegen 392.7 s, compile ~44 s), exit 0.

**Verification:**
- Workaround strings **present in `rexruntime.dll`**: `committed on demand as page`,
  `on-demand commit limit`, `on-demand commit failed`, `Unhandled guest access violation`.
- New override function **present in generated sources**: 4 files (`worldcup2010_funcs.h`,
  `worldcup2010_init.cpp`, `worldcup2010_recomp.174.cpp`, `worldcup2010_register.cpp`).

**Boot** (`worldcup2010.exe`, 48.3 s, exit `0xC0000409`):

```
[2026-10-17 21:42:36.137] [warning] [sys] [t11168] Guest virtual read of 0x0006C6B8 (host
  0x000000010006C6B8) committed on demand as page 0x0006C000 (first touch); total 1
```

Exactly **one page** committed on demand (0x6C000). Game loads XEXs, starts APU/GPU, processes XAM/XContent
traces, then stops at a **new unregistered indirect call**:

```
[2026-10-17 21:43:19.941] [error] [cpu] [t16140] INVALID INDIRECT CALL: target=836A24B0
  LR=836BDA64 CTR=836A24B0 r1=7019EE40 r2=00000000 r3=7019EFA0 r11=00000001 r12=836BDC30
[2026-10-17 21:43:19.941] [critical] [core] [t16140] [FATAL] Call to invalid or unregistered
  function at guest address 0x836A24B0
```

**Progress:** the `0x83884CA0` blocker is resolved; the game now runs ~48 s (vs 33 s with the patch
alone, vs 3.3 s before the patch). The new target is a 4-instruction tail fragment (see below).

## Item 3 - Xenia level-3 log investigation (no run)

Scanned all 15 logs in `C:\FWC10B\xenia_dbg` (`round23_xlog2.py`). Every log identical shape:
12 `NtAllocateVirtualMemory` matches (= 5 guest call/return pairs + 2 kernel import lines), 3
`BaseHeap::AllocFixed attempting commit on unreserved page`, 3 `AllocFixed`, ~1,700
`MmAllocatePhysicalMemoryEx`. (Note: the thread-id after `w>`/`d>`/`F>` is the **host thread id**,
not a log offset; differs per run.)

**Guest virtual allocations** (all five calls before any `0x82CBD80C` execution; the log has 0 hits
for `82CBD80C` so ordering by it is impossible, but the 3 warnings precede all five):

| call | base | size | type | prot | result | notes |
|------|------|------|------|------|--------|-------|
| 1 | 0 | 0x100000 | 0x60002000 | 0x4 | 0x40000000 | reserve 1 MB, 64 K pages |
| 2 | 0x40000000 | 0x10000 | 0x60001000 | 0x4 | 0x40000000 | commit 64 KB |
| 3 | 0x40010000 | 0x10000 | 0x60001000 | 0x4 | 0x40010000 | commit 64 KB |
| 4 | 0 | 0x100000 | 0x60002000 | 0x4 | 0x40100000 | reserve 1 MB |
| 5 | 0x40100000 | 0x10000 | 0x60001000 | 0x4 | 0x40100000 | commit 64 KB |

**All land in v40000000 (0x40000000-0x7EFFFFFF, 64 KB pages)** — guest never allocates below
0x40000000. (Our `NtAllocateVirtualMemory` is a faithful port; same placement.)

**Xenia init commits** (source: `xenia-canary/canary_experimental src/xenia/memory.cc`,
`Memory::Initialize`): low heap `v00000000` gets **only 0x0-0xFFFF** (64 KB, `protect_zero` → NoAccess);
physical range pre-committed; GPU writeback at 0xC0000000/0x7F000000; v80000000 0x80000000-0x8003FFFF;
vA0000000 0x340000 reserve top-down. **No init commit covers 0x6C000.**

**The 3 commit-only promotions** occur during `Setup: Initializing Kernel...`, on the main thread,
right after `HostPathDevice::ResolvePath(FFFE07D1.gpd / 454108E4.gpd)` and immediately before
`Added handle:F8000000 for class xe::kernel::XObject` / XThread stacks at `0x70010000-0x70030000`
and `0x70050000-0x70070000`. **INFERRED (strong):** these are the **fixed-address XThread stack
allocations** in the v40000000 heap (0x70010000/0x70050000/0x70090000), because the log shows the
stack addresses immediately after and Xenia excludes 0x70000000-0x7F000000 from the general allocator.
Our runtime logs this warning **0 times**; its stack allocation uses `LookupHeap(0x70000000)->Release`
(`kernel_state.cpp:199-200`) — a placement/method difference in the same heap.

**What could commit 0x6C000 in Xenia and not ours?**
- Nothing in Xenia's **verified** commit set (init + 5 guest allocs + 3 stack promos) covers 0x6C000.
- **INFERRED (prime):** some Xenia-internal fixed-address commit-only `AllocFixed` call (the only
  class of call that can do it) covers 0x6C000. The warning prints no address, so this cannot be
  settled from the log; needs a source-wide search for `AllocFixed(..., kMemoryAllocationCommit, ...)`
  callers or a page check on the Xenia side.
- **INFERRED (alternative):** Xenia's page is uncommitted too, and Xenia never executes the read
  with a null base — i.e. r3 (the `*(singleton+0x64)` value) is non-zero there, and the divergence
  is upstream (the Round 11-21 subject). This reading is now *better supported* because the guest
  never allocates in the low heap and Xenia's init does not touch 0x6C000; it weakens Round 22's
  "Xenia's page is committed" inference, which rested on the assumption that the read in Xenia is a
  null-base read like ours.
- **UNKNOWN:** which. Item 4's GUI read settles it.

## Item 4 - GUI steps to read guest `0x6C6B8` in Xenia

Preconditions in `C:\FWC10B\xenia_dbg\xenia-canary.config.toml` (unchanged from Round 21/22):

```
[General] debug = true
[CPU]     break_on_instruction = 2194397196      # 0x82CBD80C
          break_condition_gpr = -1
          break_on_start = false
          break_on_unimplemented_instructions = false
```

Then:

```
cd /d C:\FWC10B\xenia_dbg
xenia_canary.exe "D:\FWC10\2010 World Cup.iso" --log_file=C:/FWC10B/xenia_dbg/gui_r23.log --log_level=3 --debug
```

The debugger window opens; the game runs. When it breaks at `0x82CBD80C` (`lwzx r28,r3,r11`):

1. **Registers panel**: read **R3** and **R11**. R3 = 0 means Xenia has the same null base as ours;
   R3 != 0 means Xenia's singleton is populated and the read goes elsewhere.
2. **Memory panel**: type guest address `6C6B8` (hex, no `0x`) and read the 4 bytes shown — that is
   the 32-bit guest value (stored big-endian; the panel shows raw bytes).
3. Same panel at `6C000`: if the page is all zeros it is committed-but-zero; a faulted/blank region
   means it is uncommitted.
4. F5 / Continue: it hits thousands of times per run; the second break confirms stability.
5. Report both: **R3** and the **4 bytes at 6C6B8** (screenshot of registers + memory panels).

## Next blocker (Round 24)

`0x836A24B0` — 4-instruction tail fragment (`lwz r11,20(r3)` / `mr r3,r4` / `stw r11,84(r4)` /
`b 0x8369C858`). Previous registered `0x836A2490` (8 insns, `bctr`) ends exactly at it; next
registered `0x836A24C0`. No direct branches, no data hits. Same vtable-reachable pattern. Override
entry `"836A24B0" = { end = 0x836A24C0 }` would be CFG-validated and non-overlapping.

Publishing prepared locally; not yet pushed.
