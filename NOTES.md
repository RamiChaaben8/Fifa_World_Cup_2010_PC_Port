# 2010 FIFA World Cup South Africa – PC Port Notes

## Current State (2026-10-19, after Round 32) - one page

> **Round 32 update (2026-10-19, applied + built + boot-tested).** The 15:13 crash
> (`worldcup2010_025.log`, 58,141 B, 392 lines) is **classification (A): a genuine one-off guest
> fault**, confirmed independently by WER (`Application` event 1000 at 15:13:04: faulting module
> `worldcup2010_fifadllzf.DLL`, code `0xc0000005`, offset `0x5992b2f`; WER minidump
> `CrashDumps\worldcup2010.exe.13020.dmp`, exception record thread 27348, address
> `0x7FFCA40F2B2F`, read of `0x100000021`). **Root cause: our own Round-14 Tier-1 override
> `"8323FB38" = { end = 0x8323FB48 }` truncates the QueryInterface chain of the 288-byte animation
> class after its first `beqlr`, so the generated body returns `this` for every tag. The
> caller's `QI(0xA6C60698)` therefore passes its null check and applies a foreign object layout,
> faulting at guest `0x8333916C` (`lwz r5,0x1C(r9)`, `r9 = 5`). The full chain's default is
> `li r3,0; blr` (return null), and the caller has a proper `if (r29==0) skip` path.
> **Fix applied:** strong-symbol override `sub_8323FB38` in the project sources (patches
> `round32-1` C15455D2 + `round32-2` 9E96A227), one incremental rebuild `BUILD_EXIT_CODE=0`
> (DLL 123,055,616 B, SHA-256 `502744EE...`; mapping entry `0x8323FB38 -> 0x18719C580`; thunk
> `0x8323FBD8` -> the same address). **152 s title-screen boot:** `worldcup2010_026.log`,
> 47,613 B / 282 lines, exactly **one** `ROUND32 QI ... tag=0xA6C60698 self=0xBE2A6CE0 -> null`,
> and **no** `Null-page access` / `Unhandled guest access violation` / `ROUND28 guest context` /
> `FATAL`. **Throw-in test still to be run by the user.** Corrections: the three `8323FB38/6C/8C`
> tier-1 entries are **not standalone stubs**; the Round-14 validator treated `beqlr` as a
> terminator (`8323FB38` and `8323FB6C` truncated; `8323FB8C` is complete). A deeper
> reachability pass also found 10 extents whose interior branch targets `end` (split functions);
> all 10 targets are registered and tail-called, so they are config-incomplete but not the same
> semantic defect. G's primary vptr is
> `0x825218B8` (`0x825218A4` is the `+0x14` secondary). Details in `# Round 32` §8 below.
> **Not pushed; no deletions; `ReXGlue/` read only.**

> **Round 31 update (2026-10-19).** The three Round-30 patches were **applied and built**
> (`patches\round30-1..3`; patch 1 `595C2377...`, 2 `48230F60...`, 3 `B8A0F761...`), with the
> requested additions: the fault block now also dumps `r29`, `G = *(r29+0x2C)` (the getter's return),
> `*(G+0x1C)` and the objects G points at; the minidump is `MiniDumpNormal` with a size cap and a
> free-space check, written to the `round30_minidump_dir` cvar (default
> `%TEMP%\worldcup2010_minidumps`, cap `round30_minidump_max_mb` = 256 MiB); the third identical
> context still exits with `0x52300001`. **One rebuild: `BUILD_EXIT_CODE=0`** (`rexruntime.dll`
> 10,216,960 B). **152 s title-screen boot, no match:** the game ran to the kill point, **one log
> file, 48,269 B, 284 lines** (Round 29: 4 files / 16,439,480 B), sign-in lines **4** (was 126,928),
> no guest fault, no fault loop, no minidump; 67 `ROUND30 exception: host RIP` lines are benign
> first-chance exceptions from one large system/driver DLL (not identified by name). Static work: `sub_836D1540` returns
> `*(this+0x2C)`; that field is the **owner pointer stored by the base constructor**
> (`sub_8323FA88`), G's class is the class with **primary** vtable `0x825218B8` (secondary
> `0x825218A4` at `+0x14`; corrected in Round 32), and **G+0x1C is an array element
> count** (`sub_83233D90`), so `*(G+0x1C)=5` is "five elements", used by the caller as a pointer -
> a guest object-graph defect, not a mapping problem. Details in `# Round 31` below.

> **Round 30 update (2026-10-19, read-only).** The throw-in crash is **our diagnostic looping, not the
> guest.** In `worldcup2010_023.*` the guest faults **once** at `0x8333916C`
> (`lwz r5,0x1C(r9)` with `r9=5`); the following **14,284** `Null-page access: guest read of
> 0x00000005` faults are the Hunk-B dumper reading guest 5 from *inside* the vectored exception
> handler. Windows re-enters the handler for that new fault, the identical frozen context is printed
> one frame deeper, the faulting thread keeps the process-global memory critical region, every other
> guest thread blocks (last non-fault log line `11:14:10.448`, first fault `11:14:10.457`), and the
> process makes no progress until it is killed. Each level costs ~8.8 ms (the nearest-function lookup
> rebuilds and sorts 91,164 entries) and ~1.2 KiB of the 16 MiB host stack, so it would eventually
> have died of stack overflow. Fix proposed, **not applied and not built**: `patches\round30-1..3`
> (host-protection check in every dump, fault-loop guard + minidump, host-RIP logging, per-user-index
> sign-in cap), all `git apply --check` OK. **First fault: `worldcup2010_023.7.log:23697`,
> `2026-10-19 11:14:10.457`, guest read of `0x00000021`.** Details in `# Round 30` below.

> **Round 29 update (2026-10-19).** Round 28 proved the title *enumerates* content for the 32-bit
> truncated XUID `0x00000000BABEBABE` (0 items) while it *creates* its save under
> `0xB13EBABEBABEBABE`. Round 29 found the cause: **the truncation is in our own runtime.** The guest
> really does pass 64 bits - `sub_8319C5D0` does `ld r3,80(r1)` at `0x8319C660` (a full 64-bit load)
> and `bctrl`s at `0x8319C670` - but `ArgTranslator::GetIntegerArgumentValue` (`include/rex/ppc/
> function.h`) returns `ctx.r3.u32` for argument 0, so every 64-bit integer argument of every export
> is zero-extended from 32 bits. **VERIFIED** by guest disassembly + marshaller source + run-time log
> (`ROUND28C XamContentAggregateCreateEnumerator args xuid=00000000BABEBABE …
> runtime_xuid=B13EBABEBABEBABE`). Xenia has no such case - its `qword_t` forwards the full register
> and `xam_content_aggregate.cc:129` only maps the `-1` sentinel.
> **Applied this round (after a timestamped backup):** 5 per-file diagnostic patches - **D**
> (narrow XUID shim `Round29ResolveXuid()`: a requested XUID whose **upper 32 bits are zero** and
> whose **low 32 bits match the profile XUID's low 32 bits** resolves to the profile XUID; used at
> `XamContentAggregateCreateEnumerator`, `XamContentCreateEnumerator` and `xeXamContentCreate`; every
> use logged; cvar `round29_xuid_shim`, compile-out `-DROUND29_HUNK_D=0`), plus `XamUserGetXUID` /
> `XamUserGetSigninInfo` value+caller+read-back tracing, plus a change-only guard on the per-frame
> `XamUserGetSigninState`. **Hunks A and B untouched.** One rebuild (`BUILD_EXIT_CODE=0`,
> `rexruntime.dll` 10,187,776 B), one 158 s title-screen boot (`worldcup2010_022.*`).
> **Result: the save bug is fixed at the enumeration level.** The aggregate enumerator now scans
> `…\B13EBABEBABEBABE\454108E4\00000001` and returns **8 items** (the 8 `WCSettings0 …` saves); the
> following `xeXamContentCreate root='rmcsave'` **opens** an existing save
> (`flags=00000033 disposition=2`) instead of **creating** a new one (`flags=00000034 disposition=1`
> in Round 28), and **no new save directory was written**. The shim fired only on the
> `aggregate-enumerator` site (`00000000BABEBABE -> B13EBABEBABEBABE`, `caller=0x8319C674` - exactly
> the LR predicted statically); the `create-enumerator` and `content-create-data` sites were already
> correct and logged `unchanged`. **One requirement was NOT met** and is reported as a defect:
> the change-only guard for `XamUserGetSigninState` did not reduce volume (107,936 of 108,150 lines;
> 16,439,480 B over 4 files) because the four user indices are polled round-robin and my single
> `(last index, last value)` slot therefore never matches. The fix is one slot per user index; it
> needs **one more rebuild** and was not spent this round. Also carried forward and **restated**: the
> Round-28 crash function `sub_8333D4E0` ends at **`0x8333DCF8`**, not `0x8333DCD0`.

> **Round 28 update (2026-10-19).** Round 27 leaves the game reaching gameplay; a **hand-played
> throw-in** then hit a **new** stop (`dist\Output\logs\worldcup2010_019.log`): a null read of guest
> `0x21` (7 ms earlier, **silently hidden** by the on-demand-commit workaround) and then
> `INVALID INDIRECT CALL: target=82486704 LR=8333DB7C CTR=82486704 r1=7019E740 r2=00000000
> r3=BE4545F8 r11=825227F8 r12=8333DB44`. That target is `bcctrl` through `*(*(r30+0x2F8)+0x14)`;
> `r30` was **not** logged but is recoverable as `0xBE4545F8 - 760 = 0xBE454300`, and `0x82486704`
> is the literal **`"EASTL basic_string"`**. Static (no Xenia): `0x82486704` has **no** data-word
> reference in any non-exec section and exactly **one** materialisation site
> (`0x82F3BFD8 lis r10,0x8248 ; 0x82F3BFE0 addi r10,r10,0x6704`) where it is passed as a **name
> argument**, never stored at a fixed `object+0x14`; only **2** of the **70** stores to `+0x2F8`
> install a genuine vtable (`0x823C8460`, `0x8253E2EC`) and **neither** has a data word at `+0x14`.
> On saves: the static audit showed our store (`C:\Users\ramic\Documents\worldcup2010`) already holds
> **six** saves under `B13EBABEBABEBABE`, and the boot then **demonstrated the bug**: the game
> enumerates content for xuid **`0x00000000BABEBABE`** (a 32-bit-truncated copy of our XUID), so
> `ListContent` scans `…\00000000BABEBABE\…`, which does not exist, and returns **0 items**, while
> `xeXamContentCreate` writes `rmcsave` under `B13EBABEBABEBABE` - the game never sees its saves.
> **Applied this round (after a timestamped backup):** 10 per-file diagnostic patches - hunks **A**
> (null-page access is never committed on demand -> reaches the fatal path, clear log line),
> **B** (on every invalid indirect call / guest AV: all `r0..r31`, `LR`, `CTR`, the nearest
> registered function below `LR`, and a bounded page-checked hex dump of `r3,r8,r9,r11,r30,r31` and
> their pointees), **C** (INFO tracing of the content/user/UI calls, above all the aggregate
> enumerator's arguments + item count) - one rebuild, one boot. **No override, no XUID change.**

> **Round 26 update (the Round-25 block below is kept, but its headline crash is now fixed).**
> The user approved the **nine-thunk family** `0x837FD0F0..0x837FD170` and withdrew the stale
> 36-entry batch. Applied to **both** override copies (281 -> 290 entries, byte-identical,
> `802EE586...` -> `89B6D4D3...`), one rebuild (**607.9 s wall, exit code 0**), all nine `sub_`
> emitted and registered. **The `0x837FD0F0` crash is gone.** An unattended boot
> (`worldcup2010_015.log`) now runs **83.1 s** and stops at a **new** address:
> `INVALID INDIRECT CALL: target=8295FB50 LR=829658CC CTR=8295FB50 r3=BB140E40 r11=8295FB50
> r12=82969B40`, i.e. **29 s after** the content/save ordinals resolve (Round 25: 2 s). The new
> target is a 2-instruction tail fragment `li r4,1 ; b 0x8295F988`, immediately before the
> **already-registered** `li r4,0 ; b 0x8295F988` at `0x8295FB58`; it is the **only** unregistered
> code pointer in the 15-pair table at `0x823AF8E4..0x823AF95C`. Proposed, **NOT applied**:
> `"8295FB50" = { end = 0x8295FB58 }`. A **second** unattended boot (`worldcup2010_016.log`) did
> **not** crash at all: it parked on the **title screen** ("PRESS START", screenshots at 35/50/65/75 s)
> and its log stalls after `d:\BigFile_CheckpointB` at 70 s, i.e. the game waits for input and does
> not advance on its own. **A real `Xbox Series X Controller` is attached and detected.** For the
> keyboard, `mnk_mode` defaults to **false**; enable it via the **F4** settings overlay, `--mnk_mode`,
> or `dist\Output\worldcup2010.toml` (`mnk_mode = true`). Round 26 also completed the XAM audit:
> every content/user export this game imports is **implemented** in our runtime, and
> `XamContentGetDefaultDevice` (the one content stub) is **not imported by this game at all**.

> **Round 25 update (the paragraph below is kept, but is now out of date, and its crash is FIXED).**
> The Round-24 statement
> is still literally true for *boot + language screen*, but the user then drove the game with real
> input: **input works, the language screen and the favourite-team selection work, and the game
> crashes when the favourite team is confirmed, before the main menu.** Two runs failed
> identically (`worldcup2010_013.log` 10:11:55, `worldcup2010_014.log` 10:16:22):
> `INVALID INDIRECT CALL: target=837FD0F0 LR=83303088 CTR=837FD0F0 r3=B8F21A50 r11=B915E070
> r12=83318368`, then `[FATAL] Call to invalid or unregistered function at guest address
> 0x837FD0F0`; host exception `0xc0000409` (WER `BEX64`, our `assert_always` fail-fast) in
> `ucrtbase.dll+0xa527e`. The target is a **4-instruction vtable dispatch thunk**
> (`lwz r12,0(r3) / lwz r11,28(r12) / mtspr CTR,r11 / bctr`), materialised at `0x83318360` by
> `lis r10,0x8380 ; addi r4,r10,-12048` and passed as the callback to the container iterator
> `sub_83302FF8` from `0x83318364`. **No override was applied and nothing was rebuilt this round.**
> It is one of a run of **9 identical thunks** (`0x837FD0F0..0x837FD170`) that Round 24's scanner
> could not enumerate (two arithmetic bugs, see the Round 25 section at the end of this file).

**One line.** **The game boots and renders.** With the approved vtable-gap override
`"836A24B0" = { end = 0x836A24C0 }` (the second such gap, after `0x83884CA0`) plus the temporary
on-demand guest-virtual commit workaround, `worldcup2010.exe` opens a visible 1920x1080 window
titled *2010 FIFA World Cup South Africa PC*, draws the EA Sports / FIFA 2010 boot splash,
advances to the **language-select screen** (UK flag, arrows, "English"), and is **still running
when we kill it at 200 s** -- no fatal stop of any kind (no `INVALID INDIRECT CALL`, no unhandled
guest access violation). Frames are real, not black (four screenshots, 834-1141 distinct colours
sampled). The only runtime concession remains the workaround, which commits exactly **one** guest
page (`0x0006C000`) on first touch. Still open: the language screen has not been confirmed
*interactive* (no input was sent) and the workaround is still a workaround.

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

> **Correction (Round 32, 2026-10-19).** "All clean" above is wrong for two of the three
> `0x8323FB38 / 0x8323FB6C / 0x8323FB8C` rows, and the "leaf" class is wrong for the first two
> (FB8C is a complete leaf but still one entry point of the chain).
> They are three entry points into **one contiguous QueryInterface chain**, not standalone
> functions. The Round-14 validator's "max reachable + 4" treated the conditional return
> `beqlr cr6` (word `0x4D9A0020`) as a terminator, so `0x8323FB38` stops at `0x8323FB48` and
> `0x8323FB6C` stops at `0x8323FB7C`; `0x8323FB8C` is a genuinely complete leaf. The 14th
> (default `0x8211A170..0x8211A178`) is clean (last instruction `b 0x82118AB8`). The Round-32
> audit of all 291 entries found exactly these two as truncated; see `# Round 32` §8.2.

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
## Appendix - superseded one-pager (Rounds 12-23), kept verbatim

The editable one-page summary above replaces this block; nothing below is edited, so the
audit trail keeps the earlier wording (and its later retractions) intact.


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



## Round 24 (2026-10-18) - **the game boots and renders a real screen**

### Verdict (VERIFIED, this round)

* `dist\Output\worldcup2010.exe` opens a **visible top-level window** titled
  `2010 FIFA World Cup South Africa PC`, rect `0,0 1920x1080`, `visible=True iconic=False`,
  **0.6 s** after launch (polled `MainWindowHandle` / `MainWindowTitle`; not assumed).
* It draws the **EA Sports / FIFA 2010 World Cup South Africa boot splash**, then advances to the
  **language-select screen** (UK flag between two arrows, caption "English").
* It was **still running when killed at 200 s**, at `cpu=550.8 s` of 200 s wall (~2.75 cores busy:
  actively working/rendering, not hung). **No crash of any kind**: zero `FATAL`, zero
  `INVALID INDIRECT CALL`, zero `Unhandled guest access violation`.
* **Frames are real, not black**: four screenshots of the window rect were captured; a 64x36
  colour-grid sample gives 1141 / 834 / 834 / 834 distinct colours; each PNG is ~1.95 MB.
  `C:\Users\ramic\AppData\Local\Temp\opencode\round24_shots\shot{1..4}_*.png`.
* Run log: `dist\Output\logs\worldcup2010_012.log` (9,239 B, 79 lines).

### Item 2 - override applied, one rebuild, one boot

* Pre-change backup: `D:\FWC10\_backups\20261018-093302-r24` (Item 5).
* Entry added to **both** copies (`Installer\recomp-template\config\fifadllzf_overrides.toml` and
  `C:\FWC10B\fwc10stage4\WorldCup2010Rex\config\fifadllzf_overrides.toml`), byte-identical:
  13,962 B -> 15,040 B, SHA-256 `802EE586D73B757573FDA264EC7D25BBA2EA2A3B0287E1E0DF69510773229DA1`,
  **281** entries (was 280).
* Rebuild: 09:34:00 -> 09:41:26 = **446 s** wall, exit **0**. Codegen **396.3 s**,
  `6 written, 653 unchanged, 0 deleted, 1 module(s) up to date` - `config\*` is among the build's
  fingerprints, so exactly the affected files were regenerated. `sub_836A24B0` is now in
  `worldcup2010_init.cpp:72805`, `worldcup2010_recomp.166.cpp:30809`,
  `worldcup2010_register.cpp:72794`.
* New binaries in `dist\Output`:
  `rexruntime.dll` 10,127,360 B `4EFD66C708AC33CA227AEAEA05415A321F5957ACEC8D6595B4CB7D6B61D6E788`;
  `worldcup2010_fifadllzf.dll` 123,052,032 B `4D7AB3FE86CE7FEC046CE42997E69AAA4453761B5D86F24106A1387D2709141A`;
  `worldcup2010.exe` 8,022,528 B `FE2680B74E091C9FEE00BFBAD157F2ED760346F4A1C846CC5CFA870BF816E91E`;
  `rexgpu-xenos.dll` 3,033,600 B `A4559360FB18E1E82E74E2D1E111ABC544EE26A13F777CD5186D3F40EF11F877`.
  The workaround literal `...committed on demand as page...` is present in the new
  `rexruntime.dll`. (The sentence is built from the split format string
  `"Guest virtual {} of 0x{:08X} (host 0x{:016X}) committed on demand as page 0x{:08X} ({})"`, so
  the substring `Guest virtual read of` is *not* contiguous in the binary - it is split by the
  `{}`.)
* Boot: **200 s**, no exit (we killed it). Exactly **one** on-demand commit:
  `[warning] [sys] [t9928] Guest virtual read of 0x0006C6B8 (host 0x000000010006C6B8) committed on demand as page 0x0006C000 (first touch); total 1`
  preceded in the same millisecond by our own
  `BaseHeap::AllocFixed attempting commit on unreserved page`.
* **Next stop: none.** The former next stop (`0x836A24B0`) is gone and nothing replaced it.
* Other progress in the log (VERIFIED): `XexLoadImage fifadllzf.xex -> hmodule=0x30033000`; XAM
  ordinal resolution (`XexGetProcedureAddress`); APU endpoint opened
  (`'Speakers (USB Audio Device)': 2 ch, 48000 Hz, format 0x8120`); `BigFile_CheckpointA` /
  `BigFile_CheckpointB`; `XamBackgroundDownloadSetMode`; plus the expected tail of
  `[NtCreateFile] FAILED ... 0xc000000f` for files the PC port does not ship
  (`d:\memoryfw.ini`, `d:\data\loc\locale.bh`, `d:\audiodata\aemsdata\*.ast`, ...).

### Item 1 - systematic scan for unregistered `lis+ori` / `lis+addi` code targets (no run)

Tool: `C:\Users\ramic\AppData\Local\Temp\opencode\round24_scan3.py` (**3 s**, no run). Method:

1. Unpack `.text` of `fifadllzf.xex` (`0x82650000..0x838D8DB4`) as big-endian words.
2. Enumerate every `lis rD,imm` followed within 8 instructions by `ori rD,rD,lo` /
   `addi rD,rD,lo` on the **same** register; keep constants landing inside `.text`.
3. Drop targets that are already registered or already an override start.
4. Decode from each survivor with a real CFG walk: `bl`/`bcl` are **calls** (not terminators);
   `bclr`/`bcctr` are returns / indirect tails (with LK=1 they are indirect calls); conditional
   branches fork and are **not** terminators. "Complete" = every explored path ends in `blr` /
   `bctr` / a tail `b` leaving the region.
5. Reject overlap with registered extents and override ranges; reject targets that fall *inside*
   the previous registered function's extent.
6. Exclude a **pointer/jump table stored inside `.text`** (a run of words whose value is itself a
   `.text` address - they decode as `lwz rD,x(rA)` and fool a linear walk): `tabfrac >= 20%`.
   Exclude a **switch dispatch** by looking at the previous registered function's body for an
   indexed table load (`lwzx`, opcode 31 / XO 23).
7. Rank: a store of the built register right after the `lis`/`ori` pair (vtable-slot pattern); a
   true gap (previous registered function ends exactly at the target); that previous function
   ending in `bctr` and **not** containing `lwzx`; small size.

Counts (VERIFIED):

| stage | count |
|---|---|
| `lis` + `ori`/`addi` pairs forming a constant inside `.text` | 2,114 |
| unique target addresses | 1,618 |
| not a registered start and not an override start | 1,023 |
| ...inside the previous registered function's extent (mid-function, not an entry) | 955 |
| ...overlap a registered extent | 11 |
| ...overlap an override range | 1 |
| ...not decodable as a complete function | 6 |
| **complete and outside every registered extent = candidates** | **50** |
| ...with a static 32-bit occurrence in a non-exec section | 0 |
| ...preceded by a jump-table dispatch (`lwzx`) | 4 |
| ...whose extent is a `.text` pointer/jump table (`tabfrac >= 20%`) | 14 |
| ...with no exact gap (unclaimed bytes before the entry) | 30 |
| **tier A: true gap, no pointer table, no jump-table dispatch** | **6** |
| **tier B: same, but no exact gap** | **30** |
| **proposed batch (A then B, <= 60)** | **36** |

The mid-round v1 numbers (464 candidates) were **wrong and are withdrawn**: that decoder treated
`bl` as a terminator and ignored the `bclr`/`bcctr` variants, which truncated extents (to the first
call) and let mid-function addresses pass the "outside the previous function" test. Use the v2
counts above.

Tier A (all six have the previous registered function ending *exactly* at the target):

```
"82AC37F8" = { end = 0x82AC3808 }   # lwz r12,0(r3) / lwz r11,152(r12) / mtspr / bctr
"82EE77B0" = { end = 0x82EE77C4 }   # lis/addi r11 -> global / lwz r11,8(r11) / mtspr / bctr
"8267C070" = { end = 0x8267C074 }   # single tail `b`
"83018288" = { end = 0x83018298 }   # lis/ori const 0xC14A247C / cmp / bclr
"8323F4B8" = { end = 0x8323F4E0 }   # object init: stw r9,4(r3) / stw r10,0(r3) / stw r11,8(r3) / blr
"82685B18" = { end = 0x82685B34 }   # lis 0x839B / mr r4,r3 / lwz r3,-32712(r11) / lwz / lwz / mtspr / bctr
```

Tier B (30) and the full disassembly of the top 20 are in `round24_scan3_out.txt`.

> ### WITHDRAWN (2026-10-18, Round 26, on the user's instruction)
>
> **The 36-entry batch above is withdrawn and must never be applied.** The Round-25 audit found
> that **13 of its 36 entries name the WRONG address** (real value = entry `- 0x10000`, caused by
> `round24_scan3.py:172` not sign-extending the `addi` immediate and requiring
> `dest == src == lis dest`); see "AUDIT OF THE PENDING 36-ENTRY BATCH" in the Round 25 section.
> The three tier-A entries printed above are among the wrong ones. The **corrected** pool is
> **NOT APPLIED** and is listed in the Round 26 section below.

### Item 3 - how Xenia's backing mapping is created vs ours (VERIFIED: source + local experiment)

**Xenia** (`xenia-canary/xenia-canary`, `canary_experimental`), `src/xenia/memory.cc:180-185`:

```cpp
  // Create main page file-backed mapping. This is all reserved but
  // uncommitted (so it shouldn't expand page file).
  mapping_ = xe::memory::CreateFileMappingHandle(
      file_name_,
      // entire 4gb space + 512mb physical:
      0x11FFFFFFF, xe::memory::PageAccess::kReadWrite, false);
```

`src/xenia/base/memory_win.cc:212-226`:

```cpp
FileMappingHandle CreateFileMappingHandle(const std::filesystem::path& path,
                                          size_t length, PageAccess access,
                                          bool commit) {
  DWORD protect =
      ToWin32ProtectFlags(access) | (commit ? SEC_COMMIT : SEC_RESERVE);
  auto full_path = "Local" / path;
  return CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, protect, ...
```

So the whole 4 GB guest + 512 MB physical arena is **`PAGE_READWRITE | SEC_RESERVE`** - reserved,
**not** committed. The low virtual heap is committed up front only for its **first 64 KB**
(`memory.cc:234-239`):

```cpp
  // Protect the first and last 64kb of memory.
  heaps_.v00000000.AllocFixed(
      0x00000000, 0x10000, 0x10000,
      kMemoryAllocationReserve | kMemoryAllocationCommit,
      !cvars::protect_zero ? kMemoryProtectRead | kMemoryProtectWrite
                           : kMemoryProtectNoAccess);
```

Xenia's other up-front commits are the GPU writeback windows (`vC0000000` at `0xC0000000` +
`0x01000000` and `v7F000000` at `0x7F000000` + `0x00C80000`, both reserve|commit RW,
`memory.cc:243-252`), the whole physical range (`memory.cc:254-263`), and
`v80000000.Alloc(0x40000, 4 * 1024, kMemoryAllocationCommit, RW)` (`memory.cc:281-285`).
**`0x6C000` is in none of them.**

Later commits go `BaseHeap::AllocFixed` -> `xe::memory::AllocFixed` ->
`VirtualAlloc(..., MEM_COMMIT, ...)` (`memory_win.cc:110-131`), and a *commit-only* request on a
reserved page is silently promoted (`memory.cc:1118-1123`):

```cpp
    if ((allocation_type == kMemoryAllocationCommit) &&
        !(state & kMemoryAllocationReserve)) {
      // Attempting a commit-only op on an unreserved page.
      XELOGW("BaseHeap::AllocFixed attempting commit on unreserved page");
      allocation_type |= kMemoryAllocationReserve;
```

`ShouldSkipHostCommit` (`memory.cc:106-116`) skips the host commit only when the **host** page size
is > 4 KB; on Windows x64 `page_size()` returns 4096 (`memory_win.cc:30-32`), so Xenia really does
issue it.

And Xenia's access-violation handler **refuses non-physical heaps** (`memory.cc:598-614`):

```cpp
  uint32_t virtual_address = HostToGuestVirtual(host_address);
  BaseHeap* heap = LookupHeap(virtual_address);
  if (heap->heap_type() != HeapType::kGuestPhysical) {
    return false;
  }
```

**Ours** (`ReXGlue/src/system/xmemory.cpp`) is the same design:
`CreateFileMappingHandle(file_name_, mapping_size, PageAccess::kReadWrite, false)` (lines 141-145)
=> `SEC_RESERVE`; `heaps_.v00000000.Initialize(..., 0x00000000, 0x40000000, 4096)` with the same
64 KB `AllocFixed(0x00000000, 0x10000, 0x10000, reserve|commit, NoAccess)` (lines 186-187,
206-210); and `AccessViolationCallback` with the same `!= kGuestPhysical` early-out (lines
608-614) - the on-demand commit *above* that early-out (lines 547-606) is our Round-22 workaround,
not Xenia code.

**Experiment (VERIFIED, on this machine, `spr_test.py`).** Reproducing the exact creation with
`CreateFileMappingW(INVALID_HANDLE_VALUE, ..., PAGE_READWRITE|SEC_RESERVE, ...)` + `MapViewOfFile`:

* `SEC_RESERVE` view: every page reports `state=RESERVE protect=0x0 type=MAPPED`
  - **not committed up front**.
* `SEC_COMMIT` view: every page reports `state=COMMIT protect=0x4 type=MAPPED`.
* A raw read of a reserved page of the `SEC_RESERVE` view **faults with `0xC0000005`** - Windows
  does **not** commit it on demand.
* `VirtualAlloc(addr, 0x1000, MEM_COMMIT, PAGE_READWRITE)` *inside* the view succeeds, splits the
  region to a single 0x1000 `COMMIT` page with `protect=0x4` - the only way to make the page live,
  and exactly the mechanism Xenia's `AllocFixed` and our workaround use.

Our faulting page `0x1_0006_C000` reported `MEM_RESERVE` / `protect 0` / `MEM_MAPPED` (Round 23),
i.e. byte-for-byte the `SEC_RESERVE` shape above. **The mapping flags are identical in Xenia and
in ours, so the fault is not a flag difference.**

#### Correction to the Round 23 notes (Round 23 item 3)

Round 21 verified `r3 == 0` at `0x82CBD80C` in Xenia **with controls**, so Round-23 reading (b) -
"Xenia never takes the null-base read" - is **ruled out and retracted**. With (i) both runtimes
`SEC_RESERVE`, (ii) neither committing `0x6C000` up front, and (iii) Xenia's AV handler refusing
virtual heaps, the surviving explanation is that **in Xenia page 0x6C000 really is committed before
that read by a path our runtime does not take**. Supporting asymmetry (VERIFIED, Round 23): Xenia
prints `BaseHeap::AllocFixed attempting commit on unreserved page` **3x per run** (three
commit-only promotions of reserved pages) while our runtime prints it **0x** without the
workaround. *Which* caller does it stays **INFERRED, not verified** - the warning prints no
address - and would need a source-wide search for `AllocFixed(..., kMemoryAllocationCommit, ...)`
callers. Our workaround reproduces the *effect* (commit on first touch) and is what makes this
round's boot possible.

### Item 4 - the exact one-line command

Same flags as our runs = **no flags**, working directory `dist\Output`:

```
cd /d D:\FWC10\world-cup-2010-pc-port\dist\Output && worldcup2010.exe
```

(Prepend `start ""` if you want the console to return immediately. Each run writes a new
`logs\worldcup2010_NNN.log`.) Our runner used `Start-Process -WorkingDirectory dist\Output` with no
arguments - identical, except that our runner also polls `MainWindowHandle` and screenshots the
window.

### Item 5 - backups / verification state

`D:\FWC10\_backups\20261018-093302-r24` (pre-change): `xmemory.cpp.with_r23_workaround`
(`48D8EF09616A1CC4F5B28F14AD45D343FBA45CD1060F982D6AD4D5100AAA8BE9`, 101,208 B); both
`fifadllzf_overrides.toml` copies *before* the entry (`D69ADAA0...684A`, 13,962 B); both
`default_overrides.toml` copies; `BuildWorldCup2010.ps1.before`; `git-HEAD.txt`;
`git-status-porcelain.txt`; `README.txt`; `SHA256SUMS.txt`; appended line in
`D:\FWC10\_backups\LAST_BACKUP.txt`. Post-change artefacts (both override copies as `*.after`, the
build log, the scan output, the run log, the four screenshots, the driver scripts) are added to the
same directory after the boot.

`D:\FWC10\xenia` was **not touched and Xenia was not run this round**, so no post-run re-verification
of its file set was required.

Changes remain uncommitted (no git repo at `D:\FWC10`).

---

## Round 25 (2026-10-18) - favourite-team selection crashes: a second vtable-thunk run the Round-24 scan could not see

User report: **input works**; the language screen and the **favourite-team selection work**; it
**crashes after confirming the favourite team, before the main menu**. No rebuilds and no override
changes until approval. 45-minute box.

**Nothing was built, no override was changed, no Xenia run by us this round.** The only writes were
this file and the round backup directory. The crash diagnosis is from the user's own two runs.

### Item 1 - the failure (VERIFIED)

| run | log | game start | fatal | thread |
|---|---|---|---|---|
| 013 | `dist\Output\logs\worldcup2010_013.log` | 10:11:0x | 10:11:55.920 | t28248 |
| 014 | `dist\Output\logs\worldcup2010_014.log` | 10:15:26.630 | 10:16:22.882 | t18044 |

* **Failure type: invalid indirect call, not an access violation** (VERIFIED, both logs):
  `INVALID INDIRECT CALL: target=837FD0F0 LR=83303088 CTR=837FD0F0 r1=7019E910 r2=00001100
  r3=B8F21A50 r11=B915E070 r12=83318368` followed one line later by
  `[critical] [core] [t18044] [FATAL] Call to invalid or unregistered function at guest address
  0x837FD0F0`.
* **Guest address: `0x837FD0F0`** (`fifadllzf`, `.text` `0x82650000..0x838D8DB4`, offset
  `0x11AD0F0`, 4-byte aligned, **not** a registered start, **not** an override start).
* **Host exception code: `0xc0000409`** (`STATUS_STACK_BUFFER_OVERRUN` / fail-fast; WER
  `Event Name: BEX64`, `P4: ucrtbase.dll`, `P6: 0x3f426c5b`, `P7: 0x00000000000a527e`,
  `P8: c0000409`, `P9: 0x7`); `Application Error` 1000 for `worldcup2010.exe`
  (`Exception code: 0xc0000409`, `Fault offset: 0xa527e` in `ucrtbase.dll`), fault buckets for the
  two runs are **identical** (`2146590310605515663`). This is our runtime's own fatal path
  (`assert_always()` -> CRT `abort()`/`__fastfail`), i.e. the *consequence* of the FATAL above, not
  an independent host crash (VERIFIED: the fatal line is written first, in the same thread).
* Crash dumps exist: `C:\Users\ramic\AppData\Local\CrashDumps\worldcup2010.exe.24928.dmp`
  (10:11:59, run 013) and `...worldcup2010.exe.12432.dmp` (10:16:25, run 014). No PDB/`cdb`/WinDbg,
  so the dumps were not opened; the logs are sufficient and decisive.
* Run 014 lasted **56 s** (10:15:26.630 -> 10:16:22.882); it contains **zero** `FATAL` before the
  final one and **zero** access violations.

### Item 2 - what the target is, and where the pointer comes from (VERIFIED)

`0x837FD0F0` is one of **ten consecutive 16-byte vtable-dispatch thunks** at
`0x837FD0E0..0x837FD180`; only the *first* is registered, the other **nine are not**:

```
0x837FD0E0  lwz r12,0(r3) ; lwz r11,12(r12) ; mtspr CTR,r11 ; bctr   <-- REGISTERED
0x837FD0F0  lwz r12,0(r3) ; lwz r11,28(r12) ; mtspr CTR,r11 ; bctr   <-- crashed here (slot +0x1C)
0x837FD100  lwz r12,0(r3) ; lwz r11,44(r12) ; mtspr CTR,r11 ; bctr   (slot +0x2C)
0x837FD110  lwz r12,0(r3) ; lwz r11,60(r12) ; mtspr CTR,r11 ; bctr   (slot +0x3C)
0x837FD120  lwz r12,0(r3) ; lwz r11,32(r12) ; mtspr CTR,r11 ; bctr   (slot +0x20)
0x837FD130  lwz r12,0(r3) ; lwz r11,48(r12) ; mtspr CTR,r11 ; bctr   (slot +0x30)
0x837FD140  lwz r12,0(r3) ; lwz r11,64(r12) ; mtspr CTR,r11 ; bctr   (slot +0x40)
0x837FD150  lwz r12,0(r3) ; lwz r11,36(r12) ; mtspr CTR,r11 ; bctr   (slot +0x24)
0x837FD160  lwz r12,0(r3) ; lwz r11,8(r12)  ; mtspr CTR,r11 ; bctr   (slot +0x08)
0x837FD170  lwz r12,0(r3) ; lwz r11,40(r12) ; mtspr CTR,r11 ; bctr   (slot +0x28)
```

Each is `lwz r12,0(r3)` (the object's vtable) / `lwz r11,<slot>(r12)` / `mtspr CTR,r11` / `bctr` --
a virtual-method forwarder. Validated with the same procedure as `0x83884CA0` and `0x836A24B0`:
true gap (the previous registered entry `0x837FD0E0` ends **exactly** at `0x837FD0F0`), no
registered entry inside the extent, terminator `bctr` at `0x837FD0FC`, no `bl` inside, no incoming
non-volatile argument reads, `static=0`, `.text`-pointer-table fraction 0%.

**Where the pointer comes from (VERIFIED, by disassembly):** it is *passed in*, as the second
argument of a container iterator, and it is materialised by the **negative-`addi` idiom with a
different destination register**:

```
0x83318354  3D408380  lis  r10, 0x8380
0x83318358  38A10054  addi r5, r1, 84
0x8331835C  807F0004  lwz  r3, 4(r31)
0x83318360  388AD0F0  addi r4, r10, -12048      ; r4 = 0x83800000 - 0x2F10 = 0x837FD0F0
0x83318364  4BFEAC95  bl   0x83302FF8          ; iterate, callback = r4
0x83318368  ...                                ; == r12 in the crash dump
```

and the iterator itself does `lwz r11,12(r30) / mtspr CTR,r27 / lwz r4,0(r26) / add r11,r11,r31 /
lwz r3,4(r11) / bcctrl` (`CTR = r27` = the callback argument; `r3` = the object). So the game is
iterating a container and invoking this interface method on each element. The same address is
materialised at **8 further sites** (`0x833183DC`, `0x833183F4`, `0x83318418`, `0x83318464`,
`0x837B...`, `0x8380...`).

**Why Round 24's scan did not propose it (VERIFIED - two enumeration bugs).** `round24_scan3.py:172`
combined the halves as `full = (hi << 16) | (w2 & 0xFFFF)` for **both** `ori` and `addi`, and
required `dest == source == lis dest`. The real code is `lis r10,0x8380` + `addi r4,r10,-12048`:
(a) `addi` **sign-extends** its immediate, so the value is `0x83800000 - 0x2F10 = 0x837FD0F0`, not
`0x8380D0F0`; (b) the **destination register differs** from the `lis` destination. Both were
invisible to the Round-24 scan, and this address is **not** stored anywhere in the image (0 data
occurrences of `0x837FD0F0` in either XEX) -- it exists only as those `lis`/`addi` constructions.

### Item 1 (Round-24 batch) - AUDIT OF THE PENDING 36-ENTRY BATCH: 13 of 36 entries name the WRONG address (VERIFIED)

The same arithmetic bug applies to the batch that is still awaiting approval. Re-deriving every
materialised constant correctly and re-checking the batch's 36 entries:

* **23 entries** name an address that a real `lis`+`ori/addi` pair does build (kept).
* **13 entries** name an address that **no instruction builds** -- the value the code really builds
  is `entry - 0x10000`:
  - tier A (3 of 6!): `0x8267C070` (really `0x8266C070`), `0x83018288` (really `0x83008288`),
    `0x8323F4B8` (really `0x8322F4B8`) -- and all three "real" addresses are **already registered**,
    so those tier-A entries are pure phantoms.
  - tier B (10 of 30): `0x82EB8C80`, `0x82EEB048`, `0x83018110`, `0x8301BEA8`, `0x8301DB90`,
    `0x8267AFC8` (real addresses all already registered) plus `0x8309C894` -> `0x8308C894`,
    `0x830AC60C` -> `0x8309C60C`, `0x833AD37C` -> `0x8339D37C`, `0x834C8CE0` -> `0x834B8CE0`
    (**these four real addresses are NOT registered** - genuine missing functions, off by `0x10000`).
* **Do not apply the 36-entry batch as it stands.** The corrected pool is in
  `round25_scan_out.txt` / `round25_scan_candidates.json` (563 non-registered candidates -> 87
  valid -> **12 tier A**).

### Item 4 - every `Xam*` / `Nt*` call between the language screen and the crash (VERIFIED)

Log 014 is 90 lines / 56 s. Complete inventory of kernel/XAM traffic:

* **`XamContentCreateEx`, `XamUserWriteProfileSettings`, `XamUserReadProfileSettings`,
  `XamContentClose`, any content-device mount: ZERO occurrences.** There is **no save write** in
  our run - not one content/package/file write of any kind.
* The only `Xam*` line in the whole log is a *stub*: `__imp__XamBackgroundDownloadSetMode STUB`
  (10:15:56, t27816). The only other stub is `__imp__XUsbcamGetState STUB - returning 0x0` (68).
* **`NtCreateFile`: 26 calls, all FAILED**, all `-> 0xc000000f` (`STATUS_OBJECT_NAME_NOT_FOUND`),
  all read-only lookups of game data on `d:\` / `E:\dvdini` (`memoryfw.ini`, `data\loc\locale.bh`,
  `cl.ini`, `data\loc\eng_us_upd.db`, `d:\BigFile_CheckpointA`, `d:\BigFile_CheckpointB`,
  `d:\audiodata\aemsdata\*.ast`, ...). **Zero successes, zero writes.** The save path is not
  reached and `0xc000000f` here is benign (optional config/audio files the PC conversion does not
  ship - the game continues).
* **The tell-tale sequence immediately before the crash** (thread `t27816`, caller `0x8319C1C0`) --
  the game resolves the **content/save** API by ordinal, right after the favourite team is chosen:
  - `10:16:07.283` ordinal `0x00000279` -> `XamContentAggregateCreateEnumerator`
  - `10:16:07.334` ordinal `0x00000271` -> `XamContentCreateInternal`
  - `10:16:20.818` ordinal `0x00000270` -> `XamContentDeleteInternal`
  - `10:16:21.848` `NtCreateFile` `d:\audiodata\aemsdata\21_LL.ast` FAILED
  - `10:16:22.882` **the fatal indirect call**
  So the game is *setting up the save/content flow* when it enters the code path that calls
  `0x837FD0F0`. **The save write is involved only in the sense that the crash happens while the
  game is preparing to write `WCSettings0`; it is not caused by a save failure** (no content call,
  no device access, no error was ever emitted). Note our SDK *does* implement
  `__imp__XamContentCreateEx` / `XamContentCreateInternal` / `XamContentDeleteInternal` (real
  bodies in `src\kernel\xam\xam_content.cpp`), while most package/mount entry points
  (`XamContentCreateAndMountPackage`, `XamContentMountPackage`,
  `XamContentGetMountedPackageByRootName`, `XamContentCreateEnumeratorInternal`, ...) are
  `REX_EXPORT_STUB`.

### Item 3 - access violation? No (VERIFIED: not applicable)

The failure is an invalid indirect call, so there is no failing guest address / page to report. For
completeness: the run contains **no** `Unhandled guest access violation` line, and the on-demand
commit workaround fired **exactly once**, at **10:15:28.961** (2.3 s in, on the *startup* path, not
at the crash): `Guest virtual read of 0x0006C6B8 ... committed on demand as page 0x0006C000 (first
touch); total 1`, preceded by `BaseHeap::AllocFixed attempting commit on unreserved page` - i.e. the
same single `0x6C000` commit as Rounds 23 and 24.

### Item 5 - what Xenia does at the same stage that we do not (VERIFIED, read-only)

Sources: `D:\FWC10\xenia\xenia.log` (97,810 B, 1541 lines, 10-17 14:44 - read only, not modified)
and the content stores `D:\FWC10\xenia\content` / `C:\FWC10B\xenia_dbg\content`.

* Xenia's *import* tables (the `F ...` dump) contain, for `fifadllzf` (`82300440`), exactly the
  calls our log never shows:
  `XamContentCreateEx (0x259)`, `XamContentDelete (0x25B)`, `XamContentClose (0x25A)`,
  `XamContentGetCreator (0x262)`, `XamContentGetLicenseMask (0x266)`,
  `XamContentCreateEnumerator (0x25C)`, `XamContentGetDeviceState (0x265)`,
  `XamContentGetDeviceData (0x25E)`, and `XamUserReadProfileSettings (0x219)`.
* Xenia actually **creates and mounts the save content**: `~ContentPackage: Closing package:
  rmcsave (Device: \Device\Content\3\) Device mounted: Yes` and the same for `\Device\Content\4\`,
  plus `Savegame ID: 454108E4`.
* On disk Xenia produced the **`WCSettings0` save** - `content\E03000007F393D8F\454108E4\
  00000001\WCSettings0 20261017134124` + `...134145` (494,349 B of data + 40,960 B headers) plus
  the profile `.gpd` files (`454108E4.gpd`, `FFFE07D1.gpd`) and the `Account` file. **Our run
  produced nothing** (no `content` directory is even touched; `dist\Output` has no save store).
* Interpretation (INFERRED): the game reaches the same "create/open `WCSettings0`" step in both
  emulators; Xenia completes it, we crash one call *earlier* - inside game code that runs when the
  content objects are being built. We cannot yet say whether our content/save path would succeed
  after the crash is fixed, because the game never gets there.

### Item 6 - smallest fix, with evidence (NOT APPLIED - awaiting approval)

**Proposal (smallest):** one override entry, in **both** override copies:

```toml
"837FD0F0" = { end = 0x837FD100 }
```

Evidence: the game *does* call it (LR `0x83303088`, `CTR=target`, callback materialised at
`0x83318360`, two independent runs, identical registers); it is a true function start (previous
registered entry ends exactly at it; `bctr` terminator; no registered entry inside; no static
table; not a `.text` pointer table; `lwzx`-free); and the same validation was used for
`0x83884CA0` and `0x836A24B0`.

**Wider variant (family):** the whole run, 9 entries, `"837FD0F0"` ... `"837FD170"` each
`{ end = next }` (`0x837FD100`, `0x837FD110`, ..., `0x837FD180`). All nine are real thunks
materialised by real `lis`/`addi` pairs (`0x837FD0E0` was registered; the other nine were not) and
the interface is a contiguous vtable slot map (slots `0x0C 0x1C 0x2C 0x3C 0x20 0x30 0x40 0x24
0x08 0x28`), so the next method call on the same object would hit the next thunk.

**Caveat (INFERRED, honest):** each thunk is a *forwarder* - `0x837FD0F0` will, when it runs,
jump to whatever the object's vtable slot `+0x1C` holds. If that callee is itself unregistered the
run will stop there instead (a different address). The one-entry proposal is therefore the smallest
step that lets the run continue and *report the next stop*, not a promise that it reaches the main
menu.

**Not applied. Nothing was built.** The next action is the user's call: apply the single entry (or
the 9-entry family), rebuild once, boot, and report wall time / commits / next stop.

### Verification vs inference (Round 25)

* VERIFIED: the failure is an invalid indirect call at `0x837FD0F0`, identical in both runs; the
  host `0xc0000409` is our own fail-fast; the page state question (AV) does not apply; the on-demand
  commit fired once on the startup path; the thunk's 4 instructions; the true-gap validation; the
  materialisation at `0x83318360` and 8 other sites; zero data occurrences of the address in either
  XEX; the two Round-24 scanner bugs and the 13 wrong batch entries; the complete XAM/Nt inventory
  (no content/save call, 26 failed `NtCreateFile`); Xenia's import list, `rmcsave` mounts and the
  on-disk `WCSettings0` save; the SDK export/stub split.
* INFERRED: that the crash happens *inside the flow that prepares the `WCSettings0` write* (it
  follows the three `XamContent*Internal` resolutions by 2 s); that registering `0x837FD0F0` will
  move rather than end the problem (the real callee behind vtable slot `+0x1C` is data); that Round
  24's 36-entry batch would have been harmful if applied unmodified (12 of the 13 wrong addresses
  are already-registered functions, so those overrides would have re-declared an existing function
  with a bogus extent).

### Round 25 artefacts (all under `C:\Users\ramic\AppData\Local\Temp\opencode\`)

`round25_triage.py` / `_out.txt` (target + call site), `round25_run.py` / `_out.txt` (the 9-thunk
run), `round25_scanfix.py` / `_out.txt` (enumeration correction), `round25_origin.py` / `_out.txt`
(pointer origin), `round25_scan.py` (corrected scanner, cloned from `round24_scan3.py`) /
`round25_scan_out.txt` / `round25_scan_candidates.json`, `round25_batch_audit.py`,
`round25_audit.py`, `round25_dbg.py`, `r25_patch.py`, `r25_logscan.py`. Backup directory
`D:\FWC10\_backups\20261018-105xxx-r25` with SHA-256 sums.

`D:\FWC10\xenia` was **not modified and Xenia was not run** (only `xenia.log` was read);
`C:\FWC10B\xenia_dbg` was read only. Neither copy was written to.

---

## Round 26 (2026-10-18) - the nine-thunk family is applied; the favourite-team crash is fixed; a new stop appears

**Box:** backup + one override change + **one rebuild** + two boots + one source audit. No Xenia run.

### What the user approved, and what changed (VERIFIED)

* **Approved:** the **family of nine** thunk entries `837FD0F0, 837FD100, 837FD110, 837FD120,
  837FD130, 837FD140, 837FD150, 837FD160, 837FD170`, each `end = start + 0x10`; last ends at
  `0x837FD180`. **Withdrawn:** the Round-24 36-entry batch (see the WITHDRAWN banner in the Round 24
  section).
* **Both override copies changed, byte-identically:**

  | | before | after |
  |---|---|---|
  | bytes | 15,040 | **16,464** |
  | entries | 281 | **290** |
  | SHA-256 | `802EE586D73B757573FDA264EC7D25BBA2EA2A3B0287E1E0DF69510773229DA1` | **`89B6D4D33BF11037FE259FEAA23175D0EE0276BC80F9A1032E7FA26A89A8B36E`** |

  Copies: `D:\FWC10\world-cup-2010-pc-port\Installer\recomp-template\config\fifadllzf_overrides.toml`
  and `C:\FWC10B\fwc10stage4\WorldCup2010Rex\config\fifadllzf_overrides.toml` (compared byte for
  byte). The nine entries carry a comment block recording the evidence and the withdrawn batch.
* **Backup:** `D:\FWC10\_backups\20261018-105001-r26` - `fifadllzf_overrides.{A,B}.{before,after}.toml`,
  `NOTES.md.before`, `git-HEAD.txt`, `sdk-src-state.txt`, `SHA256SUMS.txt`, plus
  `worldcup2010.exe.after` and `worldcup2010_register.after.cpp` (post-build). `LAST_BACKUP.txt`
  appended twice (before-build, after-build).
* **One rebuild:** `Installer\BuildWorldCup2010.ps1 -SourceBuild -Jobs 2`, **wall 607.9 s**,
  `BUILD_EXIT_CODE=0`. (Round 24's reference was 446 s. No claim is made that the difference is
  real: heavy Python analysis was running concurrently with this build, which is the obvious
  candidate - **INFERRED**, not measured.)
* **Every one of the nine new `sub_` is emitted** in the **fifadllzf** module
  (`generated\fifadllzf_xex\`, timestamps 10:59:01-10:59:06) in
  `worldcup2010_funcs.h`, `worldcup2010_init.cpp`, a `worldcup2010_recomp.NN.cpp`, and
  `worldcup2010_register.cpp`:

  ```
  registrar->SetFunction(0x837FD0F0, sub_837FD0F0);   ... 0x837FD100, 0x837FD110, 0x837FD120,
  0x837FD130, 0x837FD140, 0x837FD150, 0x837FD160, 0x837FD170   (register.cpp:78290-78298)
  ```
  and the rebuilt translation units are exactly those nine files (recomp .20/.45/.100/.122/.124/.153/.254/.279/.320).
* The build's own second codegen pass printed `Codegen summary: 0 written, 2 unchanged, 0 deleted`
  because the configure phase (`[3/6]`/`[4/6]`, phases `Register -> Scan -> Discover -> GapFill ->
  Merge -> Validate -> Write`) had already written the generated code in the same run.

### Item 1 - pre-application evidence for the nine (VERIFIED)

Decode of the ten-thunk run (`0x837FD0E0..0x837FD180`), re-derived from the XEX image:

| address | vtable slot | decode | state before |
|---|---|---|---|
| `0x837FD0E0` | `r12+0x0C` | `lwz r12,0(r3) / lwz r11,12(r12) / mtspr CTR,r11 / bctr` | already registered |
| `0x837FD0F0` | `r12+0x1C` | `... lwz r11,28(r12) ...` | unregistered <- the crash |
| `0x837FD100` | `r12+0x2C` | `... 44(r12) ...` | unregistered |
| `0x837FD110` | `r12+0x3C` | `... 60(r12) ...` | unregistered |
| `0x837FD120` | `r12+0x20` | `... 32(r12) ...` | unregistered |
| `0x837FD130` | `r12+0x30` | `... 48(r12) ...` | unregistered |
| `0x837FD140` | `r12+0x40` | `... 64(r12) ...` | unregistered |
| `0x837FD150` | `r12+0x24` | `... 36(r12) ...` | unregistered |
| `0x837FD160` | `r12+0x08` | `... 8(r12) ...` | unregistered |
| `0x837FD170` | `r12+0x28` | `... 40(r12) ...` | unregistered |

* All nine decode **exactly** `lwz r12,0(r3) / lwz r11,<slot>(r12) / mtspr CTR,r11 / bctr`; each
  is **16 bytes** (terminator `bctr` at `+0xC`); the nine are consecutive with no gaps; the last
  ends at `0x837FD180`.
* **Boundaries:** the nearest registered entry below the run is `0x837FD0E0`, whose extent ends
  **exactly** at `0x837FD0F0`. **No registered entry lies strictly inside**
  `0x837FD0F0..0x837FD180`. **`0x837FD180` IS registered** (19-instruction leaf) and is **not** an
  override start, so the family must stop before it.
* **No overlap** of any of the nine 16-byte ranges with any registered extent, nor with any of the
  281 applied override ranges. No `837FD0xx` entry existed before.
* **Provenance audit of all 281 applied override entries** (the check the user asked for - did any
  applied override come from the buggy `round24_scan3.py` `addi` handling?):

  | provenance | count |
  |---|---|
  | address built by a real, sign-correct `lis`+`ori/addi` pair | **2** |
  | address built **only** by the buggy arithmetic (`(hi<<16)\|low`, `dest == src == lis dest`) | **0** |
  | no `lis`+`ori/addi` pair at all (added by the Stage 6b-6d `.rdata`/pointer-table method) | **279** |

  The two pair-built entries are `0x83884CA0` (built at `0x836D3320`/`0x836D3324`, `hi=0x8388
  lo=0x4CA0`) and `0x836A24B0` (built at `0x836BDC1C`/`0x836BDC24`) - both sign-correct. All 279
  "other provenance" entries are now registered starts. **VERDICT: no applied override is
  attributable to the buggy `addi` handling.**

### Item 2 - apply, rebuild, boot, and the keys

**Boot 1** (`worldcup2010_015.log`, unattended, `round24_run.ps1`): window at **1.2 s**, 1920x1080,
title *2010 FIFA World Cup South Africa PC*; real frames (781-1066 distinct colours sampled);
**exited at 83.1 s with `0xc0000409`** (our `assert_always` fail-fast).

**The old crash is gone.**

```
[11:03:43.582] [error] [cpu] [t29144] INVALID INDIRECT CALL: target=8295FB50 LR=829658CC
                                    CTR=8295FB50 r1=7088AA80 r2=828EBE00 r3=BB140E40
                                    r11=8295FB50 r12=82969B40
[11:03:43.582] [critical] [core] [t29144] [FATAL] Call to invalid or unregistered function at guest address 0x8295FB50
```

* `INVALID INDIRECT CALL at 0x837FD0F0`: **zero occurrences**. The new address is different.
* The content/save ordinals resolved at **11:03:06.8 / 11:03:06.8 / 11:03:14.9** (`0x279`, `0x271`,
  `0x270`), and the stop comes **29 s later** - Round 25 stopped **2 s** after the same resolves.
* One on-demand commit, the same single startup page (`0x0006C000` on guest read `0x0006C6B8`).

**Boot 2** (`worldcup2010_016.log`, `round26_run2.ps1`, late screenshots): **no crash at all** -
killed at 200 s. 81 log lines; the log **stalls** after `d:\BigFile_CheckpointB` (70 s). Screenshots
at 35 / 50 / 65 / 75 s all show the **title screen**: *2010 FIFA WORLD CUP SOUTH AFRICA(TM)* with
**"PRESS START"** (blinking) and "© 2010 Electronic Arts Inc." So this boot was **parked waiting for
input** and never reached the save-preparation path. Why Boot 1 advanced and Boot 2 did not is
**not established** (INFERRED: an input/controller event in Boot 1); it is reported rather than
explained.

**Which keys to press (for the manual test).** The runtime logs a real **`Xbox Series X
Controller`** being detected (`SDL OnControllerDeviceAdded`), so a gamepad works with no
configuration. For the **keyboard**, note that `mnk_mode` **defaults to `false`**
(`REXCVAR_DEFINE_BOOL(mnk_mode, false, ...)`, `src/input/mnk/mnk_input_driver.cpp:31`), so keys do
nothing until it is enabled - via the **F4** settings overlay (`bind_settings`, `rex_app.cpp:417`),
the command line (`--mnk_mode`, or `--no-<name>`/`--<name> true` per `include/rex/cvar_cli.h`), or
`D:\FWC10\world-cup-2010-pc-port\dist\Output\worldcup2010.toml` with `mnk_mode = true`
(the config path is `exe_dir / (<name> + ".toml")`, `src/ui/rex_app.cpp:~150`; it does not exist yet).
With `mnk_mode` on, the default binds are:

| pad | keys | pad | keys |
|---|---|---|---|
| **Start** | **`X` or `Enter`** | **A** | **`;` or `Space`** |
| B | `'` or `Backspace` | X | `L` |
| Y | `P` | Back | `Z` or `Tab` |
| D-pad | `Shift`+arrows | left stick | `W` `A` `S` `D` |
| right stick | arrows | LB / RB | `1` / `3` |
| LT / RT | `Q` or `I` / `E` or `O` | L3 / R3 | `F` / `K` |

Other runtime hotkeys: **F4** settings overlay, **Home** statistics overlay, **`** (backtick)
console, **F7** achievements. **Navigation (INFERRED - not verified by hand):** on the title screen
press **START** (`X`/`Enter`, or the controller's Menu button) to leave it, then confirm the
language with **A** (`;`/`Space`), then move with the stick/D-pad to the **favourite-team** selection
and confirm with **A**.

### Item 3 - the XAM surface this game actually uses, and the save-device answer (VERIFIED, source-quoted)

The game's **import tables** (from the read-only `D:\FWC10\xenia\xenia.log`, which Xenia prints per
XEX) are the authoritative "what the game asks for". `default.xex`: `XamContentCreateEx` (601),
`XamContentClose` (602), `XamContentCreateEnumerator` (604), `XamContentGetDeviceData` (606),
`XamUserGetSigninInfo` (551), `XamUserGetSigninState` (528). `fifadllzf.xex`: the content family
above plus `XamContentDelete` (603), `XamContentGetCreator` (610), `XamContentGetLicenseMask` (614),
`XamContentGetDeviceState` (613), `XamUserReadProfileSettings` (**0x219**/537),
`XamUserGetXUID` (522), `XamUserCreateAchievementEnumerator` (750), `XamUserCheckPrivilege` (530),
`XamUserAreUsersFriends` (531), `XamUserGetName` (526), `XamUserGetSigninInfo`,
`XamUserGetMembershipTierFromXUID` (535), `XamUserGetOnlineCountryFromXUID` (536),
`XamShowSigninUI` (700), `XamShowAchievementsUI` (709), `XamShowMarketplaceUI` (711),
`XamShowDeviceSelectorUI` (715), `XamShowDirtyDiscErrorUI` (729),
`XamShowMarketplaceDownloadItemsUI` (743), the `XamInput*` family, `XamAlloc`/`XamFree`/`XamEnumerate`,
etc. Resolved **dynamically** with `XexGetProcedureAddress` in our log:
`0x00000279` -> `XamContentAggregateCreateEnumerator`, `0x00000271` -> `XamContentCreateInternal`,
`0x00000270` -> `XamContentDeleteInternal`; at module load `0x00000AFF` -> `XamPartyGetUserList`,
`0x00000B00` -> `XamPartySendGameInvites`, `0x00000B0B` -> `XamPartySetCustomData`,
`0x00000B10` -> `XamPartyGetBandwidth`, `0x00000305` -> `XamShowPartyUI`,
`0x0000030B` -> `XamShowCommunitySessionsUI` (names from `kernel/xam/export_table.inc`).

**Implemented vs stub in our runtime** (`REX_EXPORT` = implemented, `REX_EXPORT_STUB` = stub):

| export | ours | source |
|---|---|---|
| `XamContentCreateEx` / `CreateInternal` / `CreateEnumerator` | implemented | `xam_content.cpp:422 / 424 / 421` |
| `XamContentClose` / `Delete` / `DeleteInternal` | implemented | `xam_content.cpp:427 / 431 / 432` |
| `XamContentGetCreator` / `GetLicenseMask` | implemented | `xam_content.cpp:428 / 419` |
| `XamContentAggregateCreateEnumerator` | implemented | `xam_content_aggregate.cpp:157` |
| `XamContentGetDeviceName` / `GetDeviceState` / `GetDeviceData` / `CreateDeviceEnumerator` | implemented | `xam_content_device.cpp:175-178` |
| `XamContentGetDefaultDevice` | **STUB** | `xam_content_device.cpp:183` |
| `XamUserReadProfileSettings` / `GetXUID` / `GetSigninState` / `GetSigninInfo` / `GetName` | implemented | `xam_user.cpp:738 / 733 / 734 / 735 / 736` |
| `XamUserCheckPrivilege` / `AreUsersFriends` / `CreateAchievementEnumerator` / `GetMembershipTierFromXUID` | implemented | `xam_user.cpp:742 / 751 / 753 / 774` |
| `XamUserGetOnlineCountryFromXUID` **(imported!)** | **STUB** | `xam_user.cpp:775` |
| `XamShowSigninUI` | implemented | `xam_user.cpp:752` |
| `XamShowAchievementsUI` / `XamShowMarketplaceUI` / `XamShowMarketplaceDownloadItemsUI` **(all imported!)** | **STUB** | `xam_ui.cpp:586 / 635 / 631` |
| `XamShowDeviceSelectorUI` / `XamShowDirtyDiscErrorUI` / `XamShowPartyUI` / `XamShowCommunitySessionsUI` | implemented | `xam_ui.cpp:570 / 571 / 572 / 573` |
| `XamPartyGetUserList` / `SendGameInvites` / `SetCustomData` / `GetBandwidth` | implemented | `xam_party.cpp:47-50` |

So **every content and user export this game imports is implemented**; the only stubs among its
imports are `XamUserGetOnlineCountryFromXUID` and three `XamShow*UI` functions (presentation only).
A `REX_EXPORT_STUB` is `REX_STUB`, which only logs - it **does not write r3**, so a stubbed call
returns its first argument unchanged (`include/rex/hook.h:50-55`).

**What the game sees when it asks for a save device, and what Xenia returns.** The game does **not**
call `XamContentGetDefaultDevice` (it is not in either import table - so its being a stub is
irrelevant here; Xenia's `xam_content_device.cc` has no implementation of it either). It uses
`XamContentGetDeviceData` / `XamContentCreateEnumerator` / `XamContentGetDeviceState`, then
`XamContentCreateEx`. Our implementations return a **dummy device table**
(`xam_content_device.cpp:38-52`): **HDD** `id 1 / type 1(HDD)`, 20 GB total, **3 GB free**,
`"Dummy HDD"`; **ODD** `id 2 / type 4(ODD)`, 7 GB, 0 free, `"Dummy ODD"`. So
`XamContentGetDeviceState(1|2)` -> `X_ERROR_SUCCESS` and anything else ->
`X_ERROR_DEVICE_NOT_CONNECTED`; `XamContentGetDeviceData(1)` -> those fixed numbers. Xenia's version
of the same file is identical in shape with two differences: its **fallback** HDD claims **10 GB**
free, and for a HDD it reports `content_manager()->GetContentTotalSpace()/GetContentFreeSpace()`
(the real host disk) instead of the constants; and Xenia's `XamContentCreateDeviceEnumerator`
**skips the ODD when `kExcludeReadOnlyDevices` is set**, which ours does not. A successful
`XamContentCreateEx` in our runtime goes `xeXamContentCreate` -> `ContentManager::CreateContent` ->
`ContentPackage`, which registers a `HostPathDevice` at **`\Device\Content\<n>\`** plus a symbolic
link `<root_name>:` (`src/system/xam/content_manager.cpp:39-53`) - i.e. **a save would be a real
host directory**, with the header written by `WriteContentHeaderFile`. **Xenia actually did this**:
its log shows `~ContentPackage: Closing package: rmcsave (Device: \Device\Content\3\) Device
mounted: Yes` (and `\Device\Content\4\`), and on disk
`D:\FWC10\xenia\content\E03000007F393D8F\454108E4\00000001\WCSettings0 20261017134145\...`
(494,349 B) with a 40,960 B `.header`. **Caveat (INFERRED):** our runs 013-016 contain **zero**
content/save calls, so our save path has still never been exercised end-to-end.

### Item 4 - the corrected (Round-25) candidate pool: **NOT APPLIED**

The 36-entry batch is withdrawn (see the banner in the Round 24 section). The corrected pool from
`round25_scan_candidates.json` (563 non-registered candidates -> 87 valid -> **12 tier A** = true
gap, no static 32-bit occurrence, no jump-table dispatch before it) is **NOT APPLIED** and is listed
here so it cannot be lost. `0x837FD0F0` is in this list and has since been applied as part of the
nine-thunk family, so **11 of the 12 remain unapplied**:

```toml
# NOT APPLIED - corrected tier A (Round 25). Round 24's 36-entry batch is WITHDRAWN.
"82AC37F8" = { end = 0x82AC3808 }   # applied in Round 26 (nine-thunk family)
"837FD0F0" = { end = 0x837FD100 }   # <- applied in Round 26; the other 11 below are NOT
"82ACD630" = { end = 0x82ACD648 }   # 6 insns
"82EE77B0" = { end = 0x82EE77C4 }   # 5 insns
"82FEF818" = { end = 0x82FEF830 }   # 6 insns
"82685B18" = { end = 0x82685B34 }   # 7 insns
"826AEAA0" = { end = 0x826AEAB8 }   # 6 insns
"827B69B0" = { end = 0x827B69C0 }   # 4 insns
"82ED2298" = { end = 0x82ED22B0 }   # 6 insns
"837AC820" = { end = 0x837AC830 }   # 4 insns
"82706360" = { end = 0x8270637C }   # 7 insns
"83097038" = { end = 0x8309703C }   # 1 insn
```

(Only `82AC37F8`, `82EE77B0`, `82685B18`, `837FD0F0` are real tiers-colleagues-of-the-same-pattern;
none has been validated as deeply as the nine just applied. **Do not apply without a fresh
pre-application audit.**)

### The new stop: analysis and the smallest proposed fix (**NOT APPLIED**)

`0x8295FB50` is **not** a vtable dispatch thunk this time. Facts:

* It is a **2-instruction tail fragment**: `0x8295FB50: li r4,1` / `0x8295FB54: b 0x8295F988`, i.e.
  it re-enters the head of the function at `0x8295F988` with `r4 = 1`. Right after it, at
  `0x8295FB58`, sits the **already-registered** twin `li r4,0 ; b 0x8295F988` (2 insns,
  `0x8295FB58..0x8295FB60`).
* The nearest registered entry below is `0x8295F988`, whose extent ends **exactly** at `0x8295FB50`;
  the target is **not inside** any registered extent. The whole `0x8295F988..0x8295FB60` region is
  tail-branch chained (no `blr` anywhere in it).
* **The pointer table** (`0x823AF8E4..0x823AF95C`, 15 code-pointer/aux pairs) contains code pointers
  `0x8295EBE8, 0x8295ECF8, 0x8295EDD0, 0x8295FB50, 0x82960300, 0x8295FCA8, 0x8295FC30, 0x8295FEF8, ...`
  - **all are registered starts except `0x8295FB50`**, which is the crash target. That is
  self-consistent, independent evidence that the analyzer missed exactly this one entry.
* There is **no `lis`+`ori/addi` pair** that builds `0x8295FB50`; it occurs once in the image, as the
  data word at `0x823AF8FC`.
* Call site: `LR = 0x829658CC`, immediately after a four-level vtable walk
  `lwz r11,20(r31) / lwz r11,4(r11) / lwz r11,0(r11) / lwz r11,16(r11) / mtspr CTR,r11 / bcctrl`.

**Proposed smallest fix (NOT applied):** `"8295FB50" = { end = 0x8295FB58 }` - the 8-byte extent
that ends exactly where the registered `0x8295FB58` begins. Honest caveat: the global scan for
"other code-pointer words that are neither registered nor inside a registered extent" returns
**28,040** hits, which is dominated by data that merely aliases the code range; that scan is
**not** trustworthy and no family is proposed from it.

### Verification vs inference (Round 26)

* **VERIFIED:** the nine thunks' decode, 16-byte extents, boundaries, lack of overlap, and
  `0x837FD180` being registered; the 281-entry provenance audit (2 pair-built, 0 buggy-provenance,
  279 other); both override copies' sizes/hashes and byte-identity; the build wall time and exit
  code; every new `sub_` emitted and registered in the fifadllzf module; the old crash's absence and
  the new stop's exact address/registers in `015`; boot 2's no-crash and its title-screen
  screenshots; the import tables and the implemented/stub split (source lines quoted); the dummy
  device table and `\Device\Content\<n>\` backing; Xenia's `rmcsave` mount and on-disk `WCSettings0`;
  the new target's shape, neighbours and unique table occurrence.
* **INFERRED:** that the 607.9 s build is slower than Round 24's 446 s because of concurrent
  analysis; that the new stop lies in the same `WCSettings0`-preparation flow (it follows the
  ordinals by 29 s); that Boot 1 advanced because of an input/controller event; the exact key
  sequence to the favourite-team screen; that the save path would work once reached (never called).

### Round 26 artefacts

`round26_item1.py` / `_out.txt` (nine-thunk + 281-audit evidence), `round26_apply.ps1` (backup +
apply), `round26_two.py`, `round26_stop2.py` / `_out.txt` (new stop), `round26_stop2_region.py` /
`_out.txt` (region disassembly), `round26_table.py`, `round26_family.py` / `_out.txt`,
`round26_tierA.py` / `round26_tierA2.py` (corrected pool), `round26_showjson.py`,
`round26_run2.ps1` (second boot), `round26_build.log`. Screenshots:
`...\round24_shots\shot4_22s.png` (legal screen), `...\round26_shots\late_{35,50,65,75}s.png`
(title screen). Backup:
`D:\FWC10\_backups\20261018-105001-r26` with `SHA256SUMS.txt`.

**Xenia was not run this round and `D:\FWC10\xenia` was not written to** (only `xenia.log` and
`content\` were read); `C:\FWC10B\xenia_dbg` was not touched. **No crash dump or log was deleted**;
`logs\worldcup2010_013..016.log` and the two dumps all remain.
---

## Round 27 (2026-10-18) - single override 0x8295FB50 applied; the crash is fixed; the game reaches gameplay

**Box:** backup + one override change + **one rebuild** + one unattended boot + one driver test boot + no Xenia run.

### What the user approved, and what changed (VERIFIED)

* **Approved:** the single override entry `"8295FB50" = { end = 0x8295FB58 }` - an 8-byte tail fragment `li r4,1 ; b 0x8295F988` whose twin `0x8295FB58` (`li r4,0 ; b 0x8295F988`) is already registered and ends at its own `b`. Evidence from `round27_item1.py` / `item1b.py` / `item1c.py`:
  - both halves decode to exactly 2 instructions (8 bytes each), adjacent and disjoint, both jump to `0x8295F988`;
  - the registered twin `0x8295FB58` has extent `0x8295FB58..0x8295FB60`, ending at its own terminator `b`;
  - the previous registered entry `0x8295F988` ends exactly at `0x8295FB50`; no registered entry lies strictly between them;
  - the 15-record table at `0x823AF8E0..0x823AF958` is `{.data ptr (.data), .text code ptr}` pairs; 14 of 15 code pointers are registered starts; **only** unregistered code pointer is `0x8295FB50` (record 4, data ptr `0x83913364`);
  - no overlap with any registered extent or with the 290 applied overrides; target not already an override start â†’ **SAFE**.

* **Both override copies changed, byte-identically:**

  | | before | after |
  |---|---|---|
  | bytes | 16,464 | **17,727** |
  | entries | 290 | **291** |
  | SHA-256 | `89B6D4D33BF11037FE259FEAA23175D0EE0276BC80F9A1032E7FA26A89A8B36E` | **`6DE35890AE9D8A6C5043CEDF56331D82040B15EDFFAB195A49B2F714E9D2B0F3`** |

  Copies: `D:\FWC10\world-cup-2010-pc-port\Installer\recomp-template\config\fifadllzf_overrides.toml` and `C:\FWC10B\fwc10stage4\WorldCup2010Rex\config\fifadllzf_overrides.toml` (compared byte for byte).

* **Backup:** `D:\FWC10\_backups\20261018-125321-r27` - `fifadllzf_overrides.{A,B}.{before,after}.toml`, `NOTES.md.before`, `git-HEAD.txt`, `sdk-src-state.txt`, `SHA256SUMS.txt`. `LAST_BACKUP.txt` appended.

* **One rebuild:** `Installer\BuildWorldCup2010.ps1 -SourceBuild -Jobs 2`, **wall 422.9 s**, `BUILD_EXIT_CODE=0`. The new function `sub_8295FB50` is emitted in the **fifadllzf** module (`generated\fifadllzf_xex\`) in `worldcup2010_funcs.h` (DECLARE), `worldcup2010_init.cpp` (table entry), `worldcup2010_recomp.183.cpp` (body: `ctx.r4=1; sub_8295F988(ctx,base);`), and `worldcup2010_register.cpp:14415` (`SetFunction(0x8295FB50, sub_8295FB50)`). Registered entries: **87,195** (was 87,194).

* **Boot 1 (unattended, 240 s, `worldcup2010_017.log`):** **NO CRASH** - 104 lines, zero `FATAL`/`INVALID INDIRECT`. The game loaded team/kit assets (hair, accessory, banner textures) and rendered a full 3D stadium (Norway vs Sweden). Screenshots at 20/40/60/80/100 s show progression from title â†’ team selection â†’ stadium. One on-demand commit (page `0x0006C000`).

* **Boot 2 (driver test, 69.6 s, `worldcup2010_018.log`, `--mnk_mode`):** standalone input driver (`round27_input_driver.ps1`) launched the game with `--mnk_mode`, confirmed its own top-level window, **checked foreground before every send** (refused to type elsewhere), and sent:
  1. `Return` (Start) â†’ title â†’ **team flag grid** (favourite-team screen)
  2. `Return` â†’ language confirm
  3. `Space` (A) â†’ select
  4. `Shift+Down` (D-pad down)
  5. `Space` (A) â†’ confirm
  Screenshots saved to `round27_shots\`; driver log at `C:\Users\ramic\AppData\Local\Temp\opencode\round27_input_driver.log`. **Stop the driver:** Ctrl+C in its console, close the game window, or wait for `-MaxSeconds` (it kills the game and releases held keys).

* **Xenia was not run** and `D:\FWC10\xenia` was not written to (newest write still `2026-10-17 14:44:51`); `C:\FWC10B\xenia_dbg` was not touched. **No crash dump or log was deleted**; `logs\worldcup2010_001..018.log` and all screenshots remain.

### Verification vs inference (Round 27)

* **VERIFIED:** the target/twin decode, registration status, table structure (15 records, data vs code sections), unique unregistered code pointer, no overlap; both override copies' sizes/hashes/byte-identity; the build wall time and exit code; the new `sub_` emitted/registered in four generated files; boot 1's 240 s no-crash and its asset-load/stadium screenshots; boot 2's driver test progression (screenshots confirm team-flag grid reached); the driver's foreground-check logic.
* **INFERRED:** that the driver's key sequence is the "correct" one (it reached the favourite-team screen, but the exact menu depth wasn't verified by hand beyond that); that no further crashes will appear (the 240 s run is encouraging but not exhaustive); that the save-device path (never exercised) would work as implemented.

### Round 27 artefacts

`round27_item1.py` / `_out.txt` (core evidence), `round27_item1b.py` / `_out.txt` (every 4-byte word of the table), `round27_item1c.py` (section of each pointer), `round27_apply.ps1` (backup + apply), `round27_verify.py` / `_out.txt` (emission check), `round27_build.cmd` / `round27_build.log` (build), `round27_run.ps1` (unattended boot), `round27_input_driver.ps1` / `round27_input_driver.log` (driver + test boot), `round27_boot1_out.txt` (unattended boot transcript). Screenshots: `...\round27_shots\r27_{20,40,60,80,100}s.png` (unattended), `...\round27_shots\1352*_*.png` (driver test). Backup: `D:\FWC10\_backups\20261018-125321-r27` with `SHA256SUMS.txt`.

---

# Round 28 (2026-10-19) - throw-in crash triage, save-path audit, three diagnostic hunks

**Box:** one timestamped backup, 10 per-file patches, **one rebuild**, **one unattended boot**.
**No Xenia run**; `D:\FWC10\xenia` and `C:\FWC10B\xenia_dbg` were **read-only** (Xenia was not run at
all). Every claim below is tagged **VERIFIED** (I read the bytes/source/log) or **INFERRED**.

## The crash, re-read from `worldcup2010_019.log` (VERIFIED)

```
[22:50:25.395] Guest virtual read of 0x00000021 (host 0x0000000100000021) committed on demand
               as page 0x00000000 (recommit); total 2          <- hidden by the workaround
[22:50:25.402] INVALID INDIRECT CALL: target=82486704 LR=8333DB7C CTR=82486704
               r1=7019E740 r2=00000000 r3=BE4545F8 r11=825227F8 r12=8333DB44
```
Same thread `t24456`, 7 ms apart; registered functions = 87,195.

## Corrections to the Round-28 brief

* **(a) ACCEPTED (VERIFIED).** `0x8333DB68 lwz r9,760(r30)` / `0x8333DB6C addi r3,r30,760` /
  `0x8333DB70 lwz r8,20(r9)` / `0x8333DB74 mtctr r8` / `0x8333DB78 bcctrl`. `CTR` = **the value
  stored at** `r9+20`. `0x82486704` is that stored value, **not** the address `r9+20`; `r9` was not
  logged. Any earlier claim of the form "r9 = 0x824866F0" is **withdrawn**.
* **(b) ACCEPTED (VERIFIED).** Bytes at `0x82486704` = `45 41 53 54 4C 20 62 61 …` =
  `"EASTL basic_string"` (`.rdata`, repeated; preceded by `"LayoutData"` at `0x824866F8`). It is a
  pointer to that string literal.
* **(c) PARTLY WRONG - corrected (VERIFIED).** The function starts at `0x8333D4E0`, but the **next
  registered start is `0x8333DCF8`**, and the **next `.pdata` record is also `0x8333DCF8`**
  (`0x8262B078 -> 0x8333D4E0` with info `0x4002050B`, `0x8262B080 -> 0x8333DCF8`). The extent is
  therefore `0x8333D4E0 .. 0x8333DCF8`, **not** `.. 0x8333DCD0` (which is 0x28 short of the end).
  `LR=0x8333DB7C` is inside it at `+0x69C`, so the "inside-or-after" logic is unaffected.
* **(d) CONFIRMED (VERIFIED from disk).** The old "enumerator added 0 items" observations predate the
  first save; no log yet shows what the enumerator returns while six saves exist.
* **(e) RETRACTED.** No Round-28 analysis depended on "the same assets fail in Xenia"; no Xenia run
  was made and no Xenia line is quoted.

## NEW deduction - `r30 = 0xBE454300` (VERIFIED arithmetic)

At the trap `r3 = 0xBE4545F8` (logged). The instruction immediately before the call is
`addi r3,r30,760` (`0x8333DB6C`) and nothing between it and the `bcctrl` writes `r3`. Therefore
**`r30 = 0xBE4545F8 - 760 = 0xBE454300`**. `r30` was not logged; this recovers it. Also (VERIFIED):
`r30` at the crash is **not** `parent+0x230` - it is overwritten at `0x8333DB04 mr r30,r3`, the return
value of the virtual call at `0x8333DAF8` (slot `+8` of the object at `parent+0xE0`). The crashing
call is `(&(call1_result + 0x2F8))->vtable[+0x14]`.

## Task 1 - static crash analysis (`round28_t1.py`, `round28_t1b.py`)

**_(i) cross-references to `0x82486704`._**

* **Data-word occurrences** (32-bit big-endian `== 0x82486704`) in `.rdata`/`.pdata`/`.data`:
  **NONE** (VERIFIED). No emulator-side static table slot points at the string.
* **Code materialisation** (`lis` + sign-correct `addi`/`ori`, dataflow over `.text`): exactly **one**
  site (VERIFIED):
  ```
  0x82F3BFD8  lis  r10,0x8248
  0x82F3BFE0  addi r10,r10,0x6704      ; r10 = 0x82486704
  ```
  (A secondary literal scan reports two window matches, but both are the same `addi` preceded by the
  two adjacent `lis r11`/`lis r10` at `0x82F3BFD4/D8`, so it is one site.)
* **What builds the object** (function `0x82F3BFC8..0x82F3C080`, VERIFIED): it stores the other string
  `0x82487D90` at `0(r3)`, stores `0x82486704` on the **stack** at `80(r1)`, sets `r5 = r1+0x50`, and
  calls a constructor-like routine (`0x82F3C008`); it then fills a small array of `{0,0,0,nameptr}`
  records (`24(r31)=0 … 64(r31)=0, 68(r31)=nameptr`). The string is materialised as a **name
  argument**, never stored at a fixed `object+0x14`.
* Consequence (INFERRED): the value at `(r9+20)` cannot come from static data, so it is a
  runtime-written heap field. `r9` is a structure whose `+0x14` field is a `const char*` name (an
  EASTL allocator/type-name string) - **not** a C++ vtable of the type the call expects.

**_(ii) stores to `+0x2F8` and vtable installs (VERIFIED)._**

* **70** stores with displacement 760 exist in `.text`. Exactly **3** store a pointer *constant*;
  only **2** are genuine vtables:

  | site | stored value | first words | all registered starts? |
  |---|---|---|---|
  | `0x82A4B8E4 stw r5,760(r31)` | `0x823C8460` (`.rdata`) | `82A53980 82A48060 82975CB8 …` | **yes** |
  | `0x83088C14 stw r9,760(r15)` | `0x8308005E` (`.text`) | `7FA8EB78 80E10050 …` | no (code ptr, not a table) |
  | `0x833C88D4 stw r9,760(r31)` | `0x8253E2EC` (`.rdata`) | `82A53980 833B3FD0 82A53940 …` | **yes** |

  Neither real vtable has a data word at its `+0x14` slot.
* **67 of 70** stores write a *heap pointer* (`stw r28/r29/r30/r31,…`) into `+0x2F8`, i.e. in most
  types `+0x2F8` is a plain pointer field, not an embedded polymorphic object.

**_(iii) stale / wrong type / unpopulated?_** **Not decidable from the image alone.** The evidence
points at **wrong object type (or an unpopulated field)** rather than a dangling pointer, but that is
INFERRED, not proven: `*(r9+0x14)` is a pointer to a name string only ever produced as a constructor
name argument (i); and `r9` is **not** one of the image's two `+0x2F8` vtables (ii), so the object at
`r30+0x2F8` is not one of those types, or its vptr was clobbered. **What would settle it:** the
runtime values of `r30` and `r9`, the words at `r30+0x2F8` and around `r9` - exactly what **Hunk B**
logs.

**_(iv) callers of `sub_8333D4E0` (VERIFIED)._** `0x825362C4` (`.rdata`) `= 0x8333D4E0`, **slot 4** of
a contiguous table at `0x825362B4..` (`8333CF80 83340908 8332EF30 8332F3F8 8333D4E0 83342A68 …`) whose
every entry is a registered function start -> `sub_8333D4E0` is a **virtual method**. `0x8262B078`
(`.pdata`) `= 0x8333D4E0`, the function's **unwind record**. The object passed is the `this` behind
vtable `0x825362B4`, not identifiable from data alone; its role is named only from code (the crash
frame chains virtual calls on `parent+0xE0` slot `+8`, then on `(result+0x2F8)` slot `+0x14`).

**_(v) the null read of guest `0x21` (VERIFIED)._** No load with displacement `0x21` exists inside the
LR function **or** inside any of its 12 distinct direct callees. The null read is therefore deeper (an
indirect/virtual callee) or elsewhere on the same thread; the single `LR` does not pin the
instruction. The original AV is absent from the log because the `kGuestVirtual` on-demand-commit
workaround committed page 0 and resumed - **Hunk A restores the fatal path** so the AV and its
register state now appear.

## Task 2 - why the game may not see its saves (source audit, no build)

* **Our content root** = `C:\Users\ramic\Documents\worldcup2010` (VERIFIED chain: no `user_data_root`
  cvar; `rex_app.cpp` uses `GetUserFolder()/GetName()`; `GetName() == "worldcup2010"`).
* **Our aggregate enumerator** (`src\kernel\xam\xam_content_aggregate.cpp:82-151`, VERIFIED) uses the
  **caller's `xuid` verbatim** (no `-1 -> 0` normalisation), **ignores the 4th argument** (our named
  `unk3`; Xenia names it `title_id`), scans `root/<xuid>/<title>/<type>/`, and fills each item from
  `Headers/<type>/<name>.header` when present.
* Disk facts (VERIFIED): our store holds **six** saves under `B13EBABEBABEBABE\454108E4\00000001\`
  with matching `Headers\00000001\*.header`; **Xenia's** single save is in a *different* store
  (`D:\FWC10\xenia\content`) under a *different* XUID (`E03000007F393D8F`).
* Therefore Xenia's save is invisible to us for two independent reasons (store + XUID), **and** our
  own six saves sit exactly where `ListContent` scans. The premise "the game cannot find its saves" is
  **not demonstrated** by the source or the disk.
* The one decisive unknown is the `xuid`/`device_id`/`content_type`/`title_id` the game actually
  passes - it is not in the log. **Hunk C** logs those arguments and the resulting item count at INFO,
  which settles it.

## Task 3 - patches (separate per-file diffs in `patches\`)

Each carries a BSD-3 header and an off switch (`ROUND28_HUNK_A`, `ROUND28_HUNK_B`, `ROUND28_HUNK_C`;
pass `-D<name>=0` to compile the hunk out - each `.cpp` also has an `#ifndef` default of 1).

| patch | target | SHA-256 (patch) |
|---|---|---|
| `round28-A-src_system_xmemory.cpp.patch` | `src/system/xmemory.cpp` | `370E22BB205B07D8F2BD43EA587B83186CADAF1653CB02BB47425164BFBC13E2` |
| `round28-B-include_rex_system_function_dispatcher.h.patch` | `include/rex/system/function_dispatcher.h` | `3FE36A39059E8512EEF09FDCA9FC67F42CC3BAEFED7489BEA1D93F1D9B3DDAC9` |
| `round28-B-src_system_function_dispatcher.cpp.patch` | `src/system/function_dispatcher.cpp` | `FB95B47D671BBF4361261D627E077232EE2414EBBBAB12D506BA9FD42A478A49` |
| `round28-B-src_system_xmemory.cpp.patch` | `src/system/xmemory.cpp` | `226C255269F6F3B87E62B3EEAE130E042F7BA5E6D200923C02CB53105F9C5736` |
| `round28-C-src_kernel_xam_xam_content.cpp.patch` | `src/kernel/xam/xam_content.cpp` | `3D3AB0F4B0980ED69A52709592FACF11BA4DD236B1D08467DB96405BD4C48FF3` |
| `round28-C-src_kernel_xam_xam_content_aggregate.cpp.patch` | `…xam_content_aggregate.cpp` | `A20074F8B1AB5102633D29B132257D3FD78E6B73B36D9A088849559C80E285F8` |
| `round28-C-src_kernel_xam_xam_content_device.cpp.patch` | `…xam_content_device.cpp` | `E7619C9C25301BF2D82F2DB75A36CC18A2CE2AB30A476F899E1938C371F60FA9` |
| `round28-C-src_kernel_xam_xam_ui.cpp.patch` | `…xam_ui.cpp` | `796A4CC3A4248A5561826C68030BEB12A8D3DB3D4895F132A6EC419588755FB3` |
| `round28-C-src_kernel_xam_xam_user.cpp.patch` | `…xam_user.cpp` | `46A258223DD75E4D46D5741E2660DDB53978BAAA102C383772F8F66BBA4241A5` |
| `round28-C-src_system_xam_content_manager.cpp.patch` | `src/system/xam/content_manager.cpp` | `675F5A3DDD6751DFAE1A5563F2B2135AFBAFF71FC592FB8C0F56E5AC69B9D4B5` |

* **A** - in `Memory::AccessViolationCallback`, refuse the on-demand commit when
  `fault_page < 0x10000`, log `Null-page access: … refusing on-demand commit below 0x10000; falling
  through to the fatal path`, and let the existing fatal path run. Addresses `>= 0x10000` (including
  the `0x6C000` first-touch case) are unchanged.
* **B** - `Round28DumpGuestContext()` (shared by the invalid-indirect-call trap and the guest-AV
  handler) prints **all** `r0..r31`, `LR`, `CTR`, the nearest registered function below `LR`
  (`FunctionDispatcher::FindContainingFunctionStart`, a sort + binary search over the same table the
  dispatcher registers from `PPCFuncMappings`), the module base, and a bounded 64-byte,
  **page-commit-checked** hex dump of `r3,r8,r9,r11,r30,r31` and of each pointee.
* The lookup was **validated** against statically-known pairs (`round28_lookup_check.py`):
  `0x8333DB7C -> 0x8333D4E0 (+0x69C)`, `0x8333D5A0 -> 0x8333D4E0 (+0xC0)`,
  `0x8333DB68 -> 0x8333D4E0 (+0x688)` - all OK. **Nearest-lower cannot prove containment** (an
  address in a gap still returns the previous start); the dump prints the offset and warns when it
  exceeds `0x40000`.
* **C** - INFO tracing (`ROUND28C `) of `XamContentCreateEnumerator` /
  `XamContentAggregateCreateEnumerator` (args + item count), `xeXamContentCreate` (root, flags,
  type/title/xuid, disposition, result), `XamContentCreateEx/Internal`, `XamContentClose`,
  `XamContentDeleteInternal`, `XamContentGetDeviceData/State`, `XamUserRead/WriteProfileSettings`,
  `XamUserGetSigninState`, `XamShow{MessageBox,DeviceSelector,DirtyDisc}UI`, and
  `ContentManager::ListContent` (scanned root, each item's name + header-read result, total count) +
  `OpenContent` (path, exists).
* `git apply --check` on a pristine copy of every touched file: **all 10 OK**. (The first build
  exposed `uint32_t(be<XContentType>)` casts in `xam_content.cpp`; fixed to `.get()`, patches
  regenerated, re-checked, re-applied.)

## Task 4 - build + boot

* **Backup:** `D:\FWC10\_backups\20261019-095738-r28` - `files\` holds the pre-patch content of all
  9 touched files; the 10 `round28-*.patch`; `git-HEAD.txt`, `git-status-porcelain.txt`,
  `SHA256SUMS.txt`, `README.txt`. `LAST_BACKUP.txt` appended.
* **Rebuild:** `Installer\BuildWorldCup2010.ps1 -SourceBuild -Jobs 2` (via `round28_build.cmd`).
  First attempt failed on the `be<XContentType>` cast (above); after the fix the rebuild succeeded,
  and all Round-28 files compiled without error.
* **Boot (unattended, 150 s, killed at the cap):** `dist\Output\logs\worldcup2010_020.log` (plus
  rotations `.1`, `.2`; the logger caps a file at 5 MB), 10:15:26 -> 10:17:56. Five screenshots at
  20/40/60/90/120 s (`round28_shots\r28_*.png`). **No `FATAL`, no `INVALID INDIRECT CALL`, no
  `Null-page access`, no `ROUND28 guest context`** - the game sat at the title/menu (no hand input),
  so hunks **A** and **B** produced no output. That is expected: the throw-in crash needs hand-played
  gameplay.
* **Hunk C is live** and the content/store trace ran. **The save problem is now explained (VERIFIED
  from the log):**

  ```
  [10:15:27] XamContentCreateEnumerator user_index=254 content_type=00000002 ... -> items=0
             (ListContent scanned xuid=B13EBABEBABEBABE, i.e. the runtime xuid)
  [10:16:09] XamShowDeviceSelectorUI user_index=0 content_type=00000001 ... -> device_id=0x00000001
  [10:16:09] XamContentAggregateCreateEnumerator args xuid=00000000BABEBABE device_id=1
             type=00000001 unk3(title_id?)=00000000 runtime_xuid=B13EBABEBABEBABE
             ListContent scan xuid=00000000BABEBABE type=00000001 title_id=454108E4
               root='C:\Users\ramic\Documents\worldcup2010\00000000BABEBABE\454108E4\00000001'
               -> 0 item(s)
             XamContentAggregateCreateEnumerator xuid=00000000BABEBABE ... -> items=0
  [10:16:09] xeXamContentCreate root='rmcsave' flags=00000034 type=00000001 title_id=454108E4
             xuid=B13EBABEBABEBABE resolved_xuid=B13EBABEBABEBABE
             xeXamContentCreate root='rmcsave' disposition=1 -> result=0x00000000
  [10:16:40] XamContentDeleteInternal type=00000001 title_id=454108E4 -> 0x00000000
  ```

  **The game enumerates user content for xuid `0x00000000BABEBABE`, but our content lives under
  `0xB13EBABEBABEBABE`.** The directory `…\Documents\worldcup2010\00000000BABEBABE\…` does not exist
  (VERIFIED: only `B13EBABEBABEBABE` and `cache` exist), so `ListContent` returns **0 items** and the
  game concludes there are no existing saves. `xeXamContentCreate` then **creates** `rmcsave` (flags
  `0x34` -> disposition `Create`) with `resolved_xuid=B13EBABEBABEBABE`, i.e. the write path and the
  read path use **different** XUIDs. The game then deletes and recreates - the "saves issue".
* **Where the game's `0x00000000BABEBABE` comes from is OPEN (INFERRED):** it is exactly the **low 32
  bits** of our hard-coded `0xB13EBABEBABEBABE` with the high dword zero, i.e. a 32-bit-truncated copy
  of our XUID. Both branches of our `XamUserGetXUID_entry` and our signin info return the full 64-bit
  value, so the truncation is somewhere between our XAM user APIs and the game. This needs one more
  log line on `XamUserGetXUID` / `XamUserGetSigninInfo` before any fix.
* **Volume defect found (VERIFIED):** Hunk C logs `XamUserGetSigninState`, which the game polls **every
  frame from several threads**. In 150 s that produced **8,981 lines / 11.45 MB across three rotated
  files** and buried the real content lines. Patch C as applied does **not** satisfy "cap the volume"
  for this call; the intended fix (log only when the value changes) is **not yet applied**.

## Verification vs inference (Round 28)

* **VERIFIED:** the crash log lines and thread/timing; the four `lis`/`lwz`/`mtctr`/`bcctrl`
  instructions and `r30` recovery; the string bytes and section; the absence of any data-word
  reference and the single materialisation site; the 70/3/2 `+0x2F8` store/vtable counts and both
  vtable dumps; the `.pdata` next-record and registered-next-start both being `0x8333DCF8`; the
  `.rdata` vtable slot `0x825362C4`; the absence of a `0x21`-displacement load in the LR function and
  its 12 direct callees; the content-root resolution and the enumerator's argument handling; the disk
  layout of both stores; all 10 patch hashes and the clean `git apply --check`; the rebuild result.
* **INFERRED:** that `r9` is a name-descriptor rather than a real vtable (static evidence is strong
  but not conclusive); that the null-read instruction is in a virtual callee (not pinned); the origin
  of the game's `0x00000000BABEBABE` (a 32-bit truncation of our XUID is the leading hypothesis, not
  proven).
* **Boot (VERIFIED):** the Round-28 markers are present in the rebuilt `rexruntime.dll`; the run
  reached the title/menu with **no** FATAL/AV/indirect-call (so A/B were not exercised); the save
  trace shows the enumerator querying xuid `0x00000000BABEBABE` (0 items) while create uses
  `0xB13EBABEBABEBABE`; the `XamUserGetSigninState` poll volume (8,981 lines / 11.45 MB in 150 s).

## Open questions / next approval

1. **Stale vs wrong-type** for `r30+0x2F8` cannot be chosen statically; the Hunk-B dump, once the user
   reproduces a throw-in by hand, decides it.
2. **Save bug - root cause found, fix NOT applied.** The game enumerates content for xuid
   `0x00000000BABEBABE` while we store it under `0xB13EBABEBABEBABE` (boot log, above). Candidates,
   none applied: (a) find and fix the 32-bit truncation of our XUID so the game receives the full
   value - needs one log line on `XamUserGetXUID`/`XamUserGetSigninInfo` first; (b) normalise the
   aggregate enumerator's xuid the way Xenia does. The user asked to stop after the boot report, so
   this is **for approval**.
3. **Hunk C volume.** `XamUserGetSigninState` must log **on change only**; as applied it rotates 5 MB
   log files within seconds. **Not applied** (the one-rebuild rule was honoured).
4. Hunk A may make the null read **fatal sooner**, so a run can stop earlier than the throw-in. That
   is intended: the next step is to read *where* it stops, not to re-enable the silent commit.

## Round 28 artefacts

All under `C:\Users\ramic\AppData\Local\Temp\opencode\`: `round28_genpatch.py` (patch generator),
`round28_lookup_check.py` (lookup validation), `round28_t1.py`/`round28_t1_out.txt` and
`round28_t1b.py`/`round28_t1b_out.txt` (static analysis), `round28_build.cmd` / `round28_build.log`
(build), `round28_run.ps1` (boot). Patches: `D:\FWC10\world-cup-2010-pc-port\patches\round28-*.patch`.
Backup: `D:\FWC10\_backups\20261019-095738-r28`.


# Round 29 (2026-10-19) - the XUID is truncated by *our own* argument marshaller; save-path shim + XUID/sign-in tracing

**Box:** one timestamped backup (`D:\FWC10\_backups\20261019-104335-r29`), **5 per-file patches**
(`patches\round29-*.patch`), **one rebuild**, **one unattended 150 s title-screen boot**
(`worldcup2010_022.*`). **Hunks A and B of Round 28 were not touched.** Every claim is **VERIFIED**
(bytes/source/log actually read) or **INFERRED**.

## Headline 1 (VERIFIED): the save bug is a ReXGlue ABI bug, not a game bug

Round 28 established from the log that the title *enumerates* content under
`…\00000000BABEBABE\…` (**0 items**) while it *creates* its save under `…\B13EBABEBABEBABE\…`.
Round 29 finds the truncation and proves it is ours.

**1. The guest passes a correct 64-bit XUID** (VERIFIED, guest disassembly of
`xexdump\fifadllzf.dec.bin`, script `round29_t1_dis.py`). `fifadllzf` reaches the aggregate
enumerator (xam ordinal **0x279**, lazily resolved into the slot at **`0x83C6402C`**) from
`sub_8319C5D0`:

```
0x8319C5DC  li  r11,-1
0x8319C5E8  std r11,80(r1)        ; xuid slot := -1
0x8319C610  lis r11,-31834        ; 0x83C60000
0x8319C614  li  r3,633            ; 0x279 = XamContentAggregateCreateEnumerator
0x8319C618  addi r30,r11,16428    ; r30 = 0x83C6402C  (lazy-resolve slot)
0x8319C620  bl  sub_8319C170      ; resolve(xam!0x279, &0x83C6402C)
0x8319C640  bl  0x838D7E5C        ; XamUserGetXUID(user_index=r29, type_mask=1, ptr=r1+80)
0x8319C654  lwz r11,0(r30)        ; resolved enumerator entry point
0x8319C660  ld  r3,80(r1)         ; *** FULL 64-bit load of the XUID -> arg1 ***
0x8319C664  mr  r5,r31            ; content_type
0x8319C668  mr  r4,r27            ; device_id
0x8319C66C  mtctr r11
0x8319C670  bctrl                 ; aggregate enumerator; guest LR = 0x8319C674
```

`ld` is the **64-bit** load, so `r3` really does hold all 64 bits. The runtime confirmed this guest
address independently: `ROUND29D XamContentAggregateCreateEnumerator caller=0x8319C674 …` (see
below) - the LR predicted statically is exactly the LR observed at run time.

**2. Our marshaller forwards only `r3`'s low 32 bits** (VERIFIED, source).
`include/rex/ppc/function.h`:

```cpp
  static constexpr uint64_t GetIntegerArgumentValue(const PPCContext& ctx, uint8_t* base,
                                                    size_t arg) noexcept {
    if (arg <= 7) {
      switch (arg) {
        case 0:
          return ctx.r3.u32;      // <-- 32-bit read, zero-extended to uint64_t
        case 1:
          return ctx.r4.u32;      // ... r5/r6/r7/r8/r9/r10 likewise
```

`ArgTranslator::GetValue<T>()` routes every plain integer (`u64 = uint64_t`) through this helper, so
`XamContentAggregateCreateEnumerator_entry(u64 xuid, …)` is handed `0x00000000BABEBABE` when `r3` is
`0xB13EBABEBABEBABE`. The defect is **general** (every 64-bit integer argument of every export); it
only bites when the value exceeds 32 bits, which is precisely the XUID.

**3. Every log line is consistent with this** (VERIFIED):

* `ROUND28C XamContentAggregateCreateEnumerator args xuid=00000000BABEBABE … runtime_xuid=B13EBABEBABEBABE`
  - a *register* argument is truncated, a value read from the profile inside our code is not.
* `ROUND28C xeXamContentCreate root='rmcsave' … xuid=B13EBABEBABEBABE resolved_xuid=B13EBABEBABEBABE`
  - the content-data XUID comes out of **guest memory** (a `be<uint64_t>` field), so it is never
  marshalled and stays correct; the create path also uses the profile XUID directly.

**Conclusion VERIFIED by three independent routes** (guest disassembly, marshaller source, run-time
log): the truncation happens in **our runtime**, not in the game. **INFERRED**: on a real console
(and in Xenia) the guest's full register value reaches XAM, so neither sees this.

## Headline 2 (VERIFIED): the shim repairs the enumeration

```
ROUND29D xuid shim[aggregate-enumerator]: requested=00000000BABEBABE -> profile_xuid=B13EBABEBABEBABE
         (upper 32 bits zero, lower 32 bits match) caller=0x8319C674
ROUND29D XamContentAggregateCreateEnumerator caller=0x8319C674 xuid_in=00000000BABEBABE xuid_used=B13EBABEBABEBABE
ROUND28C XamContentAggregateCreateEnumerator xuid=B13EBABEBABEBABE device_id=1 type=00000001 -> items=8
ROUND28C XamContentAggregateCreateEnumerator xuid=B13EBABEBABEBABE device_id=0 type=00000001 -> items=8
```

and the create that follows is now an **open of an existing save** instead of a create:

| run | `xeXamContentCreate` | disposition | result |
|---|---|---|---|
| Round 28 (`020`) | `root='rmcsave' flags=00000034` | `disposition=1` (Create) | `0x00000000` |
| Round 29 (`022`) | `root='rmcsave' flags=00000033` | `disposition=2` (Open) | `0x00000000` |

No new save directory was created by the Round-29 boot, and **no file in the content store was
modified** (newest mtime still `10-19 10:24`); the store still holds exactly the **8**
`WCSettings0 …` saves. In every previous boot the title created a *fresh* save, because it could not
see the old ones.

## Xenia comparison (VERIFIED, read from xenia-canary `canary_experimental`)

Xenia has no truncated-XUID case to normalise. Its only mapping on this path is the all-ones
sentinel - `src/xenia/kernel/xam/xam_content_aggregate.cc`:

```cpp
dword_result_t XamContentAggregateCreateEnumerator_entry(qword_t xuid, …) {
  …
    auto content_datas = kernel_state()->content_manager()->ListContent(
        static_cast<uint32_t>(DummyDeviceId::HDD),
        xuid == -1 ? 0 : static_cast<uint64_t>(xuid), title_id,
        content_type_enum, XContentFlag::kNone);
```

`qword_t` is forwarded by Xenia's shim layer as the **full 64-bit** register value, so `xuid == -1`
is all the special-casing it needs. Our shim (low-32 match -> profile XUID) exists **because** our
argument path loses the high half - it is a workaround for a ReXGlue defect, not a Xenia behaviour
being copied. The profile XUID was **not** changed and no Xenia save file was copied.

Two further Xenia/ReXGlue differences noticed while reading (not bugs for this title, RECORDED):
`XamUserGetSigninInfo` - Xenia writes `info->xuid` only when
`!flags || flags & X_USER_GET_SIGNIN_INFO_OFFLINE_XUID_ONLY`, our copy always writes it (FIFA 10 calls
it with `flags = 0`, so behaviour is identical); `XamUserGetXUID` - Xenia returns early with `0` and
`X_E_NO_SUCH_USER` for a non-signed-in index, ours goes through `user_profile->type() & type_mask`
and can return `X_E_SUCCESS` with `xuid = 0`.

## Task 1 - logging for `XamUserGetXUID` / `XamUserGetSigninInfo`

Both exports now log the value written, the **guest caller**, and the **guest address the guest reads
it back from** (patch `round29-D4-…xam_user.cpp.patch`). 46 `ROUND29D` lines in the whole 150 s run,
43 of them distinct - no spam. What they revealed:

* `XamUserGetXUID user_index=0 type_mask=1 -> 0x00000000 xuid=B13EBABEBABEBABE written_to=0x708EF780
  caller=0x8319C644` - **caller `0x8319C644` is the return address of the `bl` at `0x8319C640`
  inside `sub_8319C5D0`**, and `written_to=0x708EF780` is that function's `r1+80`. So **the reader is
  `sub_8319C5D0` itself**: it re-loads the XUID with the 64-bit `ld r3,80(r1)` at `0x8319C660` and
  passes it straight in as arg1 of the aggregate enumerator. Nothing on that path re-reads it with a
  32-bit `lwz`; the loss happens **after** the guest sets `r3`, in our marshaller.
* the other save-path caller is `0x8319C414` (same wrapper family, the create side); other callers are
  `0x8319BD00` (user enumeration, `type_mask=7`) and `0x831E76AC` (`type_mask=2`).
* for `user_index = 1..3` the export returns `0x80070525` (`X_E_NO_SUCH_USER`) with `xuid = 0`, so
  only index 0 is ever a real XUID.
* `XamUserGetSigninInfo user_index=0 flags=00000000 -> X_E_SUCCESS xuid=B13EBABEBABEBABE
  written_to=0x708EF550 caller=0x8319B948` (also seen from `0x820FB4F8`, and once with `flags=2`).

## Task 2 - per-frame log volume: **the cap did NOT work; this is a defect in my patch**

Requirement: `XamUserGetSigninState` must log only when its returned value changes. As built it still
logs essentially every call:

| | R28 boot (`020`, 150 s) | R29 boot (`022`, 158 s) |
|---|---|---|
| log files | 3 | 4 |
| bytes | 11,455,643 | 16,439,480 |
| `ROUND28C` lines | 105,911 | 108,150 |
| of which `XamUserGetSigninState` | 105,860 | **107,936** |

**Cause (VERIFIED by reading my own patch):** I keyed the "changed?" test on a single
`(last user_index, last value)` pair. The title polls the four indices **round-robin**
(`0,1,2,3,0,1,2,3,…`), so the remembered index never equals the current one and the condition is
always true. The new suffix is even misleading: every one of those line says
`(value changed; per-call repeat suppressed)` although the value did not change. Raw log:

```
11:03:25.479 user_index=2 -> 0x00000000 (value changed; per-call repeat suppressed)
11:03:25.482 user_index=3 -> 0x00000000 (value changed; per-call repeat suppressed)
11:03:25.484 user_index=0 -> 0x00000001 (value changed; per-call repeat suppressed)
11:03:25.484 user_index=1 -> 0x00000000 (value changed; per-call repeat suppressed)
11:03:25.489 user_index=0 -> 0x00000001 (value changed; per-call repeat suppressed)
```

**Fix (not applied - it needs one more rebuild, which Round 29's budget did not allow):** keep one
slot **per user index** instead of one global slot, e.g.

```cpp
    static bool     r29_seen[4]       = {};
    static uint32_t r29_last_state[4] = {};
    bool changed;
    if (user_index < 4) {
      changed = !r29_seen[user_index] || r29_last_state[user_index] != signin_state;
      if (changed) { r29_seen[user_index] = true; r29_last_state[user_index] = signin_state; }
    } else { … one extra slot for out-of-range indices … }
    if (changed) R28C_LOG(…);
```

With that, a 150 s title-screen run should emit **4** `XamUserGetSigninState` lines (one per index,
all values constant), i.e. ~105,000 fewer lines, and the log set should drop from ~16.4 MB to
well under 1 MB. No other per-frame call needed capping: in the 191 s run `worldcup2010_021` every
other `ROUND28C` message was <= 32 occurrences (`ListContent` 32, aggregate/create/enumerator 4 or
fewer, the rest 1-2).

## Task 3 - the shim

`Round29ResolveXuid(requested, site)` (`src/system/xam/content_manager.cpp`, declared in
`include/rex/system/xam/content_manager.h`): when the requested XUID has a **zero upper 32 bits** and
its **low 32 bits equal the current profile XUID's low 32 bits**, it returns the profile XUID;
otherwise the requested value unchanged. Applied to:

| path | site tag | value shimmed | observed |
|---|---|---|---|
| `XamContentAggregateCreateEnumerator_entry` | `aggregate-enumerator` | the marshalled `xuid` argument | **substituted twice** (`00000000BABEBABE -> B13EBABEBABEBABE`) |
| `XamContentCreateEnumerator_entry` | `create-enumerator` | the profile-derived XUID (identity) | unchanged x4 |
| `xeXamContentCreate` | `content-create-data` | `content_data.xuid` from guest memory | unchanged x1 |

Every call logs `ROUND29D xuid shim[<site>]: requested=… -> profile_xuid=… (upper 32 bits zero, lower
32 bits match) caller=0x…`, or `… unchanged caller=0x…`. **Off switch:** the `round29_xuid_shim` cvar
(defined in `content_manager.cpp`, default `true`) disables substitution; the whole hunk compiles out
with `-DROUND29_HUNK_D=0`. The profile XUID is unchanged; no Xenia save file was copied.

## Task 4 - backup, patches, rebuild, boot

* Backup `D:\FWC10\_backups\20261019-104335-r29`: the 5 pre-patch files under `files\`, the 5
  patches, `git-HEAD.txt`, `git-status-porcelain.txt`, `README.txt`, `SHA256SUMS.txt`.
  `_backups\LAST_BACKUP.txt` updated both before and after the rebuild.
* Per-file patches, each `git apply --check` **OK** on a pristine copy of the pre-Round-29 tree:

| patch | SHA-256 |
|---|---|
| `round29-D1-include_rex_system_xam_content_manager.h.patch` | `BA3B60BEC30EF858812C89E3F0D1CE903A9828DADC5D629B21161AA43250D483` |
| `round29-D2-src_system_xam_content_manager.cpp.patch` | `9E6D3326752BA54B6923A118D2306EBB58A81A53C3618372A498470E67909C68` |
| `round29-D3a-src_kernel_xam_xam_content_aggregate.cpp.patch` | `64389AF8F6AE40B1486B655E3BEF48D043D5EF7DCBA18E860C65D6C31E191BD5` |
| `round29-D3b-src_kernel_xam_xam_content.cpp.patch` | `D96706CEDD84AE7097263C833CB9D4F3DE57F1C84CCA06E45D31548FE80DC645` |
| `round29-D4-src_kernel_xam_xam_user.cpp.patch` | `10F46BD6C32CC33409C37765BCD12CA7E55B1FB8E7FEB7683BC2F14A1F90CA0F` |

  Pre-patch SHA-256 of the five targets: `content_manager.h` `6990884D…6B01C4`,
  `content_manager.cpp` `FD61FD12…E46EF7`, `xam_content_aggregate.cpp` `EBC4755F…888859`,
  `xam_content.cpp` `BF725697…A59D08F`, `xam_user.cpp` `221D9362…E38EA55`.
* The four touched translation units were compiled first (`round29_precheck.cmd`, exit 0), then the
  single rebuild: **`BUILD_EXIT_CODE=0`**, `rexruntime.dll` **10,187,776 B** at `10:48:16`.
* New strings in the built runtime (VERIFIED by byte search): `ROUND29D ` x7, `xuid shim[` x2,
  `round29_xuid_shim` x2, `aggregate-enumerator`, `create-enumerator`, `content-create-data`,
  `written_to=0x` x2, `per-call repeat suppressed`, `Round29ResolveXuid` x2.
* Boot `11:01:45 -> 11:04:23` (158 s wall, killed by the harness cap; screenshots at
  20/40/60/90/120/150 s, `round29_shots\`), windowed title screen, **zero** occurrences of
  `Null-page access`, `Unhandled guest access violation`, `INVALID INDIRECT CALL`,
  `ROUND28 guest context`, `nearest registered function`, `FATAL`, `TRAP`.

### Boot results

* **Log volume:** 4 files, **16,439,480 B**, 108,150 lines. The cap did **not** take effect (Task 2
  above): `XamUserGetSigninState` is still 107,936 of those lines; the ROUND29D tracing contributed
  only 46 lines.
* **XUID lines:** 43 distinct, listed in Tasks 1 and 3; the decisive ones are the shim substitution
  at `caller=0x8319C674` and `XamUserGetXUID … caller=0x8319C644 written_to=0x708EF780`.
* **Enumerator scan result:** **8 items** on both calls (`device_id=1` and `device_id=0`,
  `type=00000001`), scanned under
  `C:\Users\ramic\Documents\worldcup2010\B13EBABEBABEBABE\454108E4\00000001`. The 8 names are the
  saves themselves: `WCSettings0 20261018091153`, `…091620`, `…100314`, `…120501`, `…125232`,
  `…214606`, `…20261019091640`, `…20261019092400`. (Round 28 reported the same scan as
  `…\00000000BABEBABE\… -> 0 item(s)`.)
* **Other new observations:** `xeXamContentCreate` now **opens** rather than creates
  (`flags=00000033`, `disposition=2`, result `0x0`); no save directory and no file in the content
  store was written by this boot; the `Headers\00000001\*.header` files (one 328 B header per save)
  were already present from the earlier creates; `C:\Users\ramic\Documents\worldcup2010\00000000BABEBABE`
  still does not exist.

## Correction carried from Round 28 (VERIFIED, restated)

The crash function in `worldcup2010_019.log` is `sub_8333D4E0` and its extent ends at
**`0x8333DCF8`** - the next registered function start **and** the next `.pdata` record - **not**
`0x8333DCD0` (which is `0x28` short). `LR = 0x8333DB7C` is inside the function at `+0x69C`.

## Open items

1. **One more rebuild is needed** to make requirement 2 true (per-index change tracking, code above).
   Everything else in Round 29 behaves as intended.
2. A *general* repair of the truncation would be to widen `ArgTranslator::GetIntegerArgumentValue` so
   a 64-bit parameter reads `ctx.rN.u64` (and the stack path reads 64 bits). That changes **every**
   export's ABI, so it was deliberately not done; the narrow shim covers the XUID without that blast
   radius.
3. The throw-in crash (`worldcup2010_019.log`; independently reproduced by `worldcup2010_021.*` at
   `10:25:50`, `Null-page access: guest read of 0x00000021`, `LR=0x8333915C`, nearest function
   `0x83338F30 +0x22C`) was **explained in Rounds 30-31**: the faulting instruction is **`LR + 0x10`**
   (i.e. `+0x23C`, not `+0x22C`), and the repeated `read of 0x00000005` lines were **our own Hunk-B
   dumper**, not guest reads. Log 019 begins with the **same** read of `0x21` as log 023, so both logs
   show one guest defect (a returned pointer whose `+0x1C` field is `5`, then a data address called as
   a function), not two unrelated stops. Hunks A and B remain in place, unmodified, and did not fire
   during the Round-29 boot (the game sat on the title screen).


# Round 30 - the throw-in crash is a diagnostic fault loop, not a guest loop (read-only)

**Status: analysis complete. Three patch files were written to `patches\` and each passes
`git apply --check` on the pristine tree. Nothing was applied, nothing was rebuilt, and no file under
`ReXGlue\src` was modified this round.** Stop point: waiting for approval.

**One sentence.** In `worldcup2010_023.*` the guest does fault **once**, at `0x8333916C`
(`lwz r5,0x1C(r9)` with `r9=5`), but the 14,284 "null-page" faults that follow are **our own Hunk-B
dumper** reading guest `0x00000005` from *inside* the vectored exception handler. Windows re-enters
the handler for that new fault, the same block is printed again one stack frame deeper, and the whole
process stops making progress because the faulting thread holds the process-global memory critical
region. **The guest instruction is never re-executed.** The crash is therefore a defect in the
*diagnostic*, not a guest spin loop, and it is fixable without touching the guest.

## Task 1 - log reconnaissance (VERIFIED)

* Authoritative set: `dist\Output\logs\worldcup2010_023*.log`, 11 files, `11:11:07.805` to
  `11:16:16.288`. `D:\FWC10\_backups\crash_logs_r29` is only a partial copy taken after rotation
  (its first file starts mid-run); do not mix the two sets.
* **First** "Null-page access" anywhere in the set:

  ```
  [2026-10-19 11:14:10.457] [error] [sys] [t18136] Null-page access: guest read of 0x00000021
  (host 0x0000000100000021, page 0x00000000): refusing on-demand commit below 0x00010000;
  falling through
  ```
  at `worldcup2010_023.7.log:23697`.
* Then **14,284** occurrences of `Null-page access: guest read of 0x00000005` from `11:14:10.469` to
  `11:16:16.280` = 126 s, **8.8 ms each**, ending only because the harness killed the process.
  `Unhandled guest access violation`, `ROUND28 guest context` and the three pointer lines each occur
  **14,284** times as well, i.e. exactly one block per fault: one nesting level per repetition, not a
  repeating guest loop.
* `worldcup2010_021.*` shows the same pattern earlier: first fault `0x21` at `10:25:50.178`, then
  4,695 x `0x05` until `10:26:28.573` (38 s, 8.2 ms each). No stack-overflow death and no exit line
  in either run.
* **Decisive timing:** the last non-fault log line in the whole run is
  `[2026-10-19 11:14:10.448] [info] [krnl] [t11092] ROUND28C XamUserGetSigninState ...` - 9 ms
  *before* the first fault. After `11:14:10.457` the logs contain **only** the fault block, until the
  kill at `11:16:16.288`. The other guest threads stop too (see Task 5).
* Off-by-one counts between "fault" and "dump" lines in earlier rounds were log-rotation truncation,
  not lost blocks.
* Per-frame logging (measured on the 023 set, 541,382 lines): `ROUND28C XamUserGetSigninState`
  **126,928** lines; next most frequent message **27**. The sign-in line is the only per-frame log
  worth capping (Task 6d).

## Task 2 - the faulting instruction (VERIFIED)

`DEFINE_REX_FUNC(sub_83338F30)` in `worldcup2010_recomp.255.cpp:25084`, site lines 25405-25417
(lowercase hex in the generated source; the image/disassembly below is the same code):

```
0x83339144  lwz  r11,0(r29)        ; r11 = *(r29) = 0x82522820
0x83339150  lwz  r10,24(r11)       ; r10 = vtable[+0x18] = 0x836D1540
0x83339154  mtctr r10
0x83339158  bctrl                  ; ctx.lr = 0x8333915C
0x8333915C  lwz  r9,28(r3)         ; r9 = the getter's return value + 0x1C  <- see below
0x83339160  mr   r6,r30
0x83339164  lwz  r8,4(r31)         ; r8 = 0xB8F5DA10
0x83339168  lwz  r3,12(r31)        ; r3 = 0xB8DFD5E0
0x8333916C  lwz  r5,0x1C(r9)       ; <-- FAULT: r9 = 5, effective address 0x00000021
0x83339170  lwz  r4,12(r8)
0x83339174  bl   0x832D2C28
```

* How `r10` became CTR: `r29 = 0xBE25D870`, `*(r29) = 0x82522820`; the image (big-endian) holds
  `0x836D1540` at `0x82522820 + 0x18 = 0x82522838`. So `mtctr r10` loads the address of the getter
  `sub_836D1540`, which is `lwz r3,44(r3); blr` (`worldcup2010_recomp.311.cpp:32488`) - it returns
  `*(this + 0x2C)`. **The value returned is 5.**
* Provenance of `r9 = 5`: `r9 = *(getter_return + 0x1C)` where `getter_return = *(r29 + 0x2C) = 5`.
  The guest uses the getter's result as a pointer and then adds `0x1C`; there is no 64-bit wrap and no
  truncation involved. The *object* `X = *(r29+0x2C)` is still unidentified (no guest memory dump
  exists for the 11:14 run) - Task 6e adds it to the dump.
* `LR` is **not** the faulting instruction: `0x8333915C` is the return address of `bctrl`; the fault is
  at `0x8333916C` = `LR + 0x10`. Hence the log line "nearest registered function
  `0x83338F30` (+0x22C)" under-reports the truth by 16 bytes (the faulting instruction is
  `+0x23C`). The next `ctx.lr` write is at `0x83339178`, so the reported LR really is stale.
* `r30 = 1`, `r24 = 2`: small counters/indices at this site, not pointers (INFERRED from their use
  and from the surrounding code; they do not change across the 14,284 repetitions).
* `r4 = 0xA6C60698`: **guest, not host.** `0xA6C60698` lies inside `vA0000000` (the kGuestPhysical
  alias of guest RAM), and `r4` is only written *after* the faulting load (`0x83339170`), so at fault
  time it holds the caller's previous value (VERIFIED for the range and for the write order; the
  "stale" character is INFERRED). It coincides with the low 32 bits of a possible
  `0x1_00000000`-based host pointer, which is why it looked host-like, but there is no evidence it is
  a host pointer leak.
* The dump's `r3 = 0xB8DFD5E0` is the value *after* `0x83339168` executed, **not** the getter's return
  value; the getter's return (`5`) survives only in `r9` (and in the `X` that was dereferenced).

## Task 3 - the objects on the crash path

VERIFIED by reading the dumped guest blocks and the image (`fifadllzf.dec.bin`, big-endian):

* `r8` object at `0xB8F5DA10`:

  | off | value | meaning |
  |---|---|---|
  | +0x00 | `0x8252ECD0` | primary vtable: 16+ code pointers (`0x832D0580`, `0x832BF7D0`, `0x832BF7E8`, `0x832C2518`, `0x832D1D68`, ...) |
  | +0x04 | `0x8252ECC4` | secondary 3-word table `{0x832CF968, 0x832C9088, 0x00000000}` |
  | +0x08 | `0xB8D219B0` | the registry table (below) |
  | +0x0C | `0x0000001E` | integer 30 |
  | +0x14 | `0xB8F5D4E0` | pointer |
  | +0x18 | `0xB8E044A0` | pointer |
  | +0x1C | `0xB8E0F7C0` | pointer |
  | +0x20 | `0xB8DFDBA0` | pointer |
  | +0x24 | `0x01CDCDCD` | a `0xCDCDCDCD` word whose high byte was later overwritten with `0x01` (INFERRED) |
  | +0x28 | `0xB8DFD5E0` | == `r3` |
  | +0x2C..0x3C | `0xBAFD8390`, `0xBAFDB2C0`, `0xBAFE1A10`, `0xBAFDB330`, `0xBAFEC2B0` | pointers into `vBExxxxxx` guest RAM |

* `r3` block at `0xB8DFD5E0`: `+0x00 = 0xB8D219B0`, `+0x04..+0x0F = 0xCDCDCDCD x3`,
  `+0x10 = 0xB8ED2860`, `+0x14.. = 0xF0F0F0F0`. It is a **live, readable guest-heap block** with a
  valid table pointer and a valid pointer at `+0x10`, plus poison fill in between.
  Is it allocated / freed / never constructed? VERIFIED: allocated and reachable (readable, valid
  contents). INFERRED: an allocated-but-only-partially-initialised object - the `0xCD` fill is what
  this game's constructors leave in fields they have not set yet (see the fill sites below); it is
  *not* a freed block (freed blocks would normally be re-linked, and `+0x10` still points at a live
  block). "Never constructed" cannot be proven from one block.
* Table at `0xB8D219B0`: 16-byte records pointing into the image, e.g.
  `{0x6C, 0, 0x83917920, 0}`, `{0, 1, 0x8391792C, 0}`, `{0xB8D231B0, 2, 0x83917938, 0}`,
  `{0xB8D233D0, 3, 0x83917944, 0}`. The image table at `0x83917920` is 12-byte records
  `{index, name_ptr, kind}`:

  ```
  0  GymDino::NoType                  kind 0x00
  1  GymDino::IIntersectable          0x40
  2  GymDino::IRendered               0x40
  3  GymDino::IHavePosition           0x40
  4  GymDino::IHaveSettablePosition   0x40
  5  GymDino::IOutputDebugText        0x3C
  6  GymDino::IPlayer                 0x3A
  7  GymDino::PlayerRender            0x3A
  8  GymDino::ActionActor             0x3A
  ```
  (`EdbDino::NoType/int/char/MyStruct/...` sit at `0x823C43E0..` with 8-byte records at
  `0x839178D4..`; 64 name-pointer sites and 119 type-name strings were found, all inside this
  registry). This is EA's **GymDino / EdbDino** interface/type registry - the title runs EA's
  "GymDino" engine, so the object is a live engine object, and the table is the type registry, not a
  vtable.
* **Constructor sites for `0x8252ECD0` / `0x8252ECC4`: not found in this module (INFERRED).** No word
  in the image equals either vtable address, and no `lis`+`addi`/`ori` sequence materialises them
  (method sanity-checked: the same search does find the 72 sites that reference `0x83917920`). Either
  the constructor lives in another XEX/module of the title or the pointer is copied from a prototype
  object. The vtables themselves *are* image data (the entries read this round all land inside the
  module code range `0x82650000-0x838D8DB4`).
* **Who writes `0xCD` / `0xF0` (VERIFIED sites, INFERRED meanings):** the game's own code materialises
  `0xCDCDCDCD` at 16 places and `0xF0F0F0F0` at 2. Examples:
  * `0x833A00BC`: `lis r9,0xCDCD; ori r9,r9,0xCDCD; mtctr r9; ... stwu r9,4(r11); bdnz` - a
    **region word-fill loop** with `0xCDCDCDCD`.
  * `0x829CE2CC`: `lis/ori` then `stw r11,0(r31); stw r11,4(r31)` - **poisoning a new small object**.
  * `0x82A2DE30`: three `stw 0xCDCDCDCD` followed by real field stores - the classic
    "fill-then-initialise" constructor.
  * `0x83478140`: `lis r9,0xF0F0; ori r9,r9,0xF0F0; mtctr; stwu r9,4(r11); bdnz` over a **64-byte
    stack buffer** (`r11 = r1+0x9C`, 16 iterations); `0x83568048` is a second `0xF0F0F0F0` fill.
  So: `0xCD` = uninitialised/poison (INFERRED, strongly supported by the ctor sites); `0xF0` = a
  second poison pattern whose role at these two sites is not determinable (one is clearly a stack
  buffer) - treat its meaning as UNKNOWN. The runtime's own fills are unrelated: `scribble_heap`
  (`0xCD`, default **off**), `Arena::DebugFill` (`0xCD`, host arena) and the guest-stack fill `0xBE`
  (`xthread.cpp:308`); none of them writes guest heap blocks.

## Task 4 - relation to worldcup2010_019.log (VERIFIED)

`worldcup2010_019.log` (2026-10-18, **pre-Hunk-A** build) shows the same guest defect one step later:

```
118: [2026-10-18 22:50:25.395] [warning] [sys] [t24456] Guest virtual read of 0x00000021
     (host 0x0000000100000021) committed on demand as page 0x00000000 (recommit); total 2
119: [2026-10-18 22:50:25.402] [error] [cpu] [t24456] INVALID INDIRECT CALL:
     target=82486704 LR=8333DB7C CTR=82486704 r1=7019E740 r2=00000000 r3=BE4545F8
     r11=825227F8 r12=8333DB44
120: [2026-10-18 22:50:25.402] [critical] [core] [t24456] [FATAL] Call to invalid or
     unregistered function at guest address 0x82486704
```

* Same defect family: an interior/returned pointer's small offset field is used as a pointer
  (`023`: `*(X+0x1C) = 5`) or as a call target (`019`: `*(r9+0x14) = 0x82486704`, a *data* address
  inside the image, called through `mtctr`/`bctrl`).
* `019` site: `sub_8333D4E0` (`worldcup2010_recomp.62.cpp:23868`, call at line 24856):
  `lwz r9,760(r30)` -> `addi r3,r30,760` -> `lwz r8,20(r9)` -> `mtctr r8` -> `bctrl`
  (`ctx.lr = 0x8333db7c`), i.e. `r8 = *(r9+0x14) = 0x82486704`.
* Because the pre-Hunk-A build committed the low page, the guest read `0x21` returned zeros and the
  process survived 7 ms longer before dying on the invalid call. **Hunk A now surfaces the true
  defect at the first near-null read**, which is the better failure mode; Hunk A must not be weakened.
* The Round-29 note that `sub_8333D4E0` ends at `0x8333DCF8` is **correct** (re-verified this round:
  `DEFINE_REX_FUNC(sub_8333DCF8)` exists at `worldcup2010_recomp.27.cpp:24366` and is the next
  registered start after `0x8333D4E0`, so `LR 0x8333DB7C` is `+0x69C` inside the function).

## Task 5 - why the process neither terminates nor makes progress

The chain, all VERIFIED unless tagged:

1. The guest faults at `0x8333916C` -> host `0x100000021` -> Windows calls the VEH
   (`ExceptionHandlerCallback`, `core\exception_handler_win.cpp`).
2. `MMIOHandler::ExceptionCallback` (`system\mmio_handler.cpp:371`) takes the **process-global**
   `std::recursive_mutex` at line 408 (`rex::thread::global_critical_region::Acquire()`;
   `include\rex\thread\mutex.h:56-58` shows it wraps a `static std::recursive_mutex`) and moves it
   into `Memory::AccessViolationCallback` (lines 419-421). **The faulting thread therefore holds the
   memory critical region for the whole handler.**
3. `AccessViolationCallback` (`system\xmemory.cpp:549`) takes Hunk A's low-page branch, logs
   "refusing on-demand commit", falls through to the fatal path, calls Hunk B's
   `Round28DumpGuestContext`, and returns `false`.
4. Hunk B's `Round28DumpRegAndPointee("r9", 5)` calls `Round28DumpBytes`. Its guard only checks
   "committed" (`info.state & kMemoryAllocationCommit`, true for guest page 0) and then reads
   `p[0..63]` at host `0x100000005` - a **PAGE_NOACCESS** page (`protect_zero` commits the low 64 KiB
   as no-access). That is a **second access violation inside the handler**.
5. Windows **re-enters the same VEH** for the new fault (it does not retry the faulting
   instruction; verified with a faithful 16 MiB-stack probe in `r30_depth_probe.c`: depth kept
   incrementing past 5,000). The guest context is frozen, so the identical block is printed again,
   one frame deeper.
6. Nothing ever handles it: `ExceptionHandlerCallback` returns `EXCEPTION_CONTINUE_EXECUTION` only
   when a registered handler returns true (line 98) and `EXCEPTION_CONTINUE_SEARCH` otherwise
   (line 101); the VCH is commented out (line 111); `AccessViolationCallback` returns `false` for
   both faults. The generated game code contains **no SEH frames at all** (0 `SEH_TRY` / `SEH_CATCH`
   / `__except` in the generated sources; the 16 `RtlUnwind` hits are guest import *names*), so the
   guest code cannot swallow it either. There is no `SetUnhandledExceptionFilter` in the runtime.
7. Why the whole process freezes, not just one thread: the recursion never unwinds, so the global
   memory critical region is never released, and every other guest thread that allocates/frees or
   touches guest memory blocks on it. Log evidence: the last non-fault line is
   `11:14:10.448`, the first fault `11:14:10.457`, and after that only the fault block, for 126 s.
8. Why it did not die of stack overflow while being watched: `xthread.cpp:433`
   `params.stack_size = 16_MiB; // Allocate a big host stack.` - each guest thread has a **16 MiB**
   host stack, and 14,284 levels fit in it (`16 MiB / 14,284 = 1.17 KiB` per level). The probe with
   the same call chain dies at roughly 5-6 k levels only because its frames are larger; with the real
   frames the loop was within a few thousand levels of a stack-overflow death when the process was
   killed.
9. Cost per level: ~8.8 ms, dominated by `FindContainingFunctionStart` (`function_dispatcher.cpp:246`)
   rebuilding and sorting a 91,164-entry `std::vector` **on every dump** (INFERRED from the code and
   the probe timing; the probe's frames without the sort run ~0.5 ms/level).
10. The guest instruction executes **exactly once** and never re-executes: the VEH never returns to
    `0x8333916C`, so there is no "retry" of the guest load. The repetition is entirely ours.

## Task 6 - proposed Round-30 change set (written, NOT applied)

One change set, split per file as in Round 29 (apply in order 1, 2, 3 from the repo root with
`git apply -p1`). Every file carries its own `#ifndef ROUND30_FIX / #define ROUND30_FIX 1` off switch;
`exception_handler_win.cpp` and `function_dispatcher.cpp` share the `ROUND30_FIX` name and default.
`ROUND30_MINIDUMP` (default `1`) additionally gates the minidump.

| patch | SHA-256 |
|---|---|
| `patches\round30-1-fault-loop-and-safe-dump.patch` | `660174BB2F026CD001110B3DA83FBA48DABC70E772F248BD18CF01979B00CB3F` |
| `patches\round30-2-host-rip-log.patch` | `48230F60451642E5E15F9B8503EC67E31803EFBF354E2D5CA82656E5DAB997C2` |
| `patches\round30-3-signin-per-index.patch` | `B8A0F7617AACEDC17C8A5AD2F189FE0639092BDD41813F63D1CA43DDCF4B1DEC` |

(Exact values are also in `D:\FWC10\_backups\20261019-121636-r30\SHA256SUMS.txt`.)

### 6a - `ReXGlue\src\system\function_dispatcher.cpp` (the fault-loop guard + a dump that cannot fault)

* **The root fix:** every diagnostic read now checks **host** page protection first
  (`Round30HostReadable`: `VirtualQuery` + `State == MEM_COMMIT` + no `PAGE_NOACCESS`/`PAGE_GUARD`),
  so the dumper cannot be the thing that faults: `Round28DumpBytes` (before reading `p[0..63]`) and
  `Round28DumpRegAndPointee` (before reading the pointee word). The message becomes
  `(... host page not readable; not dumped)`.
* **Fault-loop guard:** an FNV-1a hash over all 32 GPRs + LR + CTR is compared with the previous
  context on the same thread. Repetition 1 dumps; repetition 2 dumps and logs
  `ROUND30 fault repeated with an identical guest context ...`; repetition 3 logs
  `ROUND30 fault loop: the same guest register context faulted N times in a row ... guest function
  0x... (+0x... from LR=...) ... r3=... r8=... r9=... r29=... r31=... Terminating the process`, writes a
  minidump and calls `TerminateProcess(..., 0x52300001)`. Repetitions above 3 are suppressed with a
  rate-limited counter (belt and braces; unreachable once the guard fires).
* **"Not only LR":** `Round30DumpCode` prints `0x60` bytes of guest code starting at `LR-0x10`
  (readable-checked), so the instruction after the last call is visible in the log even without the
  image.
* **Owner chain / table pointers (6e):** the block now also dumps `[r29]`, `[r29->*]`, and the first
  24 words of the registry table at `[r3->*]` (and at `[r8+8]` if it differs). For the 023 crash that
  is exactly `0xB8D219B0` and its `GymDino::*` records.
* `ROUND30_MINIDUMP` writes `%TEMP%\worldcup2010_r30_<pid>_<tick>.dmp` with `MiniDumpWriteDump`
  (`#include <dbghelp.h>`, `#pragma comment(lib, "dbghelp.lib")`, Windows-only, failures silent) and
  logs one line. No exception pointers are available at that depth; it is a normal dump, enough to see
  the recursed stack.

### 6b - `ReXGlue\src\core\exception_handler_win.cpp` (log the host RIP)

* Before the handler loop, for `EXCEPTION_ACCESS_VIOLATION` only, log
  `ROUND30 exception: host RIP=0x... (<module> base=0x... +0x...) fault_host=0x...`, rate-limited to
  the first 8 per thread and then every 1024th (`thread_local` counter). `Round30HostRipClass` maps the
  RIP with `VirtualQuery`/`GetModuleHandleExW` and names the module: **rexruntime.dll
  (runtime/diagnostic code, not guest code)** vs **main executable (recompiled guest code)**.
  In the 023 run this single line makes the diagnosis immediate: the first fault has an RIP in the
  executable, every repeat has an RIP in `rexruntime.dll`.

### 6c - Hunks A and B stay

`xmemory.cpp` is **not modified**: Hunk A's refusal (with its "falling through to the fatal path"
message) and Hunk B's call site stay exactly as they are. The dump internals are fixed, not replaced.

### 6d - `ReXGlue\src\kernel\xam\xam_user.cpp` (per-user-index sign-in tracking)

Round 29 kept **one** `(user_index, state)` pair, so the game's round-robin polling of indices 0..3
made every call look like a change (126,928 lines). The patch keeps `logged[5]` / `last_state[5]`
(0..3 plus a slot for anything else) and logs only a real change of that index's state:
`XamUserGetSigninState user_index=N -> 0x... (state changed for this index)`. No other per-frame log
exists in this run (next highest message count: 27), so nothing else is capped beyond the fault-dump
rate limiting in 6a.

### 6e - asked-for effect on the next dump (what the log will show)

For the same crash the block will contain `[r3]`, `[r8]`, `[r9] (host page not readable; not dumped)`,
`[r11]`, `[r29]`, `[r30]`, `[r31]`, the `[r3->*[table]]` word dump, the code bytes around `LR`, and a
`ROUND30 exception ... (rexruntime.dll ...)` line for the dump's own fault - or, with the fix in
place, no dump fault at all and one clean block followed by a deterministic stop.

### Verification and limits

* `git apply --check -p1 --whitespace=nowarn` on the pristine tree: **exit 0** for all three.
* **Not compiled and not built** (no build this round). The new code uses only existing helpers
  (`fmt::format`, `REXCPU_ERROR`, `REXLOG_ERROR`, `PPCContext`, `Memory::TranslateVirtual`) plus
  Windows APIs already available in the Windows-only files.
* Behaviour change to expect after applying: a genuine guest access violation now produces **one**
  context block and then the ordinary unhandled-exception termination (Hunk A's "fatal path") instead
  of a hang; a *diagnostic* fault (if one is ever introduced again) terminates after three identical
  contexts with a minidump. Both are deterministic; neither returns `EXCEPTION_CONTINUE_EXECUTION`
  for a guest fault, so no guest state is silently corrupted.

## Task 7 - state and next step

* No source change, no build, no log/dump/backup deleted. `patches\round30-*.patch` are new files;
  the pre-change tree is preserved in `D:\FWC10\_backups\20261019-121636-r30` (pristine copies of the
  three targets + the three patches + `NOTES.md.before-r30` + `SHA256SUMS.txt`).
* Waiting for approval to (a) apply the three patches and rebuild once, or (b) adjust the change set
  first. If approved, the rebuild also tests the per-index sign-in cap (126,928 -> ~8 lines expected,
  one per index and state change).

## Open items carried forward

1. ~~The identity of `X = *(r29+0x2C)` (whose `+0x1C` field is 5) is still unknown; Task 6e's dump
   should answer it on the next crash.~~ **Answered in Round 31:** `X` (= `G`) is the *owner object*
   stored by the base ctor `sub_8323FA88` (`stw r30,44(r31)`); G's class has vtable `0x825218A4`, and
   `G+0x1C` is an **array element count** (`sub_83233D90`), so `5` = five elements. The caller then
   used it as a pointer (guest type confusion). See `# Round 31`, 5.2-5.5.
2. `0x8252ECD0` / `0x8252ECC4` constructors are outside this module (INFERRED); finding them needs the
   other XEX modules or a prototype-object search.
3. The general 64-bit argument truncation in `ArgTranslator::GetIntegerArgumentValue` remains the
   general fix for XUID-class bugs (Round 29 note); the narrow shim is still the applied mitigation.

# Round 31 - the three patches applied, one rebuild, 150 s title-screen boot, and the classes behind the fault

> Round 31 applied the three Round-30 patches (with the additions the user asked for), rebuilt **once**,
> booted **150 s at the title screen (no match)**, and did the static analysis of the objects in the
> throw-in fault chain. Nothing was pushed. `ReXGlue/` is gitignored (`.gitignore:20`), so the patch
> files remain the only change record; `NOTES.md` and the pre-existing
> `Installer/recomp-template/config/fifadllzf_overrides.toml` are still the only modified tracked files.

## 1. Change set (applied)

| patch | size | SHA-256 |
|---|---|---|
| `patches\round30-1-fault-loop-and-safe-dump.patch` | 19,163 B | `595C2377D8E11E08760EDBD5FA0A4696B6DE5CFC8DD9F2C0003BB328A8823907` |
| `patches\round30-2-host-rip-log.patch` | 3,841 B | `48230F60451642E5E15F9B8503EC67E31803EFBF354E2D5CA82656E5DAB997C2` |
| `patches\round30-3-signin-per-index.patch` | 2,284 B | `B8A0F7617AACEDC17C8A5AD2F189FE0639092BDD41813F63D1CA43DDCF4B1DEC` |

- `git apply --check -p1` exit 0 for all three on the pristine tree (re-run after the edits below); then
  applied in order 1, 2, 3 (exit 0 each). Diffstat: 338 insertions, 5 deletions across
  `exception_handler_win.cpp`, `xam_user.cpp`, `function_dispatcher.cpp`.
- Round-31 additions (all requested in the approval):
  - **fault block** also dumps `r29` (24 words), `G = *(r29+0x2C)` (16 words = 64 bytes),
    `*(G+0x1C)`, the object `*(G+0x1C)` points at (when it is one), and the first words of up to four
    objects G points at (deduped, page-checked like the rest of the block). `this` for the `bctrl` is
    **VERIFIED** to be `r29` (`mr r3,r29`, generated `worldcup2010_recomp.255.cpp:25407`), so the dump
    reads `*(r29+0x2C)` and not `*(*(r29)+0x2C)`.
  - **minidump** is `MiniDumpNormal` (module list + thread list + thread stacks, **no full memory**),
    with a `MiniDumpWriteDump` IO callback that counts bytes and requests a cancel at the cap, plus a
    post-write file-size check (so an over-cap file is never kept). Free-space gate: it refuses when
    free space is below `cap + 64 MiB`.
    - `round30_minidump_dir` (string, default empty): empty = `%TEMP%\worldcup2010_minidumps`;
      file name `worldcup2010_r30_<pid>_<tick>.dmp`. **Default path:**
      `C:\Users\<user>\AppData\Local\Temp\worldcup2010_minidumps\worldcup2010_r30_*.dmp`.
    - `round30_minidump_max_mb` (uint32, default **256**; 0 = no cap).
  - **termination** after the third identical fault context is unchanged (`TerminateProcess` with
    `0x52300001`); a genuine one-off guest fault still produces exactly **one** context block and then
    the normal unhandled-AV path, as before.
- Transparency: the **first** rebuild attempt failed to compile (clang-cl rejected the minidump
  callback member names I had used: `IoStartCallback`/`IoWriteAllCallback` do not exist in
  `minidumpapiset.h`). Fixed to `input->Io.BufferBytes` / `output->Cancel` (SDK 10.0.26100.0
  `um\minidumpapiset.h:1237-1265`) + a post-write size check; patches regenerated, `git apply --check`
  re-run (exit 0), re-applied, rebuilt. Only the final hashes above were built.

## 2. Build (one rebuild, approved)

- `BUILD_EXIT_CODE=0` (recipe `C:\Users\ramic\AppData\Local\Temp\opencode\round29_build.cmd`).
- `dist\Output\rexruntime.dll` **10,216,960 B**, 2026-10-19 14:36:01 (Round 29: 10,187,776 B).
- `dist\Output\worldcup2010.exe` 8,022,528 B, 14:36:18.
- New strings found in the built runtime (ASCII search of `rexruntime.dll`): 1x
  `ROUND30 exception: host RIP`, 1x `ROUND30 fault loop`, 1x `ROUND30 minidump written`, 1x
  `ROUND30 minidump abandoned`, 3x `ROUND30 minidump skipped`, 1x `worldcup2010_minidumps`,
  2x `round30_minidump_dir`, 2x `round30_minidump_max_mb`, 1x `G = *(r29+0x2C)`, 1x `r29 object`,
  1x `state changed for this index`.

## 3. Boot (150 s, title screen, no match)

- 14:39:06 -> 14:41:38; window at 0.6 s (`2010 FIFA World Cup South Africa PC`); screenshots at
  20/40/60/90/120/150 s in `C:\Users\ramic\AppData\Local\Temp\opencode\round31_shots\`
  (`r31_150s.png` shows the attract/stadium sequence); still running at 152 s -> killed by the harness.
- **Log volume: 1 file, 48,269 B, 284 lines** (`worldcup2010_024.log`). Round 29 was 4 files /
  16,439,480 B / 34,491 lines in the largest log. Reduction ~340x in bytes.
- **Sign-in lines: 4** (one per user index, `state changed for this index`) instead of the 126,928
  per-call lines in the Round-30 crash set -> Hunk-3 works.
- **No** `Null-page access`, **no** `ROUND28 guest context`, **no** `ROUND30 fault loop`, **no**
  minidump, **no** `INVALID INDIRECT CALL` / `TRAP` / `FATAL`.
- 67 `ROUND30 exception: host RIP=0x...` lines: these are **first-chance** exceptions the VEH saw from
  one module (`base=0x7FFC9E760000`, 15 distinct offsets `+0x52FF8E..+0x70AD766`, 9 threads) during
  startup. The game
  survived all of them, so they are not guest faults; the host-RIP line logs every VEH entry (first 8
  per thread, then every 1024th), as designed. Non-ROUND30 `[error]` lines are only the pre-existing
  FIFA `XexGetProcedureAddress` traces and `ResolvePath` misses.

## 4. Corrections to earlier notes (task 5)

1. **`LR+0x22C` -> `LR+0x23C`.** The nearest-registered-function line is computed from `LR`, and the
   faulting instruction is `LR + 0x10` (`LR=0x8333915C`, fault at `0x8333916C`), i.e. `+0x23C` from
   `sub_83338F30`. Corrected in place in the Round-29 open item (item 3) and restated here.
2. **The repeated `read of 0x00000005` lines were our own Hunk-B dumper, not guest reads.** The guest
   executed the faulting instruction **once**; the 14,284 repeats are `Round28DumpBytes` reading guest
   `5` (host `0x100000005`) from inside the VEH. (The Round-30 section already states this; the Round-29
   open item is corrected in place.)
3. **Log 019 began with the same read of `0x21` as log 023.** `worldcup2010_019.log:118-120` shows
   `Guest virtual read of 0x00000021` followed 7 ms later by `INVALID INDIRECT CALL target=82486704`
   (`LR=8333DB7C`); 023 begins with the same read. So 019 and 023 are one defect family (a small
   integer used as an address/function pointer), not two unrelated stops. Corrected in place in the
   Round-29 open item.

## 5. Static analysis of the fault chain (task 6)

Everything below is read from the generated sources and the decrypted image (big-endian,
base `0x82300000`); tags say which parts are proven by code and which are inference.

### 5.1 The class of the `r29` object (VERIFIED)

- `r29`'s vptr is `0x82522820` (`lwz r11,0(r29)` at the crash site; image word at `0x82522838`
  = `0x836D1540` = slot `+0x18`).
- **ctors/dtors (all VERIFIED by the literal `lis 0x8252` + `addi 10272` materialisation):**
  - ctor `sub_83250B10` (`worldcup2010_recomp.180.cpp:22681`) - stores the vptrs and initialises the
    members;
  - base ctor `sub_8323FA88` (`worldcup2010_recomp.130.cpp:21859`);
  - destructor `sub_8323FF20` (`worldcup2010_recomp.296.cpp:21144`);
  - deleting destructor `sub_83240030` (`worldcup2010_recomp.38.cpp:22643`, slot 0: dtor + optional
    `sub_8304AE30` free);
  - allocating wrapper `sub_83250DD8` (`worldcup2010_recomp.57.cpp:20345`): `li r3,288` ->
    `sub_8321EE00` (pool allocator, 16-byte alignment) -> `sub_83250B10(new, owner, arg)` -> stores the
    new pointer in the caller's slot and increments the refcount at `+4`.
- **Size 288 bytes** (`0x120`; the ctor's last write is `+0x11C`). **Refcount at `+4`.**
- **Four vptrs** (multiple inheritance): `+0 = 0x82522820`, `+8 = 0x825227F8`,
  `+0x24 = 0x825227E8`, `+0x28 = 0x825227D8`. The `0x825218B8`-style overlap does not apply here: these
  are four distinct tables.
- **The class has its own RTTI**: slot `+4` (`sub_8323FB20`, `recomp.274.cpp:22941`) returns
  **`0x3C9F47C4`**; slot `+8` (`sub_8323FB38`) compares `r4` against it. The tag never appears in
  image data, so there is no name table to read a class name from.
- **One construction site** for the whole module (`sub_83250DD8`), **one destruction site**
  (`recomp.38.cpp:22664`). The wrapper has **no direct call sites**: it is reachable only as a
  **virtual function pointer** stored at image word `0x825218C8` (and that word is shared by the owner
  class's two vptrs, see 5.3).

### 5.2 What `sub_836D1540` returns and who `this` is (VERIFIED)

- `sub_836D1540` (`recomp.311.cpp:32488`) is exactly `lwz r3,44(r3); blr` -> returns `*(this+0x2C)`.
- the call site does `mr r3,r29` before the `bctrl` (generated line 25407), so **`G = *(r29+0x2C)`**.
- **`+0x2C` is written by the base ctor from its `r4` argument**: `sub_8323FA88` ends with
  `stw r30,44(r31)` where `r30 = r4` (`recomp.130.cpp:21859`, store at line 21884). So the field is
  **the owner pointer handed to the constructor**, not something a later setter writes. This supersedes
  the Round-30 phrasing "who writes `+0x2C` is still unknown".
- the class's slot `+0x1C` (`sub_82F19E48`, `recomp.280.cpp:16744`) calls the getter twice
  (`vtable+0x18(this)` then `vtable+0x18(result)`), i.e. the field is an **owner/parent chain**.

### 5.3 G's class (VERIFIED layout)

- G's class vptrs: **`0x825218B8` at `+0`** (primary) and **`0x825218A4` at `+0x14`** (secondary;
  the tables overlap with a `0x14` stride). **CORRECTED in Round 32:** this line originally had the
  two offsets swapped. The ctor `sub_8323FEB0` stores `0x825218B8` at `+0` (the `r9` store at
  `recomp.280.cpp:22604`) and `0x825218A4` at `+0x14`, and the live 025 dump at `0xBD6BE1D0` reads
  `+0 = 0x825218B8`, `+0x14 = 0x825218A4` - so G is a **primary** object of that class.
- ctor `sub_8323FEB0` (`recomp.280.cpp:22604`); dtor `sub_832242E0` (`recomp.301.cpp:20709`).
- ctor writes: `+0x18 = 0`, **`+0x1C = 0`**, `+0x20 = 0`, `+0x2C = 0`, `+0x24 = float const`,
  `+0x28 = float const`, and the two vptrs.
- the allocating wrapper `sub_83250DD8` is G's class virtual at **A+0x24 / B+0x10** (same word
  `0x825218C8`). As a thiscall-with-sret its arguments are `(r3 = return slot, r4 = this = G, r5 = arg)`
  - so the pointer stored at `r29+0x2C` is exactly `this` of that call: **G is the object that created
  the 288-byte object**.

### 5.4 What `+0x1C` of G is: an element count (VERIFIED)

`sub_83233D90` (`recomp.215.cpp:23275`, G's virtual at A+0x40 / B+0x2C) does:

```
r4 = *(this+0x1C); r3 = *(this+0x20); r5 = 16; r6 = comparator
sub_82838D80(array, count, 16, cmp)          ; sort/search over 16-byte records
... walk the records, drop null pointers ...
*(this+0x1C) = number_of_non_null_records
```

So the pair **`+0x20` = pointer to an array of 16-byte records, `+0x1C` = element count**. The record
loop calls each record's `vtable+8` with the type tag `0x3D94C20C` (`lis 15764; ori 49676`) and writes a
float at record `+12`; the record is `{object*, u32, float, float}`.

Therefore **`*(G+0x1C) = 5` in the 023 run means "five elements"** - a legitimate value of G's class,
not an enum, not a flag, not an index into the GymDino/EdbDino table at `0x83917920` (that table is a
different subsystem; no code path connects it to this field).

### 5.5 The caller's chain and what it expected (evidence, then inference)

Generated `recomp.255.cpp:25405-25432` (VERIFIED):

```
r11 = *(r29)                 ; 0x82522820
r3  = r29 ; r30 = *(r29+0x664)
call *(r11+0x18)             ; sub_836D1540 -> G
r9  = *(G+0x1C)              ; 5
r6  = r30
r8  = *(r31+4) ; r3 = *(r31+12)
r5  = *(r9+0x1C)             ; <-- fault, EA 0x21
r4  = *(r8+12)
sub_832D2C28(r3, r4, r5, r6)
```

- The caller reads `*(G+0x1C)` **statically** and dereferences it, so it expects a **pointer** there.
  In G's class that offset is only ever a count (the ctor writes 0; the sort/compact pass writes the
  count). Nothing in the module sets a pointer at `+0x1C` of G's class.
- The caller also reads `*(r29+0x664)` - **0x4A4 bytes past the end of a 288-byte object** - which only
  makes sense if it believes `r29` is a much larger type.
- **Two readings, both consistent with the data (INFERRED):**
  (a) *wrong object type*: the slot that produced `r29` held an object of a different class (or a stale
  pointer) and the caller applied the wrong layout; or
  (b) *adjusted subobject*: if the factory was invoked through the secondary vptr (`+0x14`), the stored
  owner is `owner+0x14`, and `G+0x1C` is the owner's `+0x30` field, a different member.
- The **new dump decides between them**: it prints 24 words at `r29`, 64 bytes at `G`,
  `*(G+0x1C)`, and the first words of G's pointed-to objects. With the corrected vptr order
  (5.3), if G's first word is `0x825218B8` the owner is the **primary** subobject (reading (a));
  if G's first word is `0x825218A4`, the stored pointer is the adjusted **secondary** subobject at
  `+0x14` (reading (b)). The 025 dump reads `+0 = 0x825218B8` -> **reading (a) survives**; (b) is
  excluded. Round 32 then showed *why* the wrong object reached the caller: the QueryInterface that
  produced `r29` is truncated (see the Round-32 section), so the caller's null check never fires.
- In **both** readings the guest is using a small integer as an address: the defect is in the guest's
  object graph (wrong/stale pointer or wrong static type), **not** in our memory mapping - the same
  shape as log 019, where `0x82486704` (a data address) was called as a function through
  `*(*(r30+0x2F8)+0x14)`.

### 5.6 Writers of small constants to `+0x1C` (reachability)

- The module has **382** store sites of a 0..9 immediate to `+0x1C` (scan over both generated trees).
  The only one belonging to G's class is the count update in `sub_83233D90`; none stores a
  pointer-sized value or a magic constant there.
- Reachability of `sub_83233D90` in our runs: **INFERRED** reachable (it is the class's array
  maintenance virtual, and the object existed with a non-empty array: 5 elements); we cannot prove the
  call without a trace, and this round added no tracing for it.
- The `5` is therefore the **element count of G's array**, i.e. the code did not "choose 5"; it is the
  state of the array at the time of the throw-in.

### 5.7 Task 7 (64-bit XAM audit) - deferred

Not done this round: marked low priority, and this round must stop after the rebuild + boot report. The
general `ArgTranslator::GetIntegerArgumentValue` truncation (Round 29 note) remains the outstanding
general fix; the narrow XUID shim is still the applied mitigation.

## 6. What the next throw-in should produce

- One `ROUND28 guest context` block with the new `r29 object` / `G` / `*(G+0x1C)` detail, then a
  capped minidump (default `%TEMP%\worldcup2010_minidumps`, 256 MiB cap), then a **clean stop** instead
  of the 14,284-fault hang; on the third identical context the process exits with `0x52300001`.
- The `[G = *(r29+0x2C) via sub_836D1540]` line plus 64 bytes at G answer 5.5 (a) vs (b).

## Open items carried forward

1. Decide reading 5.5(a) vs 5.5(b) from the next crash dump (first word at G tells them apart).
2. The semantic names of the two classes are still unknown (no name table; RTTI tags
   `0x3C9F47C4` for the 288-byte class, `0x3D94C20C` for the objects in G's array).
3. The general 64-bit argument truncation in `ArgTranslator::GetIntegerArgumentValue` remains the
   general fix for XUID-class bugs (Round 29 note); the narrow shim is still the applied mitigation.
4. The 64-bit XAM audit (task 7) is deferred.

# Round 32 (2026-10-19) - the throw-in crash is classification (A); root cause is our own truncated QueryInterface

> Read-only round. Nothing was launched, rebuilt, applied or deleted. The only writes are this
> section, the Round-31 corrections above, `LAST_BACKUP.txt`, and the two **proposed** patch files
> under `patches\`. `ReXGlue/` was read only (gitignored, unmodified).
>
> **Status after approval (2026-10-19).** This section is the pre-approval diagnosis. The two
> patches were then applied, one incremental rebuild succeeded, and a 152 s title-screen boot ran;
> §8 records the 291-entry audit, the caller/reference analysis, the C++ review, the codegen
> answers, and the build/boot evidence. Where §§5-7 say "not applied"/"not rebuilt", §8 supersedes
> them.

## 1. Classification: (A) GUEST FAULT, one off

Log `dist\Output\logs\worldcup2010_025.log` (58,141 B, 392 lines, last written 15:13:01) contains
**one** fault block:

- line 295 `ROUND30 exception: host RIP=0x7FFCA40F2B2F (other module base=0x7FFC9E760000 +0x5992B2F) fault_host=0x100000021`
- line 296 `Null-page access: guest read of 0x00000021 ... refusing on-demand commit below 0x10000`
- line 297 `Unhandled guest access violation: read of guest 0x00000021 (host 0x0000000100000021) on thread 0xF8000028`
- line 298 `ROUND28 guest context (guest access violation (read))`

Marker counts in 025: `ROUND30 fault loop` **0**, `INVALID INDIRECT CALL` **0**, `ROUND30 minidump`
**0**, `Null-page access` **1**, `Unhandled guest access violation` **1**, `FATAL` **1**. There is no
repetition: the Round-30 diagnostic loop does not reappear. **Classification (A).**

Independent evidence (VERIFIED, not from our logs):

- `Application` event **1000**, 2026-10-19 15:13:04: `Faulting application name: worldcup2010.exe
  ... Faulting module name: worldcup2010_fifadllzf.DLL ... Exception code: 0xc0000005 ...
  Fault offset: 0x0000000005992b2f ... Faulting process id: 0x32DC`.
- WER minidump `C:\Users\ramic\AppData\Local\CrashDumps\worldcup2010.exe.13020.dmp` (7,700,797 B):
  exception stream thread **27348**, code `C0000005`, address `0x7FFCA40F2B2F`, parameters
  `0x0` (read) and `0x0000000100000021`. Module `0x7FFC9E760000` is
  `...\dist\Output\worldcup2010_fifadllzf.DLL` (size `0x755E000`), so the fault is exactly
  `+0x5992B2F` into the **generated fifadllzf module**, not `rexruntime.dll`.
- The dump's ThreadContext is poisoned (`rip=0xAAAAAAAAAAAAAAAA`), so the host stack cannot be
  recovered from it; the exception record is the usable part. The game's own dump writer did not run
  (`%TEMP%\worldcup2010_minidumps` does not exist).
- Free space at the time of this round: C: 72.7 GB, D: 80.2 GB.

## 2. Root cause (VERIFIED): the QueryInterface chain of `sub_8323FB38` is truncated by our own override

`config\fifadllzf_overrides.toml:328-330` (workspace copy
`C:\FWC10B\fwc10stage4\WorldCup2010Rex\config\fifadllzf_overrides.toml`, Round-14 Tier 1) contains:

```toml
"8323FB38" = { end = 0x8323FB48 }
"8323FB6C" = { end = 0x8323FB7C }
"8323FB8C" = { end = 0x8323FBA0 }
```

`end` is exclusive, so `0x8323FB48` is exactly the instruction **after** the first `beqlr`. The
generated body (`generated\fifadllzf_xex\worldcup2010_recomp.275.cpp:21862`) is only:

```c
// lis r11,0x3C9F / ori r11,0x47C4 / cmpw cr6,r4,r11 / beqlr cr6
if (ctx.cr6.eq) return;
```

and then falls off the end with `r3` unchanged. The guest function is **one contiguous chain**
(decoded from the decrypted image, base `0x82300000`):

```
8323FB38  0x3C9F47C4 -> return this
8323FB48  r11 = this+0x24
8323FB58  0x88B8764F -> 0x8323FBA0 -> return this+0x28
8323FB68  0x301A1210 -> 0x8323FBB0 -> return this+0x24
8323FB6C  0xBA8B94E2 -> return this
8323FB7C  0x42704CE3 -> 0x8323FB8C -> return this+8
8323FB88  otherwise  -> 0x8323FBC0
8323FBC0  0x6BB23909 -> 0x8323FB8C -> return this+8
8323FBD0  default    -> li r3,0; blr   (return null)
8323FBD8  addi r3,r3,-40; b 8323FB38   (adjustor thunk, separate vtable word)
```

The 288-byte class's vtable `0x82522820` (read from the image) is
`+0x00=0x83240030`, `+0x04=0x8323FB20` (GetType -> `0x3C9F47C4`), `+0x08=0x8323FB38` (QI),
`+0x18=0x836D1540` (the getter). **The correct answer of this QI for `0xA6C60698` is null**
(the tag matches none of the six chain entries, so the guest executes `li r3,0; blr`).

The generated code gives `this` for every tag instead. That is the defect.

## 3. The crash chain (VERIFIED)

- `r30 = *(*(*(r31+8)+0xE0)+0x2C)` (`recomp.255.cpp:25343-25350`); the log's `[r8]` dump shows
  `r31+8 = 0xB8F18B00`.
- `r4 = 0xA6C60698` (`lis r4,-22842` / `ori r4,r4,1688`, lines 25364-25369). The log line 299 reads
  `r4=A6C60698`; **the `0xA6960698` used in earlier working notes was a transcription error**.
- `r3 = r30`; `call *(*(r30)+8)` (lines 25362-25376) -> the truncated `0x8323FB38`.
- The tag is not `0x3C9F47C4`, so the body returns with `r3` unchanged; `r29 = r3`
  (line 25379). Therefore **`r29 == r30 == 0xBE2AA530`** - no adjustment and no `r30 != r29` case
  (VERIFIED; this closes the Round-31 inference).
- `if (r29 == 0) goto loc_8333918C` (lines 25401-25404) is the guest's null check. It never fires.
- `r30 = *(r29+0x664)` = `0x70616453` ("padS", line 25409); then `call *(*(r29)+0x18)` and
  `G = *(r29+0x2C)` = `0xBD6BE1D0` (lines 25405-25417).
- `r9 = *(G+0x1C)` = `5` (line 25418); `r5 = *(r9+0x1C)` (line 25427) is the guest read of `0x21`
  at `0x8333916C` (`80A9001C` = `lwz r5,0x1C(r9)`), i.e. `LR+0x23C` from `sub_83338F30`.
- The object is 288 (`0x120`) bytes, so the `+0x664` read is `0x544` bytes past its end; it landed
  in mapped heap and did not fault, which is why the first foreign value ("padS") was accepted.

Why the caller's layout does not fit: the caller expects the interface whose vtable is
**`0x8251C45C`** (`+0=0x832141C8` dtor, `+4=0x832141A8` GetType -> `0xA6C60698`,
`+8=0x8320F970` QI -> returns this for `0xA6C60698`). The object in the slot is the 288-byte
animation class (`0x82522820`), which does **not** implement `0xA6C60698` - hence the QI's null check
exists in the guest. Whether the slot legitimately holds "either kind of object" (and the check is
the filter) or was written with a wrong pointer is the remaining open question (5.5(a)/(b) of
Round 31 was answered as (a), but the writer of the slot was not traced).

## 4. Corrections to Round 31

1. **G's vptr order was swapped.** The primary vptr is **`0x825218B8` at `+0`** and the secondary is
   **`0x825218A4` at `+0x14`** (the tables overlap with a `0x14` stride). The ctor `sub_8323FEB0`
   (`recomp.280.cpp:22604`) stores `0x825218B8` at `+0` and `0x825218A4` at `+0x14`; the live 025
   dump at `0xBD6BE1D0` reads `+0=0x825218B8`, `+0x14=0x825218A4`. G is therefore a **primary**
   object, and Round-31's 5.5 decision criterion is inverted (first word `0x825218B8` = (a)).
   Corrected in place in the Round-31 section.
2. **The tag is `0xA6C60698`**, not `0xA6960698` (log 025 line 299, `r4=A6C60698`; `lis -22842` +
   `ori 1688` = `0xA6C60698`).
3. `sub_8320F970` is the QI that *does* implement `0xA6C60698` (vtable `0x8251C45C`); it is a
   different class from the 288-byte animation object. It is not the function the caller reached.

## 5. Proposed fix (not applied): strong-symbol override of `sub_8323FB38`

### 5.1 Why this shape

The generated function is emitted as a **weak alias** over the real body
(`generated\fifadllzf_xex\worldcup2010_pch.h:57-78`):

```c
__attribute__((alias("__imp__sub_8323FB38")))
__attribute__((weak, noinline)) extern "C" REX_FUNC(sub_8323FB38);
REX_EXTERN(__imp__sub_8323FB38)
```

and the object confirms it: `llvm-nm` on the built
`worldcup2010_recomp.275.cpp.obj` shows `00036000 T __imp__sub_8323FB38` and
`00000000 W sub_8323FB38` (weak external). The registry, the `PPCFuncMappings` table and the
adjustor thunk `sub_8323FBD8` all reference the symbol `sub_8323FB38`
(`worldcup2010_register.cpp:57218`, `worldcup2010_init.cpp:57229`,
`recomp.285.cpp:22537`), so a strong definition in another translation unit replaces all three.

The override mechanism was **verified with this exact toolchain** (clang++ 18 + lld-link, COFF,
`/nodefaultlib`): a test with the same alias/weak pattern plus a strong definition in a second
object linked `caller` to the strong body (`mov eax,2`) rather than the weak body (`mov eax,1`).
The full target flags were used for a `-fsyntax-only` compile of the new file: **exit 0**, both
normally and with the off switch defined.

### 5.2 Files (proposed, under `patches\`)

| patch | applies to | size | SHA-256 | `git apply --check` |
|---|---|---|---|---|
| `round32-1-src_round32_qichain_override.cpp.patch` | `Installer/recomp-template/src/round32_qichain_override.cpp` (new, 136 lines, BSD-3 header) | 5,825 B | `C15455D257404AA61A3A00BDF2BD5B735B153D8EF2E57D6E2E7C161BEA1F37CC` | exit 0 |
| `round32-2-CMakeLists.txt.patch` | `Installer/recomp-template/CMakeLists.txt` (one line in `target_sources(worldcup2010_fifadllzf ...)`) | 418 B | `9E96A227650AED887FFF6239145C2C00ABFA85D71C6DB13DB5F7E4DDFBE2D85E` | exit 0 |

- Checked against a pristine extraction of `git HEAD` (`git archive HEAD`) and against the current
  working tree; both `EXIT=0`. Nothing was applied.
- The build script copies the whole template into the workspace on every build
  (`Installer\BuildWorldCup2010.ps1:122-123`), so the new file and the CMake line reach the build
  without touching `C:\FWC10B\...`.
- `src/stubs.cpp` is already in the same DLL target; the new file is added next to it. The codegen
  step is skipped when the manifest/codegen inputs are unchanged
  (`Installer\BuildWorldCup2010.ps1:197-206`), so this is one configure + one incremental rebuild
  (the new TU + link; the generated TUs are up to date).
- Off switch: `-DREX_R32_DISABLE_QI_CHAIN_OVERRIDE=1` (or remove the CMake line) compiles the file to
  an empty translation unit and the weak generated body is used again.

### 5.3 What the override implements

The exact chain above, with the same pointer adjustments: `0x3C9F47C4` -> this; `0x88B8764F` ->
this+0x28 (or the chain's fall-through if `this+0x24 == 0`); `0x301A1210` -> this+0x24 (or
fall-through); `0xBA8B94E2` -> this; `0x42704CE3` / `0x6BB23909` -> this+8 (0 if `this == 0`);
default -> **0**. It also logs one line, once, when it sees `0xA6C60698` and returns null:
`ROUND32 QI sub_8323FB38: tag=0x... self=0x... -> null`. If the override is not linked, that line is
absent, which distinguishes "fix active" from "fix not applied".

### 5.4 Risks and limits

- The generated `__imp__sub_8323FB38` body stays in the DLL (dead, since no code references
  `__imp__` directly); the config still describes the truncated function. This is a **targeted
  runtime override**, not a recompiler fix - the durable fix is still to extend the extent for
  `8323FB38` and drop/reparent the `8323FB6C`/`8323FB8C` entries. That needs a codegen run, but
  it is **not** a one-line overlap and **not necessarily a full recompile**: `config.cpp:562-580`
  rejects overlapping standalone boundaries (`Overlapping boundaries: ...`, `result.valid = false`),
  and `parent` chunks are the sanctioned mechanism for pieces of one function. The earlier
  "full rebuild" claim is corrected in §8.5: with `-Workspace` the partition sidecar keeps the TU
  assignment and only changed TUs recompile; a build without `-Workspace` deletes `generated/` and
  is full by construction.
- If some code called `__imp__sub_8323FB38` directly, it would bypass the override; the generated
  tree has **no** such reference (grep over `generated\fifadllzf_xex\*.cpp`).
- The class's other truncated functions (`8323FB6C`, `8323FB8C`) are still registered but become
  unreachable from this chain; no image data references them and the only callers were the blocks
  the override replaces (`sub_8323FBA0`, `sub_8323FBC0`).
- If the slot that holds the 288-byte object *should* hold an object implementing `0xA6C60698`,
  the game will now skip the block instead of crashing - correct guest semantics, but a possible
  missing animation/effect. That can be observed in the throw-in test; it does not affect safety.
- The override assumes the chain's tag list is complete for this function; it was read from the
  image at `0x8323FB38..0x8323FBD4` and the function is only entered at `0x8323FB38` and (via the
  thunk) `0x8323FBD8`.

## 6. Open questions

1. Who writes the slot at `*(r8+0xE0)+0x2C` and with what object kind? The crash says it holds the
   288-byte animation object; the caller expects the `0x8251C45C` interface. The QI null check is
   designed for "not implemented", but the writer was not traced. (INFERRED: a guest design where
   the slot is one of several kinds, filtered by QI.)
2. Whether the same truncation produced a wrong `this+0x28`/`this+0x24`/`this+8` pointer earlier in
   the session (tags `0x88B8764F`, `0x301A1210`, `0x42704CE3`, `0x6BB23909`). The override makes
   those answers correct from now on, but any value already stored before the fix would persist in
   that run only.
3. The semantic names of the classes remain unknown (RTTI tags `0x3C9F47C4`, `0xA6C60698`,
   `0x3D94C20C`); no name table exists in the image.

## 7. What approval is needed

Apply the two patches under `patches\` to the repo, rebuild **once** (`BUILD_EXIT_CODE=0` is the
gate), then run **one** throw-in test and compare: the crash must become a skip (no `Null-page
access`, no `ROUND28 guest context`, one `ROUND32 QI ... -> null` line), not a new stop. No push,
no deletion, `ReXGlue/` untouched, profile XUID `0xB13EBABEBABEBABE` unchanged, Hunk A's page-0
refusal unchanged.

> **Executed 2026-10-19:** both patches applied, one incremental rebuild (`BUILD_EXIT_CODE=0`), one
> 152 s title-screen boot (no fault, one `ROUND32 QI ... -> null`). The **throw-in test is the
> remaining step and is left to the user**; no push, no deletion.

## 8. Round 32 apply, audit and verification (2026-10-19)

### 8.1 Applied state

- Pre-change backup: `D:\FWC10\_backups\20261019-160925-r32apply` (`CMakeLists.txt.before`,
  `NOTES.md.before-r32apply`, both patches, `git-diff-before.patch`, `git-HEAD.txt`,
  `git-ls-files.txt`, `git-status-porcelain.txt`, `SHA256SUMS.txt`); a line was appended to
  `D:\FWC10\_backups\LAST_BACKUP.txt` before the build and another after it (§8.9).
- Applied with `git apply` (not `--check`): `round32-1-src_round32_qichain_override.cpp.patch`
  (5,825 B, SHA-256 `C15455D257404AA61A3A00BDF2BD5B735B153D8EF2E57D6E2E7C161BEA1F37CC`) and
  `round32-2-CMakeLists.txt.patch` (418 B, SHA-256
  `9E96A227650AED887FFF6239145C2C00ABFA85D71C6DB13DB5F7E4DDFBE2D85E`); both exit 0.
  `git status` now has `M Installer/recomp-template/CMakeLists.txt` and the new untracked
  `Installer/recomp-template/src/round32_qichain_override.cpp`. No config entry was changed.
- Off switch unchanged: `-DREX_R32_DISABLE_QI_CHAIN_OVERRIDE=1` (or removing the CMake line)
  compiles an empty TU and the generated weak body is used again.

### 8.2 Task 1 - audit of all 291 override entries (both copies)

**Method (VERIFIED).** The two copies are byte-identical, SHA-256
`6DE35890AE9D8A6C5043CEDF56331D82040B15EDFFAB195A49B2F714E9D2B0F3`, 291 entries each. Decoding
used the decrypted flat image `C:\Users\ramic\AppData\Local\Temp\opencode\xexdump\fifadllzf.dec.bin`
(flat image; `file_offset = guest_addr - 0x82300000`, code/data big-endian; the PE section raw pointers are not used).
`.pdata` at RVA `0x2D6000` decodes as 58,601 big-endian `RUNTIME_FUNCTION` entries
(`begin + ((info >> 8) & 0x3FFFFF) * 4`). For each entry the last word at `end-4` was decoded,
then the word at `end`; `end` was checked against every `.pdata` start/end, every other override
start, and every other override extent. Terminators accepted: `blr` (`bclr` BO=20 LK=0), `bctr`
(`bcctr` BO=20 LK=0), unconditional `b` (opcode 18 LK=0), `tw`/`twi`, `sc`/`rfi`/`rfid`.
Non-terminators: `bclr`/`bcctr` with BO!=20 (conditional return, falls through), `bc` (falls
through), `bl`/`bctrl`/`bclrl` (link call; the post-call path is lost), and ordinary instructions.

**First pass - last-instruction class (VERIFIED).**

| class | entries | last instruction |
|---|---:|---|
| hard terminator | **289** | `bctr` 138, `b` 91, `blr` 60 |
| conditional return | **2** | `bclr 12,26` = `beqlr cr6` |
| conditional branch / ordinary / link call | 0 | - |

- All 91 `b` endings target **outside** their own extent (0 backward/inside targets), so they are
  tail branches, not truncated loops.
- The 291 TOML keys (starts) are unique; no duplicate starts.
- There are **no** entries whose *last* instruction is a conditional branch, an ordinary
  instruction, or a link call.

**Second pass - reachability of the word at `end` (VERIFIED).** A hard last instruction does not
by itself prove the extent is whole: an earlier branch may target `end`. Every word of every
extent was decoded (`deepaudit.py`), and the next word's registration was checked against the
generated `worldcup2010_init.cpp` / `worldcup2010_register.cpp` and `DEFINE_REX_FUNC` symbols.

| sub-class of the 289 hard-terminator entries | entries | finding |
|---|---:|---|
| followed by padding / a registered start / `.pdata` boundary | **210** | clean boundary |
| next word is real code but **not** a registered start; no branch inside targets it | **67** | not the same logical function; not truncation |
| interior **conditional branch targets `end`**; target is a registered function | **10** | **split extents** - codegen tail-calls the registered target |
| last `b` targets a shared body 8/0x10 bytes past `end`; bytes between are separate thunks | **2** | normal adjustor-thunk tail, not truncation |

The 10 split extents are `L38 0x82A9F6C8->0x82A9F70C`, `L52 0x8265A330->0x8265A354`,
`L100 0x82AE3F70->0x82AE3F90`, `L195 0x8314DB68->0x8314DB80`, `L213 0x837EDBA0->0x837EDBE4`,
`L258 0x83367538->0x83367574`, `L265 0x837A6C70->0x837A6CA0`, `L297 0x82F1EFE8->0x82F1F01C`,
`L305 0x831ADE50->0x831ADE7C`, `L348 0x83884CA0->0x83884CEC`. They are 5 in Stage 6b
(L38/L52/L100/L195/L213), 4 in Stage 6d (L258/L265/L297/L305) and 1 in Stage 6e (L348). Every
target is registered (`worldcup2010_init.cpp`) and has a `DEFINE_REX_FUNC`; the generated entry
bodies all contain `sub_<end>(ctx, base); return;` (verified for all 10 by `tailcheck.py`;
`L348` has four such sites). These are **config-incomplete** (the function is split into two
registered functions), but they are not the FB38/FB6C defect: the branch is explicit, so the
codegen emits a tail call to the correct body. No semantic loss is proven. The 2 thunks are
`L153 0x82BD9AF0->0x82BD9B00` and `L178 0x82BDCED0->0x82BDCEE8`; the next bytes are other
`addi r3,r3,-delta; b` thunks, so the `b` is a tail branch to the shared body, not a
continuation of this thunk.

**Semantic truncation list (the only two of the FB38 class).**

| line | start -> end | last word @ address | decoded | next @ end | word | finding |
|---:|---|---|---|---|---|---|
| 328 | `0x8323FB38 -> 0x8323FB48` | `0x4D9A0020` @ `0x8323FB44` | `bclr 12,26` = `beqlr cr6` | `0x8323FB48` | `0x3D4088B8` = `lis r10,0x88B8` | The next instruction is the **same chain's** second tag test (`0x88B8764F`); the first `beqlr` is a conditional return and its fall-through is real code. The generated body (`recomp.275.cpp:21862`) is only the first compare + `if (ctx.cr6.eq) return;`. |
| 329 | `0x8323FB6C -> 0x8323FB7C` | `0x4D9A0020` @ `0x8323FB78` | `bclr 12,26` = `beqlr cr6` | `0x8323FB7C` | `0x3D604270` = `lis r11,0x4270` | Same defect: the next instruction is the chain's `0x42704CE3` test. The generated `sub_8323FB6C` has only the `0xBA8B94E2` compare + `if (ctx.cr6.eq) return;`. |

The audit script's mnemonic printer labels BO=12 as `bneqlr`; the raw encoding `0x4D9A0020` is
`bclr 12,26` (BO=12 = branch if CR6.eq true), i.e. `beqlr cr6`. The two verdicts stand on the raw
word, not on the label.

`.pdata` does **not** cover `0x8323FB38..0x8323FBE0`: the nearest runtime functions are
`0x8323FA88..0x8323FB20` and `0x8323FBE0..0x8323FC4C`. These are no-block stubs, so `.pdata`
cannot be used to excuse the boundary.

**14 Tier-1 stubs (13 fifadllzf + 1 default).**

| stub | end | last instruction | verdict |
|---|---|---|---|
| `0x8323FB38` | `0x8323FB48` | `beqlr cr6` | **RISK** (truncated same chain) |
| `0x8323FB6C` | `0x8323FB7C` | `beqlr cr6` | **RISK** (truncated same chain) |
| `0x8323FB8C` | `0x8323FBA0` | `subfic/addi/subfe/and; blr` | CLEAN (complete `(this==0)?0:this+8`) |
| default `0x8211A170` | `0x8211A178` | `addi r3,r3,8; b 0x82118AB8` | CLEAN; next `0x8211A178` is a separate `addi r3,r3,-8` thunk |
| other 10 (`0x82A63768`, `0x82ADF698`, `0x82ADF6B0`, `0x82BCBDB8`, `0x82DA6148`, `0x831A11B8`, `0x83232D58`, `0x837045C0`, `0x83704A30`, `0x8375B9D0`) | per Round 14 | 3 `bctr`, 5 `b`, 2 `blr` (all targets outside) | CLEAN |

**9 thunks `0x837FD0F0..0x837FD170`:** all nine end in `bctr`; each `end` is the next thunk's
registered start. CLEAN.

**Earlier batches:** Stage 6a `0x835F7700` CLEAN (`blr`); Stage 6b 183 last-instruction-clean
(5 of them are split; see above); Stage 6c 2 CLEAN
(`0x82EEFB68` and `0x82883A48`, both `blr`); Stage 6d 80 last-instruction-clean (4 of them are
split; see above); Stage 6e `0x83884CA0` **SPLIT** (`blr` at the end, but four interior
`beq 0x83884CEC`; `0x83884CEC` is registered and the generated body tail-calls it); Stage 6f
`0x836A24B0` CLEAN (`b 0x8369C858`; next `mfspr`); Round 27 `0x8295FB50` CLEAN (`b 0x8295F988`).

**Correction (Task 5).** The Round-14 statement that Tier 1 consists of standalone "leaf"/"epi"
stubs is wrong for `0x8323FB38`, `0x8323FB6C` and `0x8323FB8C`: they are three entry points into
one 0xA0-byte chain. The validator's "max reachable + 4" treated the conditional return `beqlr` as
a terminator, so the first two extents stop after their first `beqlr`; `0x8323FB8C` is the one
piece that is genuinely complete. The correction is also placed under the Round-14 Tier-1 table
(`# Round 15` section) so the old table is not read as still true.

### 8.3 Task 2 - callers and references of `0x8323FB38 / FB6C / FB8C`

**Direct branches in the guest `.text`** (`0x82650000..0x838D8DB4`, every 4-byte word decoded):
exactly **5** branches target the six addresses, and all five are inside the chain:

| site | instruction | target | role |
|---|---|---|---|
| `0x8323FB58` | `beq cr6` (`0x419A0048`) | `0x8323FBA0` | tag `0x88B8764F` -> FBA0 |
| `0x8323FB88` | `bne cr6` (`0x409A0038`) | `0x8323FBC0` | tag `0x42704CE3` mismatch -> FBC0 |
| `0x8323FBB4` | `beq cr6` (`0x419AFFB8`) | `0x8323FB6C` | FBA0 null-guard -> FB6C |
| `0x8323FBCC` | `beq cr6` (`0x419AFFC0`) | `0x8323FB8C` | tag `0x6BB23909` -> FB8C |
| `0x8323FBDC` | `b 0x8323FB38` | `0x8323FB38` | adjustor thunk `0x8323FBD8` |

There is **no** `bl`/direct call to any of the three from outside the chain. Generated-tree greps
agree: the only `sub_8323FB38(ctx, base)` is `recomp.285.cpp:22537` (thunk `sub_8323FBD8`), the
only `sub_8323FB6C(ctx, base)` is `recomp.211.cpp:21437` (`sub_8323FBA0`'s `beq`), and the only
`sub_8323FB8C(ctx, base)` is `recomp.153.cpp:22463` (`sub_8323FBC0`'s `beq`). `FBA0` and `FBC0`
have no call sites of their own.

**Data/table references** (aligned big-endian words in `.rdata`/`.data`/`.pdata`):

| word address | value | context |
|---|---|---|
| `0x8252274C` | `0x8323FB38` | table at `0x82522744`: `[0x8323FA18, 0x8323FB20, 0x8323FB38, ...]` (slot +8) |
| `0x82522828` | `0x8323FB38` | primary vtable `0x82522820`: `+0=0x83240030`, `+4=0x8323FB20`, `+8=0x8323FB38` |
| `0x82522710` | `0x8323FBD8` | secondary vtable; preceding word `0x8252270C=0x8323FB30` (the `-0x28` GetType thunk) |
| `0x825227DC` | `0x8323FBD8` | second secondary vtable |

**No** data word equals `0x8323FB6C`, `0x8323FB8C`, `0x8323FBA0` or `0x8323FBC0`. A broad
materialization scan (every `lis rD,imm` followed within 6 instructions by `ori`/`oris`/`addi` on
the same register, any high half, to catch `lis 0x8324` + negative `addi`) produced **0** values
equal to any of the six addresses. (The `0xFB38`/`0xFB6C`/`0xFB8C` low-half `addi` hits in
`.text` are unrelated stack offsets.)

**What each entry point expects.**

- `0x83338F30` (the crash caller; `recomp.255.cpp`: QI call at 25362-25376, null check at 25401):
  loads `r11=*(r30)`, sets `r4=0xA6C60698`, `r3=r30`, loads `r10=*(r11+8)`, `bctrl` with
  `LR=0x83339114`. After the call: `r9=*(r30+4)`, `r29=r3`, `r11=r9-1` (overwrites r11),
  `CR0=addic.`, then (after a `+12` slot call) `cmplwi cr6,r29,0` / `beq 0x8333918C`. It consumes
  only `r3`; `r10` is never read after the call, and `r11`/`CR0`/`CR6` are overwritten. It expects
  **the interface pointer or null** and has a skip path for null.
- Thunk `0x8323FBD8`: `addi r3,r3,-0x28; b 0x8323FB38`. It is reached from the two secondary
  vtables; the override therefore sees the **primary** pointer after the adjustment and returns
  primary-relative `this+0x24` / `this+0x28` / `this+8`.
- `FBA0` (tag 2): `r11=this+0x24; subfic/subfe/and` -> `(plus24==0)?0:plus24+4`; if nonzero
  `mr r3,r11; blr`, else `beq 0x8323FB6C`. It expects the chain to continue at FB6C only for an
  invalid `this`. `FBC0` (tag 6): `0x6BB23909 -> 0x8323FB8C`, else `li r3,0; blr`.
- **FB6C direct?** Only from `FBA0`'s `beq` at `0x8323FBB4`; **FB8C direct?** Only from `FBC0`'s
  `beq` at `0x8323FBCC`. Since `FBA0`/`FBC0` have no external data/code references, no caller
  reaches FB6C or FB8C directly. The strong FB38 override covers every reachable path, so those
  symbols do not need their own override. (Static proof; a runtime-computed pointer that is not
  in the image would not be visible to this scan - INFERRED low risk.)
- The registry still maps all six guest addresses (`worldcup2010_init.cpp:57229-57234`,
  `register.cpp:57218-57223`), but registration is a table, not a jump; the only entered addresses
  are the vtable slots above. The FB38 mapping now points at the override (§8.6).

### 8.4 Task 3 - C++ review against the decoded chain

Source: `Installer/recomp-template/src/round32_qichain_override.cpp:78-134`. The guest words are
from the image (`0x8323FB38..0x8323FBD4`); the C++ line numbers are from the applied file.

| tag | guest instructions | C++ | returned `r3` |
|---|---|---|---|
| `0x3C9F47C4` | `lis r11,0x3C9F; ori r11,0x47C4; cmpw cr6,r4,r11; beqlr cr6` | `if (tag == 0x3C9F47C4u) return;` (lines 84-86) | `this` (untouched) |
| `0x88B8764F` | `lis r10,0x88B8; addi r11,r3,0x24; ori r10,0x764F; cmpw; beq 0x8323FBA0`; FBA0 `subfic r10,r11,0; addi r11,r11,4; subfe r10,r10,r10; and r11,r10,r11; cmplwi r11,0; beq 0x8323FB6C; mr r3,r11; blr` | `plus24=self+0x24; adjusted=(plus24!=0)?plus24+4:0; if (adjusted!=0){r3=adjusted; return;}` (88-99) | `this+0x28` (valid `this`); 0 if `this+0x24` is null |
| `0x301A1210` | `lis r10,0x301A; ori 0x1210; cmpw; beq 0x8323FBB0`; FBB0 `cmplwi r11,0; beq 0x8323FB6C; mr r3,r11; blr` (r11=`this+0x24`) | `else if (tag==0x301A1210u){ if (plus24!=0){r3=plus24; return;} }` (100-108) | `this+0x24` |
| `0xBA8B94E2` | `lis r11,0xBA8B; ori 0x94E2; cmpw; beqlr cr6` | `if (tag == 0xBA8B94E2u) return;` (110-113) | `this` |
| `0x42704CE3` | `lis r11,0x4270; ori 0x4CE3; cmpw; bne 0x8323FBC0`; fall-through FB8C `subfic r11,r3,0; addi r10,r3,8; subfe r11,r11,r11; and r3,r11,r10; blr` | `if (tag != 0x42704CE3u) { ...tag 6 / default... }` then `r3=(self!=0)?self+8:0` (116-133) | `this+8` (0 if `this==0`) |
| `0x6BB23909` | FBC0 `lis r11,0x6BB2; ori 0x3909; cmpw; beq 0x8323FB8C`; else `li r3,0; blr` | inside `if (tag != 0x42704CE3u)`: `if (tag==0x6BB23909u){r3=(self!=0)?self+8:0; return;}` (118-121) | `this+8` (0 if `this==0`) |
| default | `0x8323FBD0 li r3,0; blr` | `r3=0; return;` (123-129) | `0` |
| `0xA6C60698` (not a chain tag) | default path | one-shot log inside the default branch, then `r3=0` (124-129) | `0` |

The C++ matches the decoded semantics, including the two null-guard fall-throughs. Note the guest
instruction at `0x8323FBB8` is `or r3,r11,r11`, canonicalized as `mr r3,r11` (generated
`// mr r3,r11` / `ctx.r3.u64 = ctx.r11.u64`); the C++ assignments match that. `FB8C`'s
`subfic/subfe/and` idiom is exactly `(self==0)?0:self+8`.

**Register side effects.** The guest chain writes `r10` and `r11` (tag constants, `this+0x24`,
`this+0x28`), `CR6` (each `cmpw`/`cmplwi`) and `CA` (the `subfic/subfe` sequences). The override
writes **only `ctx.r3`** (plus host-side `std::atomic` state and the log call); it never touches
`ctx.r10`, `ctx.r11`, `ctx.cr6`, `ctx.xer` or `ctx.lr`. The traced caller `0x83338F30` reads only
`r3` (as `r29`), overwrites `r11` at `25381-25383`, overwrites `CR6` at `25401`, and never reads
`r10`; `LR` was set by the caller. For any other ABI-conforming caller, `r10`/`r11`/`CR6`/`CA` are
volatile (caller-saved), so leaving them alone is safe. **VERIFIED** for `0x83338F30`; **INFERRED**
(ABI) for untraced callers.

**Tested vs reasoned.** Runtime-tested: the `0xA6C60698` -> default -> null path, once, at
16:32:39 in `worldcup2010_026.log`; the game did not fault. Compiled-code-verified: the six tag
immediates are present in the DLL disassembly at `0x18719C5A4..` (`cmpl $0x3c9f47c4`,
`cmpl $0x88b8764f`, `cmpl $0x301a1210`, ...); the `cmpl $0xa6c60698` is at `0x18719C5E7` and
the log string `lea` is at `0x18719C681`.
**Not runtime-tested:** the override logs only `0xA6C60698`, so the 152 s log does not show
whether the six chain tags (`0x3C9F47C4`, `0x88B8764F`, `0x301A1210`, `0xBA8B94E2`,
`0x42704CE3`, `0x6BB23909`) were queried; their mapping is reasoned from the image and confirmed
by the compiled x86, not by a runtime hit.

### 8.5 Why overlapping extents are rejected, and the incremental/full rebuild question

**Overlapping extents (VERIFIED).** `ReXGlue/src/codegen/config.cpp:562-580`:

```cpp
// Check for overlapping function boundaries (standalone functions only)
...
if (!cfg.isChunk()) {
  sorted.emplace_back(addr, cfg.getSize(addr));
}
...
if (sorted[i].first < prev_end) {
  result.errors.push_back(fmt::format(
      "Overlapping boundaries: 0x{:08X}+0x{:X} overlaps 0x{:08X}+0x{:X}", ...));
  result.valid = false;
}
```

A configuration that extends `8323FB38` to `0x8323FBD8` while keeping the standalone `8323FB6C`
(`end 0x8323FB7C`) and `8323FB8C` (`end 0x8323FBA0`) entries is therefore a fatal validation error,
not a warning. The sanctioned way to describe pieces of one function is the `parent` chunk field
(`config.h:43-49`: "A 'chunk' is simply a function entry with a non-zero parent field"), which the
overlap check explicitly skips via `if (!cfg.isChunk())`. This is the same rule that produced the
Round-14 "4 conflict" finding: "the CFG extent genuinely contains a *sibling* registered entry, so
no single contiguous `end` both covers the reachable code and avoids overlapping"
(`NOTES.md:2208-2209`).

**Why the durable fix was said to need a full recompile - corrected.** The earlier §5.4 wording
"a codegen run and a full rebuild" is too strong. The observable reason earlier override-only
rebuilds recompiled only the affected files (14 TUs in Round 15) is the stable partition sidecar
plus a resume build:

- `Installer/BuildWorldCup2010.ps1:77` `$resume = ![string]::IsNullOrWhiteSpace($Workspace)`;
  lines 176-184 delete `generated\default` and `generated\fifadllzf_xex` **only when `!$resume`**.
- `codegen_writer.cpp:278-279` `OutputPartition::Load(outputPath / kPartitionFileName)` then
  `Assign(sizes, maxFileBytes)`; `output_partition.cpp:102-150` reuses each existing
  `addressToFile_` assignment and only places new functions into the smallest bucket, so the TU
  numbers do not shift just because a function grew.
- `codegen_writer.cpp:345` `switch (WriteIfChanged(filePath, content))`; unchanged TUs are skipped
  (`Unchanged, skipping write`). Ninja then compiles only files whose content changed.

So a durable fix built **with `-Workspace`** should be incremental: the codegen re-runs because a
config file is in the fingerprint (`BuildWorldCup2010.ps1:197-207`), rewrites the TUs containing
`FB38`/`FB6C`/`FB8C` (and the global init/register/funcs files), and leaves the rest unchanged. A
build **without `-Workspace`** deletes `generated/` first, which also deletes
`codegen.partition.json`; `ChooseFileCount`/`Assign` then repartition from scratch
(`output_partition.cpp:104-113`), so the TU assignment can change broadly and the compile is full
**by construction**. The durable fix has not been run, so the exact changed-TU set is **INFERRED**,
not measured. The current build used `-Workspace`, so the codegen skipped
(`Codegen summary: 0 written, 2 unchanged`) and only the new TU + link were compiled, as predicted.

### 8.6 Task 4 - one rebuild and DLL-level proof

**Build (VERIFIED).** Command:
`Installer\BuildWorldCup2010.ps1 -GameData ...\dist\GameData -Output ...\dist\Output -Workspace C:\FWC10B\fwc10stage4 -SourceBuild -Jobs 2`; wrapper output 62 lines;
`BUILD_EXIT_CODE=0`. Key lines:

```
[8/36] Generating recompiled code for worldcup2010
Codegen summary: 0 written, 2 unchanged, 0 deleted, 2 module(s) up to date
[9/13] Building CXX object .../worldcup2010_fifadllzf.dir/src/round32_qichain_override.cpp.obj
[10/13] Linking CXX shared library worldcup2010_fifadllzf.dll
[12/13] Linking CXX executable worldcup2010.exe
```

Artifacts:

| file | size | SHA-256 | note |
|---|---:|---|---|
| `worldcup2010_fifadllzf.dll` | 123,055,616 B | `502744EE626E6ED7E687132E658244C4D4F70199E5BE578B0845952BE63113F9` | was 123,053,568 B (`CFF87086...`); +2,048 B |
| `worldcup2010.exe` | 8,022,528 B | `74481EBD88EE454166F28A353CD09B063E86384EB4DDADFF9628E9D909BC15BA` | relinked |
| `rexruntime.dll` | 10,216,960 B | `715E0D917B315358AFEEB3C9493466B0A2E17F67E6FD9FB3B87A4DB974CD0E1F` | same size, new hash; relinked incidentally after the configure rebuilt `debug_overlay.cpp`; this round's patch is project-only |

**Strong vs weak (VERIFIED).** `llvm-nm`:

- new TU `round32_qichain_override.cpp.obj` (51,082 B): `00000000 T sub_8323FB38` (strong), plus
  the `ROUND32 QI sub_8323FB38...` string symbol.
- generated `worldcup2010_recomp.275.cpp.obj`: `00036000 T __imp__sub_8323FB38` and
  `00000000 W sub_8323FB38` (weak).

**In the linked DLL (VERIFIED).** No symbols are exported, so the image was parsed directly:

- `PPCFuncMapping` entry (16 bytes: `size_t guest; PPCFunc* host`) at file offset `0x73F1B00`
  (RVA `0x73F3700`): `guest=0x8323FB38`, `host=0x18719C580` (RVA `0x719C580`). The contiguous
  neighbours are `FB6C` (`0x73F1B10`), `FB8C` (`0x73F1B20`), `FBA0`, `FBC0`, `FBD8`, so this is the
  real mapping array.
- Disassembly at `0x18719C580` is the full chain: `cmpl $0x3c9f47c4` at `0x18719C5A4`,
  `cmpl $0x88b8764f` at `0x18719C5AC`, `cmpl $0x301a1210` at `0x18719C5C6`, `cmpl $0xa6c60698`
  at `0x18719C5E7`; the `ROUND32 QI` string is at RVA `0x720DED8`, loaded by the `lea` at
  `0x18719C681`. This is the override, not the one-compare weak body.
- The `-0x28` thunk: guest `0x8323FBD8` -> host `0x6415CA0`; bytes at `0x6415CA0` are
  `48 83 01 D8 E9 D7 68 D8 00` = `add qword ptr [rcx], -0x28; jmp 0x719C580`. This is the only
  `E8`/`E9` in the image whose target is `0x719C580`.
- The generated `__imp__sub_8323FB38` body remains in the image but is unreferenced; the registry
  and the only direct caller both resolve to the strong override.

### 8.7 Task 4 - 152 s title-screen boot

- Window `2010 FIFA World Cup South Africa PC` at 0.9 s; screenshots at 20/40/60/90/120/150 s
  (223,343 / 212,641 / 231,268 / 5,764 / 516,556 / 512,131 B); still running at 152 s, then killed.
- Log volume: **1 file, `worldcup2010_026.log`, 47,613 B, 282 lines**, last write 16:33:29
  (Round 31 reference: 48,269 B / 284 lines).
- **New functional line (exactly one):**
  `[2026-10-19 16:32:39.508] [info] [krnl] [t25992] ROUND32 QI sub_8323FB38: tag=0xA6C60698 self=0xBE2A6CE0 -> null`
- Fault markers: `Null-page access` **0**, `Unhandled guest access violation` **0**,
  `ROUND28 guest context` **0**, `FATAL` **0**, `INVALID INDIRECT CALL` **0**,
  `ROUND30 fault loop` **0**, `ROUND30 minidump` **0**.
- Known benign/noise: 65 `ROUND30 exception: host RIP` lines (Round 31: 67), 42 `ROUND29D` lines
  (Round 31: 46; the functional set is present - 4 sign-in, per-index XUID, aggregate/enumerator,
  content-create). Asset IDs, shader counts and pipeline counts differ from Round 31 because the
  boot's random/flow path differs; no new message class other than `ROUND32`.
- No `worldcup2010` process was left running after the kill.

### 8.8 What remains

1. **Throw-in test (user).** The title-screen boot hit the crash tag once and returned null without
   a fault; the original crash was after a throw-in cutscene. The throw-in test is the decisive
   test and has not been run by this round.
2. If it still stops, capture the `ROUND32` line (if any) plus the fault block. Only
   `0xA6C60698` is logged; a different tag would not appear, so the fault block and the
   `self` pointer are the evidence.
3. Durable fix: extend `8323FB38`, drop/reparent `8323FB6C`/`8323FB8C` (and account for the
   discovered `FBA0`/`FBC0` targets), re-run codegen with `-Workspace`, then rebuild. Not done;
   see §8.5 for the overlap rule and the incremental expectation.
4. No push, no deletion; profile XUID and Hunk A unchanged.

### 8.9 Backup artifacts and `LAST_BACKUP.txt`

- Pre-change: `D:\FWC10\_backups\20261019-160925-r32apply` contains `CMakeLists.txt.before`,
  `NOTES.md.before-r32apply`, both patches, `git-diff-before.patch`, `git-HEAD.txt`,
  `git-ls-files.txt`, `git-status-porcelain.txt`, `SHA256SUMS.txt`. The pre-change DLL was
  **not copied**; its size and SHA-256 (`CFF87086...`, 123,053,568 B) are recorded. The
  source/config/notes state is recoverable from the backup + git; the old binary is not
  bit-recoverable.
- Post-change: `...\after\` holds the build transcript, boot report, `worldcup2010_026.log`,
  the audit scripts + `audit.json`, the six screenshots, the applied source and `CMakeLists.txt`,
  the updated `NOTES.md`, `git-status-after.txt`, `git-diff-after.patch`, and `hashes.txt`
  (DLL/EXE/rexruntime size, SHA-256, timestamp; log/notes/source hashes).
  `SHA256SUMS.after.txt` hashes every file under `after\`.
- `D:\FWC10\_backups\LAST_BACKUP.txt` has the pre-build line
  (`20261019-160925-r32apply  Round 32 APPLY BEFORE BUILD ...`), the post-build line
  (`... AFTER build+boot ...`: DLL/EXE hashes, log size/lines, `ROUND32=1`, `fault=0`), and the
  audit-refinement line (`... AFTER audit refinement ...`: the 10 split extents and the final
  `NOTES.md` SHA-256).
- No push, no deletion; `ReXGlue/` untouched.


## Select Team globe hit-test investigation (2026-10-19, read-only)

**Scope:** No build, game launch, source/config change, or asset extraction. The user's `data1.big` was opened read-only and only its index / selected entry bytes were read. Before this append, `NOTES.md` was copied byte-for-byte to `D:\FWC10\_backups\NOTES-before-select-team-20261019-212131.md` (same SHA-256 as pre-append note: `85E17780F853A537B411BD9F2DC49C6F7F552945535B43EF9C60DAC7301657E7`). Existing user changes and unrelated backup files were preserved.

### VERIFIED

- `data1.big` indexes `data/sceneassets/globe/countries.msh` (offset `0x0DE28670`, 2,519,568 B), immediately followed by `countries_select.msh` (`0x0E08F880`, 2,680,216 B), then `globe_0.rx3` and `globe_1.rx3`. The selected mesh begins `00 01 87 A8 3D 00 00 00 ...`; it has no readable ASCII country names/IDs in the sampled header. The first BE32 is `0x187A8` (100,264), followed by float-like coordinate bytes. **This is not enough to establish the mesh schema, vertex count semantics, per-country submeshes, IDs, bounds, or absence of such metadata.** No extraction or writes to the archive occurred. Archive SHA-256 observed: `9A598E86CF63CA044CA7D0231DA3413A14258D180B9BF80D54E0B61E4FBD84A9`.
- UI archive entries include `playnow/globehubscreen.big` (8,192 B), `playnow/panels/teamselectpanel.big` (11,140 B), and `components/teamselector.big` (8,644 B). Readable embedded strings include `GLOBE_HU`, `CONFEDER`, `mcConfed`, `MOVE_CUR`, `Selected`, and `TeamSelector::initRules`. These are UI asset strings, not guest-code symbols or proof of a particular hit-test.
- The only traced generated-code `XamInputGetState` wrapper is `sub_8319BEC0` (`mr r5,r4; li r4,1; b 0x838d7eac`). A caller at `sub_82A74ED0` polls it in a loop, then handles button/keystroke-like data (`lhz` at stack offsets 96/98/100, flags, and `XamInputGetKeystrokeEx`-style helper calls). This is generic input/event handling; no evidence connects it to Select Team or right-stick cursor motion.
- `ReXGlue` input fields are signed 16-bit values (`include/rex/input/input.h`); SDL maps right X/Y to `thumb_rx`/`thumb_ry` and inverts Y. This confirms the runtime representation, not which guest screen consumes the values.

### INFERRED / unresolved

- Asset adjacency and names suggest a selectable-country globe mesh, but do not prove ownership, load call, marker data layout, or interaction semantics. Searches of generated C++ and runtime source did not locate the literal asset path or a loader reference; packaged `.big` UI components are binary and do not name their native guest handler in an immediately traceable way.
- **The hit-test mechanism remains undetermined**: no ray/nearest-point CPU routine, GPU ID-buffer/readback call, or other selection path was isolated. Accordingly there is no defensible quote of the hit-test instructions/call site, no relevant VMX/float sequence to compare against Xenon behavior, and no basis to claim an Xenia shared failure is due to math or readback. The earlier readback defaults are not evidence that this screen uses either path.
- The input caller identified above is not enough to identify thumb sampling; do not treat it as the Select Team handler.

### Diagnostic decision

No diagnostic diff is justified yet: without the actual hit-test function there is no verified point to instrument and logging generic input could mislead. No diff was created, applied, or checked. The user's manual readback experiments remain pending. Further source-level progress needs a reliable route from the UI component's `MOVE_CUR`/`CONFEDER` event binding or asset loader to the guest callback (or a runtime trace the user authorizes).

## Team globe replacement feature — Phase 1 location pass (2026-10-19)

**Read-only investigation.** No source/config edits, build, launch, or game-data extraction. The only repository writes for this pass are this NOTES append and the matching backup-ledger record; the existing working tree was inspected and preserved. Immediately before these documentation writes, byte-for-byte backups were made:
- `D:\FWC10\_backups\NOTES-before-team-globe-phase1-20261019-212421.md` (pre-write SHA-256 `1A91A1D3A273C74F3996567D687EE17361CE5B552CAF7214D768324B1DC6A24C`)
- `D:\FWC10\_backups\LAST_BACKUP-before-team-globe-phase1-20261019-212421.txt` (pre-write SHA-256 `BF642FD03CFE02D5FB72C0BE367665F5402A8EA0D3F60C755F29CB5A54AFAB48`)

### VERIFIED

- In `data1.big`, the entries are adjacent: `data/sceneassets/globe/countries.msh` (offset `0x0DE28670`, 2,519,568 bytes), `countries_select.msh` (`0x0E08F880`, 2,680,216 bytes), `globe_0.rx3`, and `globe_1.rx3`. The selected mesh's first bytes are `00 01 87 A8 3D 00 00 00 ...`; there is no readable country label in the sampled header. This does **not** decode the mesh schema or establish whether it has per-country parts/IDs/bounds. Marker coordinates were not separated from the mesh or any other data.
- The three relevant UI assets are `playnow/globehubscreen.big` (8,192 bytes), `playnow/panels/teamselectpanel.big` (11,140 bytes), and `components/teamselector.big` (8,644 bytes). Readable strings include `GLOBE_HU`, `CONFEDER`, `mcConfed`, `MOVE_CUR`, `Selected`, `localEventHandler` (truncated by binary/string boundaries), and `TeamSelector::initRules`. These confirm labels/names occur in assets, but are not themselves code references to guest callbacks.
- Searching all generated guest `.cpp`/`.h` for those exact event/class strings did not find code literals. Candidate hashes were computed (CRC32 and FNV-1a32, uppercase bytes) for `MOVE_CUR` (`CRC 8c2684b2`, FNV `6ebc85f1`), `GLOBE_HU` (`f16719f4`, `3504a798`), and `CONFEDER` (`41a0df89`, `4b0a63e1`). These candidate 32-bit values were not found in the sampled UI assets in either byte order; no hash algorithm is established, so this is not a definitive negative result.
- Guest controller wrapper `sub_8319BEC0` forwards `(user, state*)` to import `XamInputGetState` (`mr r5,r4; li r4,1; b 0x838d7eac`). A caller in `sub_82A74ED0` loops across devices and processes state/keystroke fields. It is generic input polling; no call edge connects it to the globe screen. Searching generated files for literal signed loads at offsets `+12` and `+14` did not identify a function reading both as right-stick values. No 2D cursor/angle storage location was established.
- The `teamselectpanel.big` embedded string `MOVE_CUR` and `mcConfed` suggests an event/panel path. No selection variable, setter, team-changed notification, arrow/left-stick update path, or flag/stats refresh routine was located in guest code.
- Runtime source inspection found no general BIG4/game UI component parser; the visible BIG4 use in ReXGlue is the specialized font loader (`src/ui/game_ui_fonts.cpp`). The guest engine appears to own these UI components, but exact load/dispatch path was not traced.

### INFERRED / unresolved

- The UI names suggest event-driven team-selection behavior; they do not prove whether `MOVE_CUR` is a cursor event, a movement action, or an event gated on a UI state not reached. The shared symptom in Xenia and our build is compatible with an original-game logic/state issue, but does not prove one.
- No nation marker table, cursor coordinate, selected-team memory, callback target, or hit-test was identified. Therefore no evidence-based choice among CPU nearest-point, CPU mesh ray test, GPU readback, or missed state-gated event is possible. No instruction-level Xenon/recompiler analysis applies yet.
- **Replacement feasibility: LOW on current evidence** (INFERRED). **Status: ACTIVE — dynamic memory analysis is the approved current approach;** prior static replacement feasibility remains LOW and is superseded by this investigation. The visible panel and mesh are not enough to safely choose and update a team. Host-side replacement would need a verified source for crosshair coordinates and nation point data plus the game's own selection setter/notification; writing state by guessed address risks corrupting team selection and bypassing dependent UI/audio updates.

### Smallest design if the real handler proves unrepairable (proposal only)

At a verified per-frame globe-screen update/override hook, read the game's current cursor in its native coordinate space and a verified nation-point list; select the nearest eligible point only while the globe/team-select state is active and when cursor movement or the current hovered nation changes. Call the same guest setter/event used by arrow selection so flag, name, stats, and dependent UI remain coherent. Rate-limit diagnostic output to the first N actual nation changes. Keep behind an off-by-default cvar. **No hook or data source is currently verified, so this is not yet implementable as a safe diff.** Failure modes include wrong coordinate transform/rotation, back-side or occluded markers being eligible, duplicate/coincident points, wrong candidate list, state-transition false positives, and invoking the setter with stale team IDs.

**Phase 1 stop:** No diff drafted or checked. Phase 2 requires explicit user approval; until then no code changes/build/launch. User-owned readback tests remain pending.

### Optional UI container format check (read-only, 2026-10-19)

**VERIFIED:** The relevant `data1.big` entries have `.big` names and begin with the custom `BIGF` container signature, not Flash/Scaleform `FWS`, `CWS`, `GFX`, or `CFX`. Examples (first 16 bytes):

| Entry | Strings found | First 16 bytes |
|---|---|---|
| `data/ui/game/screens/playnow/panels/teamselectpanel.big` | `mcConfed`, `MOVE_CUR` | `42 49 47 46 74 2b 00 00 00 00 00 07 00 00 00 62` |
| `data/ui/game/screens/playnow/globehubscreen.big` | `GLOBE_HU`, `CONFEDER` | `42 49 47 46 f0 1f 00 00 00 00 00 03 00 00 00 38` |
| `data/ui/game/components/teamselector.big` | `TeamSelector::initRules` | `42 49 47 46 b4 21 00 00 00 00 00 03 00 00 00 38` |

Other `data1.big` entries also contain some repeated labels (`mcConfed` appears in four entries; `GLOBE_HU` in three; `MOVE_CUR` in 46). The strings are not unique callback names. **INFERRED:** These are EA UI binary/container assets rather than standalone Flash/Scaleform movies. As they are not Flash/Scaleform-signature files, the requested conditional check stops here; no claim is made about the guest UI library, cursor bridge, selection callback, or script-side picking.

## Select Team nested-archive / UI library Phase 0 (2026-10-19)

**VERIFIED, read-only:** The three screen/component resources inside `data1.big` are nested `.big` files with the `BIGF` signature. Their structures are not SWF/Scaleform signatures. The associated globe mesh pair is stored as `.msh`, followed immediately by two `.rx3` texture resources. The UI `.big` files contain binary EA UI data with embedded readable identifiers; their exact binary contents are intentionally not copied into notes or git. Header subfields beyond the `BIGF` marker are not decoded here.

**VERIFIED, guest marker search:** Searches of the generated guest source and raw `default.xex` / `fifadllzf.xex` found no meaningful `Scaleform`, `ActionScript`, `ExternalInterface`, `fscommand`, Flash UI, or GFx API strings. The few raw `GFx`/`SWF` byte sequences in `fifadllzf.xex` occur amid high-entropy bytes with no readable string context and are not evidence of a linked library. Generated-source searches likewise found no GFx/Scaleform interface names.

**INFERRED / not established:** The UI files appear to be EA-specific binary UI resources, not standalone Flash/Scaleform movies. Since no SWF/GFX signature or guest GFx bridge was established, the likely UI event mechanism and cursor/stick-to-UI interface cannot be identified from this phase. No conclusion is made about a hidden embedded script VM or its callbacks.

Phase 0 only. No game launch, source/config change, or dynamic-memory tool creation. Phase 1 requires the user-ready screen and the snapshot protocol checklist before any launch.

## Select Team dynamic analysis — nested UI structure and snapshot tool prepared (2026-10-19)

**VERIFIED, structure only:** The inner `BIGF` directories were parsed in memory. `teamselectpanel.big` has seven inner records: five non-empty numeric-labelled records (sizes 5,272; 306; 1,815; 342; 3,124 bytes) plus two zero-length `sg` group markers. `globehubscreen.big` and `teamselector.big` each have two non-empty numeric-labelled records (each paired with a zero-length `sg2` group marker); sizes respectively 4,677/3,374 and 5,581/2,929 bytes. Non-empty payloads begin with RefPack `10 FB` framing. The main record is APT data, the constants record is APT constants; two panel payloads carry an `XPR2` resource marker. The smaller remaining panel record's subtype was not decoded. No EA payload bytes or extracted files were written to notes or git.

**VERIFIED from local archive:** The APT data and constants records are packed EA binary UI resources, not standalone SWF/GFX. **INFERRED:** EA APT is a Flash-movie-derived UI format; the embedded script/constant data can encode UI behaviour, but this pass does not establish whether `MOVE_CUR`, `GLOBE_HU`, or `CONFEDER` are event dispatch names, timeline/script identifiers, or screen/component fields. Raw guest image/generated-source searches yielded no meaningful APT/GFx/Scaleform/ActionScript/ExternalInterface/fscommand bridge strings. Consequently the exact guest-to-APT cursor-input and selection-callback API remains unknown; the few `GFx`/`SWF` byte matches are uncontextual high-entropy bytes and not evidence of Scaleform.

**VERIFIED tool preparation (not run against the game):** Standalone reader created outside the repo at `C:\Users\ramic\AppData\Local\Temp\opencode\team_globe_snapshot.py`; SHA-256 `DC856F0CEF812D0D3F134A1060793438B8C7EDABB0186A670D52622CCD13AD49`. Python help/import and syntax were checked; neither launch nor attach/snapshot occurred. It has explicit `--launch` safety confirmation, supports read-only `--pid` attach with an explicit arena base, uses a global F8 capture hotkey and F9 abort, and discovers a launched run's arena from its fresh log. It scans only committed mapped read/write guest virtual and XEX pages, excluding the GPU window, physical aliases, executable pages, and read-only pages. Caps: 128 MiB/state × six states = 768 MiB raw snapshots; screenshots have an additional 128 MiB aggregate cap; it refuses to start below 2 GiB free on the temp volume. Output is a timestamped folder under the approved temp root. Snapshot reads do not suspend the process; individual reads are concurrent and not atomic. Exact run-time latency and screenshot quality remain unverified. The optional NumPy diff mode decodes BE float32, signed int16 pairs/scalars, and uint32 and writes ranked candidates locally.

**Phase state:** Phase 0 complete. Phase 1 tool prepared but awaiting the user's explicit `go, game is on the Select Team screen` before any launch. No source/config change, build, game launch, git push, or screenshot was made.

## Second-match UI/HUD disappearance - log audit and smallest fix (2026-10-23)

**Scope:** source read-only except one default-value revert; one installed-config line added; no build and no game launch in this pass.

### VERIFIED (logs)

- `C:\Program Files (x86)\FIFA World Cup 2010\logs\worldcup2010_016.log` (14:47:36-15:01:48, 166,585 B) is the run that contains the second qualification match. The `[gpu]` tag appears **5 times**, all startup: adapter, D3D12 feature list, `Translated 207 shaders`, `Created 178 graphics pipelines`, `SetInterruptCallback`. There is **no** texture, render-target, EDRAM, resolve, descriptor or allocation line anywhere in the file. At `log_level = "info"` in `worldcup2010.toml:39` the GPU resource path is therefore **uninstrumented**, so log silence is not evidence that the path is correct.
- The second scene load is visible only as asset I/O at 15:00:17 (`hairlod_0.rx3`, `banner_1337_-842150451.rx3`, `volumetric_fx_239_1.rx3` -> `0xc000000f`), i.e. the same three optional-miss entries already seen at 14:48:35 and 14:49:23 for the first load. No asset that is unique to the HUD fails to open.
- No `Failed to create a texture descriptor` / bindless-exhaustion line, no `Failed to dump host render targets for resolve`, no device-removed line. The 512 `[error][core] ROUND30 exception` lines are the known per-thread diagnostic noise (first 8 per thread, then every 1024th).

### VERIFIED (code paths that can differ between match 1 and match 2)

- EDRAM ownership is **not** reset between matches: `pipeline/render_target/cache.cpp:336-341` sets a single all-empty range at init and `:343-357` only re-creates it on shutdown. So match 2 starts with tiles owned by match 1's render targets, match 1 starts with an empty map.
- A transfer is only requested when the previous owner is non-empty: `pipeline/render_target/cache.cpp:1216` (`!transfer_source.IsEmpty() && transfer_source != dest` in `WouldOwnershipChangeRequireTransfers`). Consequently an under-claimed EDRAM extent is **harmless with an empty map and destructive with a populated one** - the exact asymmetry of "first match fine, second match broken".
- The claimed extent is `min(render target height, EstimateMaxY(...))` (`pipeline/render_target/cache.cpp:569-575`), and it becomes `rt_lengths_tiles` (`:653-658`), which is what `ChangeOwnership` (`:689`) and `PerformTransfersAndResolveClears` (`d3d12/render_target_cache.cpp:3798`) act on.
- `EstimateMaxY` only consults the vertex shader when `PA_CL_CLIP_CNTL.clip_disable` **and** the scissor is at the 8192 sentinel (`util/draw_extent_estimator.cpp:273-299`), i.e. for screen-space / full-screen style draws - typical for UI compositing, not for the clipped 3D pass.
- The local tree had that estimate **forced on globally**: `util/draw_extent_estimator.cpp:27` was `true` where upstream is `false` (see `patches/rexglue-local-changes.patch`, old hunk `-...false` / `+...true`). The same option is set explicitly per title in `D:\FWC10\fifa-street-pc-port\Installer\payload\Game\fifastreet.toml:3`, so the global flip was redundant for FIFA Street and unvalidated for this title.
- `TryResolveCopyDirectly` is not a skipped resolve: it preflights, then returns `DumpRenderTargets(...)` (`d3d12/render_target_cache.cpp:5538-5582`), and the copy shader still runs from `edram_buffer_` (`:1225-1330`). So "direct resolve silently drops the resolve" is **excluded** by code reading.

### CHANGE

1. `ReXGlue/src/graphics/util/draw_extent_estimator.cpp:27` - default reverted to `false` (upstream). FIFA Street keeps the behaviour through its own toml.
2. `patches/rexglue-local-changes.patch` and `patches/rexglue-v0.3-local.patch` - the now no-op `draw_extent_estimator.cpp` section removed so a fresh `git apply` (README:42) reproduces the corrected default instead of re-introducing the flip.
3. `C:\Program Files (x86)\FIFA World Cup 2010\worldcup2010.toml` - `execute_unclipped_draw_vs_on_cpu = false` added (line 38). `REXCVAR_GET` is evaluated per draw (`draw_extent_estimator.cpp:275`), and the string is present in the installed `rexgpu-xenos.dll`, so the A/B needs **no rebuild**.

### NOT ESTABLISHED

- That the HUD/loading overlay actually emits clip-disabled, 8192-scissor draws. If it does not, the fix is inert and the symptom belongs to the texture-refresh or ownership-transfer hypotheses. The next discriminators are `log_texture_uploads = true` (`d3d12/texture_cache.cpp:39-40`, plus `texture_diagnostic_directory`, `:42-43`) and, if needed, `direct_host_resolve = false`.
- No HUD texture identity (base/format/dimension) has been observed at runtime for this title.
## Second-match HUD: the toml was never applied, plus instrumentation (2026-10-23, later)

**Scope:** instrumentation only (counters and log lines); one installed DLL replaced; installed toml repaired; no rendering behaviour changed; no game launch in this pass.

### VERIFIED: the installed `worldcup2010.toml` did not parse, so no value in it was ever applied

- The file on disk at `C:\Program Files (x86)\FIFA World Cup 2010\worldcup2010.toml` had mtime `2026-10-23 15:33:32`; `logs\worldcup2010_017.log` (the run the user described) starts `15:33:42.994` and the file has not been modified since. So the content on disk now is the content that run used.
- That content contained `texture_diagnostic_directory = "C:\Users\ramic\AppData\Local\Temp\opencode\fwc10-tex"`. In TOML a basic string treats `\U` as an escape; `\U` needs 8 hex digits, and `s` follows. `toml::parse_file` therefore throws. Confirmed with the same toml++ build the runtime uses (`ReXGlue\thirdparty\tomlplusplus\toml.hpp`): `PARSE ERROR: Error while parsing unicode scalar sequence: expected hex digit, saw 's'`.
- `LoadConfig` catches that and only logs `REXLOG_ERROR("Failed to parse config ...")` (`ReXGlue\src\core\cvar.cpp:649-651`), but it runs at `ReXGlue\src\ui\rex_app.cpp:159`, **before** `rex::InitLogging` at `:175`, so the error never reaches any log file. Every key in the file was silently ignored.
- Consistent evidence in `worldcup2010_017.log`: `log_level = "debug"` was in that file, yet the log has **0** `[debug]` lines and **0** `Texture diagnostic:` lines, and `Loaded config: ...` (`rex_app.cpp:184`, `REXLOG_DEBUG`) is absent. The run therefore used compiled defaults for every cvar.
- Consequence: `execute_unclipped_draw_vs_on_cpu = false` never took effect in that run (it was not even present in the file at that point), so "H1 was not sufficient" is **not** supported by that run - H1 was never tested.
- Install location is not redirected: every binary in the folder is x64 (`machine=0x8664`), so UAC/WOW64 file virtualisation does not apply; `C:\Users\ramic\AppData\Local\VirtualStore\Program Files (x86)\FIFA World Cup 2010` does not exist; the config path is `GetExecutableFolder() / (GetName() + ".toml")` (`rex_app.cpp:107`, `:147`) and `Launcher.ps1:524` sets `WorkingDirectory` to the exe folder. Recommendation: keep the install in `C:\Program Files (x86)\FIFA World Cup 2010`; there is no evidence of redirection, and the new startup line proves the paths at runtime.

### Instrumentation added (observation only)

New header `ReXGlue\include\rex\graphics\hud_diagnostics.h` with monotonic counters and three cvars defined in `ReXGlue\src\graphics\graphics_system.cpp:67-74`:

- `hud_diagnostics` (default false) - one cumulative `HUDDIAG frame=...` summary line per `hud_diagnostics_interval` frames.
- `hud_diagnostics_draws` (default false) - per-draw state for UI-like draws and EDRAM extent truncation, sampled once per interval.
- `hud_diagnostics_interval` (default 60).

Hook points (all increments, no control flow changed):

- Frame boundary: `d3d12\command_processor.cpp:1944` calls `diag::FrameBoundary`, which also prints the one-time startup block (`graphics_system.cpp:765-804`): host exe path, the GPU DLL path, `exe_dir`, every `*.toml` next to the exe with size and mtime, and for 12 cvars the effective value and the `Source` that wrote it (`config` / `command-line` / `environment` / `runtime` / `default`). This is printed even when `hud_diagnostics` is off, so a dead config is always visible.
- Draw drops: viz-query predication `command_processor.cpp:1637`, packet-level failures `:1621`; in `d3d12\command_processor.cpp` no-VS `:2344`, RT update failure `:2425`, plus zero-pitch, no-effect, primitive failure, zero vertices and async-pipeline-pending counters; issued draws `:2830`.
- Draw classification: `d3d12\command_processor.cpp:2520-2564` counts clip-disabled, viewport-transform-off, depth-test, depth-write, null-pixel-shader and "UI-like" draws (`clip_disable && index_count <= 4096`), and logs index count, primitive type, clip flag, depth state, viewport, scissor, interpolator mask and shader modification hashes.
- EDRAM extent: `pipeline\render_target\cache.cpp:578-596` accumulates `height_used` vs the full render target height per draw and logs every truncation with both values, pitch, MSAA and `clip_disable`.
- Ownership/transfers: `pipeline\render_target\cache.cpp:716-729` (transfer rectangles requested per draw) and `:1289` (ownership changes); executed dispatches at `d3d12\render_target_cache.cpp:3811`.
- Resolves: `d3d12\render_target_cache.cpp:1168` (calls), failures at `:1177` and `:1225`, direct/fallback at `:1209-1212`; EDRAM copies at `d3d12\command_processor.cpp:2985`.
- Textures: invalidation `pipeline\texture\cache.cpp:742` (`Texture::WatchCallback`), uploads/failures in `CommitPreparedTextureLoad` (`:453` / `:443`), evictions in `CompletedSubmissionUpdated` (`:302`), `ClearCache` calls (`:254`); descriptor failures and bindless exhaustion at `d3d12\texture_cache.cpp:2303-2304` and `:2329`.
- Render target creation counter in `RenderTargetCache::GetOrCreateRenderTarget`.

### Build and install

- Built `rexgpu-xenos:Release` from the current tree (clang 18, Ninja, `out\build\win-amd64\build-Release.ninja`), 0 errors. `rex_app.cpp` is compiled into the game **exe**, not `rexruntime.dll` (verified: the string `Graphics presentation setup failed` exists only in `FIFA World Cup 2010.exe`), so the startup line lives in the GPU DLL instead of requiring a game rebuild.
- Installed DLL: `C:\Program Files (x86)\FIFA World Cup 2010\rexgpu-xenos.dll`, 3,007,488 B, 2026-10-23 16:15:50. Backup of the previous DLL: `D:\FWC10\backups\rexgpu-xenos-20261023-prehuddiag.dll`.
- The build also contains the `draw_extent_estimator.cpp:27` default revert (`false`), so this run tests H1 with the cvar actually at `false` for the first time.
- The installed toml was rewritten as valid TOML (`41 top-level keys`, verified with `tomlcheck`): the path is now a literal string (`'C:\...'`), `log_texture_uploads = false`, `log_level = "info"`, `execute_unclipped_draw_vs_on_cpu = false`, `hud_diagnostics = true`, `hud_diagnostics_draws = true`, `hud_diagnostics_interval = 120`.

### Ranked hypotheses and the counter that discriminates each

1. Config never applied (now excluded by the startup line: `source=config`).
2. Viz-query predication drops the HUD draws before the backend: `viz` rate rises while `draws` falls.
3. EDRAM extent truncation plus ownership transfer between the 3D and UI passes: `trunc`, `ext_permille` (< 1000), `xfer` / `xfer_disp` change rate at the transition.
4. Resolve side: `resfail` > 0, or `fb` (direct-resolve fallback) rate changes.
5. Stale HUD atlas: `inval` grows without a matching `up` growth, or `upfail` rises.
6. Descriptor exhaustion: `desc fail` / `exhaust` > 0.
7. Other backend drops: `novs`, `zpitch`, `nofx`, `noprim`, `rtfail`, `pending`, `primfail`, `failed_total`.

**NOT ESTABLISHED:** which of 2-7 is active; that the loading-screen UI and the in-match HUD share a draw path; the actual EDRAM extent used by HUD draws.
### Run 021-024: the HUD is drawn, and the draw state is identical to a working match

- **The HUD passes are present in the broken state.** Run 023 (`dump=120`) compares match 1 @frame 36480 with match 2 @frame 44880: `ps=7ABDFEFB`, texture `0/08024802/0F0D9086/001FE3FF` (1024x256 at `0x0F0D9000`), `blend=07060706`, `cctl=8700000C`, `cmask=F`, `rtD=2D0/1`, `pitch=1280`, `vp=sc=(0,0,1280,720)` - all identical. So nothing is being dropped or culled on the emulator side.
- **The resolve chain is identical too**: 30 `HUDDIAG copy` records with the same addresses, lengths and order in both frames, frontbuffer copy (`13AB8000`, 3768320 B) last.
- **The pause menu in the broken match renders perfectly** (screenshot 2026-10-24 13:48, `wc_match3_pause.png`): panel, flags, button highlight, text, EA/FIFA branding - from the *same* `7ABDFEFB` shader and the *same* `0x0F0D9000` texture. The atlas, blend state, RT path and shader translation are therefore healthy; only the HUD's own geometry can differ.
- **The failure is cumulative, not "match 2".** It appeared in match 2 on the 13:26 DLL and in match 3 on the 14:31 DLL (diagnostics-only changes), so the trigger is per-session state, not a match index.
- **Pass histogram overflow invalidated earlier presence/absence claims**: with the key including the sampled texture, 128 slots (`graphics_system.cpp:694`) overflowed by 25-47 entries in *every* match frame. Raised to 512; runs 020 and 023 predate this and their "missing pass" observations must not be used.
- **`HUDDIAG texdata` was reading 4 bytes/pixel on an 8-bit linear texture** (1 MB instead of 256 KB), so its monotonically growing `nz` was an artefact of reading past the texture. It is not evidence about atlas content and should be re-derived if needed.

### Open: per-draw geometry, and the vertex upload path

- Remaining inputs that can differ for an otherwise identical pass: vertex buffers/index buffer, shader constants. Constants are uploaded per draw through `UpdateBindings` and work for the pause menu, so geometry is the lead.
- `D3D12CommandProcessor::IssueDraw` calls `SharedMemory::RequestRange` for a vertex buffer **only when its address or size changed** (`d3d12\command_processor.cpp:2695-2698`); the range is an upload/copy (`include\rex\graphics\shared_memory.h:77-81`), refreshed when guest pages are marked dirty. A missed invalidation keeps a stale copy on the host.
- Instrumentation added: `HUDDIAG hudvtx vf= ic= addr= size= hashed= nz= hash=` (once per dump frame for `ps=7ABDFEFB`), hashing up to 512 bytes of each used guest vertex buffer via `constant_register_map().vertex_fetch_bitmap`.

---

## Online Multiplayer Architecture & Reconnaissance (Phase A)
See master documentation in `D:\FWC10\NOTES.md` for full audit tables, UI architecture analysis, XAM/XNet call sites, and multiplayer implementation design.

