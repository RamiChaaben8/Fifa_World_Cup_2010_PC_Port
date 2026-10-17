# 2010 FIFA World Cup South Africa - PC Port Notes - ARCHIVE (Rounds 7-11)

Extracted verbatim from `NOTES.md` on 2026-10-17 (Round 12) when the one-page
*Current State* summary was added at the top of the live file. The live file keeps the
stage-by-stage history, the offline hunts, the current state, Round 12, and the
"Files Intentionally Unchanged" table; everything from Round 7 through Round 11 lives here.

Rounds are in original order (7 -> 11). In-file corrections made by later rounds are kept as
they were, so this is the audit trail rather than a cleaned-up retelling.

Backup of the whole project at extraction time: `D:\FWC10\_backups\` (see `LAST_BACKUP.txt`).

---

## Round 7 (2026-10-17): item 1 (profile/sign-in) answered, item 2 (hardware watchpoint) measured

No rebuild, **0 s codegen** — this round used source reading, one config-free debugger tool, and
offline static reads only. Game data, overrides, Xenia install and Xenia config all untouched.

### Item 1 — profile / "signed in" state: our runtime already reports slot 0 signed in (VERIFIED)

Source (quoted this round):

* `ReXGlue/include/rex/system/xam/user_profile.h`
  * `uint32_t signin_state() const { return 1; }`  — unconditional ("signed in locally")
  * `uint32_t type() const { return 1 | 2; }`      — unconditional (local|online = 3)
* `ReXGlue/src/system/xam/user_profile.cpp` ctor: `xuid_ = 0xB13EBABEBABEBABE; name_ = "User";`
  and a full default settings table (the ctor comment records the deliberate 58410A1F XUID-mask choice).
* `ReXGlue/src/kernel/xam/xam_user.cpp`
  * `XamUserGetSigninState_entry`  → returns `user_profile()->signin_state()` = **1** for slot 0
  * `XamUserGetSigninInfo_entry`   → writes xuid/name and hard-codes `info->signin_state = 2`
    (comment: "FIFA Street: report Xbox Live sign-in")
  * `XamUserGetXUID_entry`         → `X_E_SUCCESS` + that xuid for slot 0 with type_mask 1/2/3/7

Config surface (VERIFIED — full `REXCVAR_DEFINE_*` inventory of the runtime was enumerated):
there is **no** cvar/TOML key for profile, sign-in, XUID or name (the only profile-ish keys are
`user_language`, `user_country`, `license_mask`, plus path keys `game_data_root`, `user_data_root`,
`update_data_root`, `cache_root`). Config is loaded from `exe_dir/<exe name>.toml`
(i.e. `dist\Output\worldcup2010.toml`, currently absent) and from `--name=value` CLI args, so a
config-only lever *does* exist — it just has nothing profile-related to set.

Xenia side (read from `xenia.log`, read-only):

* `ProfileManager: Found 0 Profiles` — Xenia's own profile *list* is empty too.
* `User test (XUID: E03000007F393D8F) doesn't have profile GPD!`
* `~ContentPackage: Closing package: User_E03000007F393D8F ... Device mounted: Yes`

**Conclusion (VERIFIED):** our runtime already reports slot 0 as signed in; the item-1 conditional
("if our runtime reports *not signed in*, change it") is **not met**, so there was no change to make
and no boot was spent on it. Profile *sign-in state* therefore cannot explain the AV. Xenia's real
advantage in this area is the *configured XUID plus a mounted profile/save content device*, which we
were explicitly instructed not to copy. Remaining measurable difference on this axis (for the
record, not acted on): our log shows `XamContentCreateEnumerator: added 0 items` (x2 at 26.146,
x2 at 28.790) and `C:\Users\<user>\Documents\worldcup2010` contains only `cache/` — i.e. no content.

### Item 2 — hardware watchpoint run: method works, and the +0x64 field is written by **nobody**

**Tooling.** This machine has **no debugger front-end** (`Windows Kits\10\Debuggers\x64` contains
only `dbgcore.dll`/`dbghelp.dll`/`srcsrv.dll`/`symsrv.dll`; no `cdb.exe`, no `windbg.exe`, no
x64dbg; VS 18 Community's `devenv.exe` exists but is GUI-only). So the watchpoint was implemented
directly: `C:\Users\<user>\AppData\Local\Temp\opencode\w32_watch.py`, `w32_watch2.py`,
`w32_watch3.py`, `w32_probe.py` — Python + `kernel32` debug API, launching the port with
`DEBUG_ONLY_THIS_PROCESS` and setting `DR0..DR3`/`DR7` per thread.

**Guest-created threads: VERIFIED handled.** Windows' debug registers are **per-thread**, so a
WinDbg-style `ba w4` only covers the thread it is issued on. This tool arms every thread from its
`CREATE_THREAD_DEBUG_EVENT`, and the result was **74/74, 76/76 threads armed, none missed** (the
count grows because the guest keeps spawning threads during the run). Post-arming read-back
verification in the final run: *"all threads carry DR1"*.

**Run fidelity: VERIFIED.** Under the debugger the build behaves as in the plain boots:
`EXIT_PROCESS exitcode=0xC0000005`, ~11-27 s, 106 × `0x406D1388` (MS_VC_EXCEPTION = the guest
thread-naming calls, matching Xenia's `RtlRaiseException(406D1388)` lines), and the guest AV
reproduced at **host `0x10006C6B8`** (guest `0x6C6B8`) — byte-identical to the runtime log.

**Address model — VERIFIED, and it corrects my earlier recipe.**

1. `C:\FWC10B\fwc10stage4\WorldCup2010Rex\generated\fifadllzf_xex\worldcup2010_pch.h:120-137`:
   ```c
   #define REX_PHYS_HOST_OFFSET(addr) (((u32)(addr) >= 0xE0000000u) ? 0x1000u : 0u)
   #define REX_LOAD_U32(x)  __builtin_bswap32(*(volatile u32*)(base + (u32)(x) + REX_PHYS_HOST_OFFSET(x)))
   #define REX_STORE_U32(x,y) (*(volatile u32*)(base + (u32)(x) + REX_PHYS_HOST_OFFSET(x)) = __builtin_bswap32(y))
   ```
   with `base` = guest virtual membase `0x1_0000_0000`. So **guest G ↔ host `0x1_0000_0000 + G`**
   (no offset for G < 0xE0000000). The `0x103A4648C` (mirror) and `0x283A4648C` (physical+full)
   candidates are **not committed**; `0x203A4648C` (physical+masked) reads 0. So the `+base` rule
   is the one in force.
2. **Byte order:** guest memory holds big-endian bytes, and the accessors `bswap32`. A debugger's
   `ReadProcessMemory` therefore sees *raw big-endian* bytes; the guest-visible value is
   `bswap32(raw)`. My first reading `0xD0573CBF` is really **`0xBF3C57D0`** (4-byte aligned — a
   real pointer). This endianness slip is why the first field watch found nothing.
3. **`0x83A4648C` is the pointer *variable*, not the object** (guest `.data` global). The object is
   heap-allocated (196 bytes) and the pointer is published there. So the field is at
   `*(0x83A4648C) + 0x64` — a *dynamic* address per boot. **My stored recipe ("watch
   `0x1_83A464F0`") was wrong and is withdrawn.**
4. The publish store exists exactly as the offline model said — `worldcup2010_recomp.317.cpp`,
   `DEFINE_REX_FUNC(sub_82C6AFC8)`: `lis r11,-31836` → `r11 = 0x83A40000`, `stw r3,25740(r11)` →
   guest **0x83A4648C**, called from `worldcup2010_recomp.41.cpp:100` (init `0x8265EF40`). An
   earlier note in this round that "the generated code has no store to `+25740`" was a truncated-grep
   artifact and is **corrected**.

**Measured hits (final run, `w32_watch3.py`, byte-order-correct):**

| # | DR | writer (module+RVA) | guest value | meaning |
|---|---|---|---|---|
| 1 | DR0 ptr-var | `0x7FFD7F71E6C3` (system DLL, ntdll memset range) | `0x00000000` | arena/bss zeroing |
| 2 | DR0 ptr-var | `0x7FFD7F71DD06` (system DLL) | `0x00000000` | arena/bss zeroing |
| 3 | DR0 ptr-var | `0x7FFC..D334` *(module unresolved — see gap below)* | **`0xBF3C57D0`** | **the game's publish store: singleton created, aligned 196-byte heap object** |
| — | DR1 field | **none, ever** | field stays `0x00000000` | **no thread writes `+0x64`** |

* Phase 2 armed `DR1 = object+0x64` (guest `0xBF3C5834`, host `0x1BF3C5834`) on every known thread as
  soon as the pointer was published, with read-back verification ("all threads carry DR1"), and then
  watched for the whole remaining life of the process (11-27 s) while the guest spawned more threads
  (each also armed at creation). **`field_hits = 0`.** The field is still `0x00000000` at the crash.
* The object is **not** an uninitialised shell: dumped at crash time its first `0x40` bytes are
  populated with live guest pointers (`+0x08 0xBF8EE0DC`, `+0x0C 0xBF8D1018`, `+0x10 0xBF8EE0E0`,
  `+0x14 0xBF5598C0`, `+0x18 0xBF8EA048`, `+0x1C 0xBF3DDE30`) whereas at publish time they were all
  zero. So the object is allocated, owned and actively used — only `+0x64` is ever left 0.
* Because the ctor (`0x82C50EF0`, zero-fill through `+0xC0` including `+0x64`) runs *before* the
  publish store, arming after publish cannot see the ctor's own zero write; but the field is
  measured 0 immediately after publish and never written again, so the ctor's zero is the *only*
  write to that field that ever happens in our build.

**Verdict (VERIFIED by measurement, not inference):** in our build the singleton object **is**
created and used, and **nothing writes `singleton+0x64` at any point** → the "initialiser" of that
field is **never reached**. This supersedes both earlier hypotheses ("created but +0x64 skipped by
a taken/not-taken branch" is still possible, but "CREATE never ran" and "host/kernel call fills it"
are now much less likely, since any guest `stw` to that address would have been caught).

**Gaps / honest caveats in this round:**

* The `modules=0` in the final trace means `CreateToolhelp32Snapshot` at `CREATE_PROCESS` returned no
  modules (process not yet settled), so writer RVAs could not be attributed to module *names*;
  hit #3's rip `0x7FFC..D334` is *inferred* to be `worldcup2010_fifadllzf.dll` (it is in the same
  module as the crash-time rip `0x7FFC..CE86` that executed guest code). Cheap fix for next time:
  snapshot modules on the first hit rather than at `CREATE_PROCESS`.
* Hardware breakpoints are per-thread and *can* be clobbered by any code that itself writes `DR7`;
  read-back verification passed at arming time, but clobbering *during* the run is not excluded.
  A cheap cross-check exists: also watch three object fields that we know *do* get written
  (`+0x08`, `+0x0C`, `+0x10`) with the remaining `DR1..DR3` slots — if those fire and `+0x64` never
  does, the "nobody writes it" conclusion is airtight (and it tells us *which* function writes the
  neighbouring fields, i.e. the likely home of the missing store).
* `w32_probe.py`'s `VirtualQueryEx` arena dump ran after process exit and printed nothing — it needs
  to run while the process is alive. Not needed for any conclusion above.

### Corrections to earlier notes in this file

| Earlier claim | Status |
|---|---|
| "Watch address `0x83A4648C+0x64` = host `0x1_83A464F0`" (item 1 recipe) | **Wrong** — `0x83A4648C` is the pointer *variable*; the object is dynamic |
| "Creator ran first (singleton non-null)" — inferred from faulting at `0x6C6B8` not `0x64` | Inference was unsound (any non-zero X with `[X+0x64]==0` faults the same way); but it happens to be **true** — now measured directly |
| "The generated code has no `stw` to `+25740`" (this round, interim) | **Wrong** (truncated grep); the store is at `worldcup2010_recomp.317.cpp:11569` |
| "Nothing in this build writes the field" (hypothesis) | **Now measured**: `field_hits = 0` across all threads for the whole run |
| Endianness of debugger reads of guest memory | **New constraint: always `bswap32`** |

### Next (proposed, awaiting go-ahead)

1. **Cheapest + most decisive:** re-run `w32_watch3.py` with `DR0=obj+0x64`, `DR1=obj+0x08`,
   `DR2=obj+0x0C`, `DR3=obj+0x10` and module names resolved on the first hit. If `+0x08/+0x0C/+0x10`
   fire from function *F* and `+0x64` never does, then *F* (or its callee) is where the missing store
   lives and the divergence is a not-taken branch inside a function that demonstrably runs.
2. **Item 4 (still open, 20-min box):** enumerate the ~32 untagged `stw rX,0x64(rB)` sites and their
   base registers, and every `bctr`/`bcctr` in the 17 chain functions — now with a concrete target:
   find the store whose base is this 196-byte object type and see whether it is reached from
   `0x8265EF40`'s subtree.
3. **Item 3 (needs explicit approval before launching):** Xenia `log_level = 3` on a **copy** of the
   install (plus optionally `log_high_frequency_kernel_calls = true`,
   `[Kernel] log_string_format_kernel_calls = true`) to capture what Xenia does between thread 35
   naming itself and the point where our run AVs.

---

## Round 8 (2026-10-17): item 1 - neighbour-field watch, timestamps, guest function names

> **[Round 9 correction - thread identity]** "thread 35 names itself" is wrong: the `0x406D1388` at
> `t=4.090` is raised by the **FEThread** (guest id 26) to name thread 35. The AV is on the **FEThread**,
> i.e. on the *creator*, not on the worker. Everything else in this round stands (the tid used by the
> tool is the authoritative event tid; only the human label was wrong).

**User correction accepted:** the Round-7 watch proves nothing wrote `+0x64` *before the AV*, not that
nothing ever does. The run ends ~2 ms after thread 35 names itself, so "the initialiser is never reached"
is **not** established below either. Everything in this round is bounded by that window.

### Tool: `w32_item1b.py` - pre-armed four-slot hardware watch (why the design changed)

The first attempt ("watch the pointer variable, then re-arm on the object once known") caught **0 hits**:
the object's neighbour fields are populated within ~5 ms of the publish, faster than the ~60 ms it takes
to re-arm ~65 threads. The object's heap address is **deterministic across boots** (`0xBF3C57D0` in six
consecutive runs), so all four slots are now armed at process creation and every new thread inherits them.

| slot | address | width | watches |
|---|---|---|---|
| DR0 | `obj+0x64` | 4 B write | the field that is 0 and crashes the game |
| DR1 | `obj+0x08` | 8 B write | covers `+0x08..+0x0F` (incl. `+0x0C`) |
| DR2 | `obj+0x10` | 8 B write | covers `+0x10..+0x17` |
| DR3 | `0x1_83A4648C` | 4 B write | the singleton pointer variable itself (publish store) |

`DR7 = 0xD99D0055`. `DR7` bits 8/9/10 (`LE`/`GE`/reserved) read back as 1, so the guardian compares with
`~0x700` masked out - the first version reported 278 "clobbers" that were purely this bit, i.e. **no real
clobber** (see below).

Guardian: every 50 ms it re-reads `DR0..DR3` and `DR7` on a rotating batch of 16 threads, re-arms on any
mismatch and logs it. Over the run: **864 thread checks, 34 re-arm failures - every one of them on a
thread that had already exited** (`EXIT_THREAD_DEBUG_EVENT` seen for the same tid; a dead thread cannot
write memory), and **0 clobbers on live threads**. So "the four watchpoints were present on every live
thread for the whole run" is now measured, not assumed.

### Hit table (representative run, `item1e_out.txt`; 16 hits, all on tid 20696)

| t (s) | writer (guest function, from module's own `PPCFuncMappings[]`) | slot | value read after store | meaning |
|---|---|---|---|---|
| 1.043 | `?` (VCRUNTIME140, direct guest syscall stub) | ptr-var | 0 | arena/bss zeroing of the pointer variable |
| 1.160 | `?` (VCRUNTIME140) | ptr-var | 0 | ditto |
| 3.588 | `sub_82821808+0x478` | +0x08 | `0xCDCDCDCD` | game-side allocator fill pattern |
| 3.589 | `sub_82821808+0x4CE` | +0x10 | `0xCDCDCDCD` | ditto |
| 3.590 | `sub_82821808+0x5E9` | +0x64 | `0x00000000` | ditto (block header clear) |
| 3.590 | `sub_82821808+0xA01` | +0x64 | `0xCDCDCDCD` | ditto (fill) |
| 3.590 | `sub_82C50EF0+0xA0` | +0x08 | 0 | **constructor zero-fill** |
| 3.590 | `sub_82C50EF0+0xC6` | +0x08 | 0 | ctor |
| 3.591 | `sub_82C50EF0+0xE4` / `+0x102` | +0x10 | 0 | ctor |
| **3.591** | **`sub_82C50EF0+0x35D`** | **+0x64** | **0** | **ctor - last write to `+0x64` in the whole run** |
| **3.591** | **`sub_82C6AFC8+0xF4`** | **ptr-var** | **`0xBF3C57D0`** | **publish store (creator)** |
| 3.595 | `sub_82CA1138+0xEC7` | +0x08 | `0xBF8EE0DC` | initialiser populates the object |
| 3.596 | `sub_82CA1138+0x1391` | +0x08 | `0xBF8EE0DC` | ditto |
| 3.597 | `sub_82CA1138+0x1464` | +0x10 | `0xBF8EE0E0` | ditto |
| 4.088 | `sub_82C6B358+0x197` | +0x10 | `0xBF8EE0E0` | second `+0x10` writer, 2.7 ms before the AV |
| 4.090 | (thread 35 `SetThreadName(35, rw45_pkg_factory_seg)`) | - | - | runtime log + `0x406D1388` in the debugger |
| **4.091** | **`sub_82CBD7E0+0x236`** | - | **AV** | read of guest `0x6C6B8`, `+0x64 == 0` at that instant |

### What this establishes (VERIFIED)

1. **The complete write history of `+0x64` for this run is three stores, all at `t=3.590/3.591`**
   (allocator fill `0xCD`, then the ctor's 0). Nothing writes it after the publish.
2. **Between publish (`t=3.591`) and AV (`t=4.091`) - a 500 ms window - no thread writes `+0x64`**,
   with the 4-byte write watchpoint verified present on every live thread throughout. Bounded claim:
   *nothing writes it before the AV*; the process dies 1.7 ms after thread 35 names itself.
3. **The init subtree does run and does populate the object**: `sub_82CA1138` writes `+0x08`/`+0x10`
   immediately after the publish. `sub_82CA1138` is exactly the function `0x8265EF40` calls right after
   `sub_82C50840(sub_82C501D0())`, so the caller-of-the-creator chain executes - it just never touches
   `+0x64`. This kills the "CREATE never ran" and "the function is unreached" hypotheses.
4. **The neighbouring fields have exactly two populating writers**: `sub_82CA1138` (right after publish)
   and `sub_82C6B358` (2.7 ms before the AV). Both are candidate homes for the missing store; neither
   writes `+0x64`.
5. **The AV is the first read of `+0x64` by this consumer**: the field went from "written by the ctor at
   `t=3.591`" to "read as 0 at `t=4.091`" with no intervening write, i.e. the crashing reader executes
   *before* anything populates the field.

### Method caveats (honest)

* Guest-function attribution uses the module's own `PPCFuncMappings[]` (`{size_t guest; PPCFunc* host}`,
  87,182 entries, found by content in the module's `.data` at runtime), with "containing function = last
  entry whose host address is <= rip". Sorting that table by host address **does not** preserve guest
  order (reported `False`), so containment is a heuristic. It is nonetheless **cross-validated for the
  decisive rows**: `sub_82C50EF0` = the ctor, `sub_82C6AFC8` = the creator, `sub_82CBD7E0` = the known
  crash-chain root - all three match the independent static addresses from Round 7, and the store offsets
  are plausible. The remaining attributions (`sub_82821808`, `sub_82CA1138`, `sub_82C6B358`) are
  *inferred from the same table*, not independently verified.
* The object address is deterministic in six runs but that is an observed regularity, not a guarantee;
  the tool also re-arms if the publish value ever differs from the pre-armed address.

### Item 2 - freeze experiment: the AV is not a scheduling race (SUPERSEDED)

> **[Round 9 correction - thread identity]** The thread frozen here, and the thread that carries the AV,
> is **not** `rw45_pkg_factory_seg` (thread 35) but the **FEThread** (guest id 26) - the thread that
> *creates, names and resumes* thread 35. See "Thread-identity correction" in Round 9 below. The
> measurements in this item are unchanged; the wording "thread 35" below should read "FEThread
> (creator)". The freeze therefore held the thread that had to *do* the resuming, which is why this
> experiment cannot discriminate the race hypothesis (the worker is never resumed during the hold).

`w32_item2.py` = item-1 tool + freeze: on the `0x406D1388` that names thread 35, `SuspendThread`
immediately (the crashing read is then still ~1.7 ms in the thread's future), keep pumping debug events,
`ResumeThread` after N ms.

| freeze | other threads during freeze | writes to `+0x64` during freeze | guest AV after resume |
|---|---|---|---|
| 50 ms | (100 ms log interval; resumed at +51 ms) | none | +1.7 ms / +2.4 ms |
| 500 ms | +179 debug events, 0 new thread names | none (`+0x64` still 0) | +2.1 ms / +2.9 ms |
| 2000 ms | +852 debug events, 0 new thread names | none (`+0x64` still 0) | +1.3 ms / +1.8 ms |

* The AV is **deterministic**: as soon as thread 35 runs its start routine it reads `obj+0x64 == 0` and
  faults. Delaying it by 50 / 500 / 2000 ms changes nothing about the outcome.
* **No thread writes `+0x64`** (nor `+0x08`/`+0x10`/the pointer variable) while it is frozen: giving the
  rest of the process two extra seconds and ~850 debug events does not produce the missing initialiser.
  So "the writer merely runs later" is **not supported**.
* During the freeze no new threads are created and the object does not change further - the rest of the
  process is quiescent in init terms, i.e. it is waiting on thread 35's own work.
* Residual caveat this experiment **cannot** exclude: the writer may sit *after* the crashing read
  **inside thread 35's own start routine** (read-then-init / a lazy-init whose init branch never runs).
  Freezing cannot observe that region.

### Item 3 - what `r31` is in the chain that stores to `r31+0x64` (VERIFIED statically)

The store: `worldcup2010_recomp.186.cpp:69-70`, inside `DEFINE_REX_FUNC(sub_826546E0)` (guest `0x826546E0`):

```cpp
// stw r31,100(r31)
REX_STORE_U32(ctx.r31.u32 + 100, ctx.r31.u32);
```

* `sub_826546E0` has **exactly one caller**: init `sub_8265EF40` (`recomp.41.cpp:164-168`,
  `mr r4,r31; bl 0x826546e0`).
* Inside it `r31 = r3` at entry (`recomp.186.cpp:17-18`) → `r31` is the function's `this`.
* In the caller, `r31` = return of `sub_826908B8(0x82304360)` (`recomp.41.cpp:154-160`), while `r3` at the
  call = whatever `sub_82654FD8` leaves in `r3` (`recomp.41.cpp:161-166`).
* `sub_826908B8(p)` = `sub_826907A8(*(0x839AA350), p)` (`recomp.4.cpp:357-368`) - a registry lookup -
  and `0x82304360` is the ASCII string **`"main"`** (dumped from the XEX image; neighbours:
  `0x82304330` = `FE::Common::Manager::Instance()->Initialize`, `0x8230435C` = `fe`, then `data/db/`,
  `DBALLOC_MAX_LEAGUES`, ..., `fifa_ng_db`).
* `sub_82654FD8` (`recomp.206.cpp:3-57`) is a run-once guard; **both** exit paths converge on
  `loc_8265501C: mr r3,r31` with `r31 = 0x83988F84` (static: `r11 = 0x83990000`, `-28796 = -0x707C`).
* Hence `this` = **0x83988F84, a static address in the guest image's own data**, and the store writes
  `0x83988F84` into **0x83988FE8** (= `this+0x64`). In the XEX image both locations are zero-initialised
  (`fifadllzf.dec.bin` offsets `0x1688F84` / `0x1688FE8`), consistent with an init-time self-pointer store.
* **Answer: it does not point at our object.** Our singleton is the heap object `0xBF3C57D0` (published by
  `sub_82C6AFC8+0xF4`); this store targets a static image object, so it can never have been the missing
  writer - which is exactly why the four-slot watch on the heap object's field never fired for it.
* Bonus (semantics): the store is a *self*-pointer, `this->0x64 = this`, followed by
  `arg->vtable[6](arg, this+44)` (`recomp.186.cpp:71-80`) - "give the object a back-pointer, then register
  it with the object named `main`". The `+0x64` being read at the crash is a different field of a different
  class (a pointer to a big object owning an array at `+0x6C6B8`).

### Item 4 - how our runtime starts guest threads vs Xenia's config (VERIFIED from source, quoted)

| aspect | our runtime (ReXGlue source) | Xenia (config only; no source in `D:\FWC10\xenia`) |
|---|---|---|
| host thread creation | `params.stack_size = 16_MiB; params.create_suspended = true;` (`xthread.cpp:432-435`) -> `CreateThread(NULL, stack_size, ThreadStartRoutine, start_data, params.create_suspended ? CREATE_SUSPENDED : 0, NULL)` (`threading_win.cpp:454-466`); start routine sets TLS/name then `Execute()` (`xthread.cpp:435-460`) | n/a |
| resume | `if ((creation_params_.creation_flags & X_CREATE_SUSPENDED) == 0) thread_->Resume();` (`xthread.cpp:483-486`) -> `ResumeThread` (`threading_win.cpp:406-418`); guest-suspended threads stay asleep until `NtResumeThread` / `KeResumeThread` (`xboxkrnl_threading.cpp:178-209`) | — |
| suspend bookkeeping | `suspend_count = (flags & X_CREATE_SUSPENDED) ? 1 : 0` (`xthread.cpp:211`) | — |
| priority | creation flags: `if (flags & 0x60) set_priority(flags & 0x20 ? 1 : 0)` (`xthread.cpp:473-475`); `XThread::SetPriority` maps guest increments and applies only `if (!ignore_thread_priorities)` (`xthread.cpp:837-859`) | `ignore_thread_priorities = false` -> honours game-set priorities |
| cvar defaults | `ignore_thread_affinities = true` (`xthread.cpp:43`), `ignore_thread_priorities = true` (`xthread.cpp:40`) | `ignore_thread_affinities = true`, `ignore_thread_priorities = false` |
| affinity | `SetActiveCpu()` always updates guest KTHREAD/PCR `current_cpu`, and pins the host thread via `set_affinity_mask(1 << cpu_index)` **only if** `logical_processor_count() >= 6 && !ignore_thread_affinities` (`xthread.cpp:880-903`); `KeSetAffinityThread` -> `SetAffinity` -> same path (`xthread.cpp:861-863`) | same cvar semantics |
| this machine | 12 logical CPUs -> the `>= 6` branch is live; `dist\Output` has **no `.toml`** -> defaults -> **no pinning** | config value `true` |

=> **No thread-start divergence that could explain the AV.** Neither runtime delays a runnable guest
thread beyond the guest's own request; both default to ignoring affinities; the single difference
(`ignore_thread_priorities`: ours `true`, Xenia `false`) affects host scheduling priority only. This
agrees with item 2's measurement that the AV is not a scheduling race.

### Corrections to Round 7 in this file

| Round-7 claim | Status after Round 8 |
|---|---|
| "nothing writes `singleton+0x64`; the initialiser is never reached" | **Overstated.** Corrected to: *nothing writes it before the AV*; the initialiser is not reached *within the 2 ms of thread-35 life that we observe* |
| "the object is all zeros at publish; neighbours get written later" | **Refined**: neighbours `+0x08`/`+0x10` are written at `t=3.595-3.597` (by `sub_82CA1138`), `+0x0C` sits inside DR1's 8-byte window; `+0x64` is written only by the ctor |
| "DR7/DR0 read-back verification passed at arming time; clobbering during the run is not excluded" | **Now excluded** for live threads (864 checks, 0 live clobbers); the only failures were threads already dead |
| "writer rip could not be attributed to a module name" | **Fixed** (`CreateToolhelp32Snapshot` refreshed until the game DLL appears; table located at runtime) |
| Round-7 item 4: "the ~32 untagged `stw rX,0x64` sites / `bctr` sites are the lead" | **One such site identified and closed** (item 3 below): `sub_826546E0`'s `stw r31,100(r31)` writes to a *static image object* `0x83988F84+0x64`, not to the singleton |

---

## Round 9 (2026-10-17): item 5 - Xenia level-3 log of a copy (data captured), the thread-identity correction, and the thread create/name machinery

### Item 5 - Xenia `log_level = 3` on a **copy** of the install: DONE

All four approval conditions were met and checked:

| condition | outcome (VERIFIED) |
|---|---|
| (a) grep the copy's config for absolute paths and repoint any into `D:\FWC10\xenia` before launching | none present: `log_file = ""` and `storage_root = ""`, so the exe dir *is* the storage root; no `\` paths to break Xenia's TOML parser |
| (a) minimal edit | the copy's config differs from the read-only one by **exactly one byte**: offset `55324`, `log_level = 2` -> `log_level = 3`; both files `65968` bytes (byte-exact diff verified) |
| (b) after the run, `D:\FWC10\xenia` has no new/changed files | **verified**: all 17 files identical in size *and* mtime |
| (c) ISO untouched, ~60 s, clean close | ISO `2010 World Cup.iso` still `5995827200` bytes, `2026-10-16 06:08:15`; the copy ran ~60 s and exited cleanly (exit code 0) |
| (d) compare Xenia's thread-35 startup with ours | done below, with an explicit verified/inferred table |

Artefacts: `C:\FWC10B\xenia_log3\` (copy of the install + `xenia.log`, 11.5 MB / 197,511 lines),
`xenia_log3\xenia-canary.config.toml` (1-byte diff), `launch_xenia_log3.ps1`, `xenia_before.txt` /
`xenia_after.txt` (the before/after file inventory).

### Xenia's thread-35 startup window (`xenia.log` lines 17870-17945), quoted

```
d> F8000330 ExCreateThread(708EEFA0(00000000), 00004000, 8398CF00(00000000), 8282FD10, 828360B8, 40103E40, 00000001)
d> F8000330 ExCreateThread Active: Thread Initially Suspended,
d> F8000330 Added handle:F80003BC for class xe::kernel::XObject
i> F8000330 XThreadF80003BC (23) Stack: 70760000-70770000
i> F8000330 RtlRaiseException(708EEF70(406D1388))
d> F8000330 SetThreadName(35, rw45_pkg_factory_seg)
d> F8000330 ObReferenceObjectByHandle(F80003BC, 30000000, 708EF030(FFFFFFFF))
d> F8000330 KeSetBasePriorityThread(301E5010, 00000001)
d> F8000330 ObDereferenceObject(301E5010, ContextArg)
d> F8000330 ObReferenceObjectByHandle(F80003BC, 30000000, 708EF030(301E5010))
d> F8000330 KeSetAffinityThread(301E5010, 00000010, 708EF034(83AEA830))
d> F8000330 ObDereferenceObject(301E5010, ContextArg)
d> F8000330 NtResumeThread(F80003BC, 708EF040(00000000))
K> F80003BC XThread::Execute thid 35 (handle=F80003BC, 'rw45_pkg_factory_seg (F80003BC)', native=000027A4)
d> F80003BC KeTlsSetValue(00000001, 40103E40)
d> F80003BC ObReferenceObjectByHandle(F8000068, 30000000, 7076FC80(3001A010))
d> F80003BC ObDereferenceObject(3001A010, ContextArg)
d> F80003BC KeTlsSetValue(00000002, F80003BC)
...
d> F8000330 NetDll_XNetGetTitleXnAddr(00000001, B5B5C2D4)
d> F8000330 KeQuerySystemTime(708EF4A0(708EF520B56CF3C8), ContextArg)   (x ~9)
```

| # | claim | status |
|---|---|---|
| 1 | thread 35 is created with `flags = 1` (CREATE_SUSPENDED), `startup = 0x8282FD10`, `start_address = 0x828360B8`, `start_context = 0x40103E40` | **VERIFIED** (Xenia log + our recompiled call site, identical numbers) |
| 2 | the **creator** (FEThread) names it (`RtlRaiseException(406D1388)` -> `SetThreadName(35, ...)`), sets base priority 1, sets affinity `0x10`, then `NtResumeThread`s it | **VERIFIED** (line order above) |
| 3 | thread 35's guest body then executes: `KeTlsSetValue(1, 40103E40)` (its own context goes into TLS slot 1), `ObReferenceObjectByHandle`, `KeTlsSetValue(2, handle)` | **VERIFIED for Xenia**; *not comparable* on our side (our runtime logs no TLS calls and no "thread executing" marker) |
| 4 | after the resume the FEThread makes **no kernel call** until `NetDll_XNetGetTitleXnAddr` (then a run of `KeQuerySystemTime`) | **VERIFIED** (gap in the quoted window) - so the `singleton+0x64` read, if it happens in the FEThread, sits inside that silent, wait-free guest window |
| 5 | therefore in Xenia the read cannot have been ordered after a kernel wait; it is ordered only by guest code | **INFERRED** (guest-side ordering is invisible to the level-3 log) |
| 6 | the `+0x64` writer is a *task* run by a worker rather than the worker's prologue | **INFERRED** - see the machinery below |

### Thread-identity correction - the AV is on the **FEThread** (guest id 26), not on thread 35 (VERIFIED)

Three independent, same-run facts:

1. *Our runtime log alone* (last run): `[t12560] SetThreadName(35, rw45_pkg_factory_seg)` at
   `16:08:34.456`, then `[t12560] Unhandled guest access violation ... on thread 0xF8000350` at
   `16:08:34.458` - same host thread `t12560`, and the handle in the AV line is the FEThread's.
2. *Same-run debugger mapping*: the provisional name `XThread3110 (F8000350)` is raised by host tid
   `0x3110` = `12560`, and that same tid self-names `FEThread`.
3. *Item-1 run*: the AV tid `27932` is the tid that self-named `FEThread` (handle `F8000350`); the worker
   (handle `F80003D0`) self-named on tid `26568`. Guest ids match Xenia exactly (`FEThread` = 26,
   `rw45_pkg_factory_seg` = 35).

Handles vary run to run; earlier `F800034C` / `F8000358` readings came from *other* runs, so **cross-run
handle comparisons are invalid** - that is what produced the wrong attribution in Round 7/8.

Consequences:

* Item 2 (freeze) held **the thread that had to do the resuming**, so the worker was never resumed during
  the hold - the experiment cannot discriminate the race hypothesis. It remains valid only as "the AV is
  deterministic, and the rest of the process does not write `+0x64` while the creator is held".
* Item 1's "crash ~1.7 ms after thread 35 is named" is really "~2 ms after the **creator** names the
  worker" (README-level wording, not a measurement change).
* The fault chain (`sub_82CBD7E0` -> `sub_82C501D0` -> `sub_832BF128` -> `lwzx r28,r3,r11`) runs on the
  FEThread - i.e. in the *frame/update* code (`sub_82CA1B50`), which is exactly what the FEThread does
  after it resumes its workers. **INFERRED**: the creator resumes the worker and then, ~2 ms later, wants
  the factory that the worker was supposed to build.

### New this round: the thread create / name machinery, decoded statically (VERIFIED from generated code)

| function | role | key lines |
|---|---|---|
| `sub_8282FD10` (recomp.67:3153) | XapiThreadStartup trampoline: `r30 = r3`, `r29 = r4`, then `mtctr r30` / `bctrl` with `r3 = r29` -> calls `start_address(start_context)` | verified |
| `sub_828360B8` (recomp.300:3457) | the game's common bootstrap: TLS get/set, writes the current guest thread id, then calls the dispatcher | verified |
| `sub_82836038` (recomp.286:3101) | **dispatcher**: `sub_8283E4F0()` -> object, then `r11 = *(obj+0x54)`, `r3 = *(obj+0x58)`, `mtctr`/`bctrl` -> calls `entry(arg)`; `sub_8319B838` runs after the body returns | verified |
| `sub_82836148` (recomp.227:3304) | allocates the **196-byte (0xC4) context**, `*(ctx+0x54) = entry`, `*(ctx+0x58) = arg`, `*(ctx+4) = -1`, creates with bootstrap `0x828360B8` | verified |
| `sub_8267CB90` / `sub_8267CF28` (recomp.82:230 / recomp.204:217) | the two "start a worker" helpers: entry hardcoded `sub_8267CAD8` / `sub_8267CE78`; name = `*(descriptor+0x14)`; priority = `*(descriptor+8)`; affinity = `*(descriptor+0x0C)` | verified |
| `sub_8267BA40` (recomp.260:189) | the guest's SetThreadName: copies the name into `context+0x24` then raises `0x406D1388` with `X_THREADNAME_INFO{0x1000, name, thread_id, 0}` | verified |

Context layout (the 196-byte object that is also `start_context`): `+0x00` handle, `+0x04` guest thread
id, `+0x24` 32-byte name copy, `+0x54` entry, `+0x58` arg.

* `"rw45_pkg_factory_seg"` lives at `0x8259BB08` in `fifadllzf.xex`'s `.rdata` (VERIFIED by searching the
  decompressed image). **No pointer to it exists anywhere in that image**, so the descriptor that carries
  it is built at *runtime* (heap) - which is why the name/entry table cannot be recovered statically, and
  why the literal never showed up in a code grep either (the name is loaded out of the descriptor).
* Consequence (INFERRED): thread 35's body is one of the two hardcoded worker entries
  (`sub_8267CAD8` / `sub_8267CE78`) - a generic RenderWare async-load worker loop that pulls **tasks** off
  a queue. So the writer of `singleton+0x64` is most plausibly a *task* (or a later step of the same
  machinery), not the worker's prologue.

### Tool semantics, pinned down (VERIFIED from runtime source) - why the debugger's "name" events exist

Two *different* `0x406D1388` paths, easily confused:

1. **Guest-initiated (the game naming a thread)** - the guest calls `RtlRaiseException` with
   `X_THREADNAME_INFO{0x1000, name_ptr, thread_id, 0}`; our runtime's guest-exception handler
   (`RtlRaiseException_entry` -> `HandleSetThreadName`, `xboxkrnl_debug.cpp:41-80,129-134`) resolves the
   thread by id and calls `thread->set_name(name)`, logging `SetThreadName(<guest id>, <name>)`. Running
   *on the raising (creator) thread* - which is why the log line's tid is the FEThread's.
2. **Runtime-initiated (debugger marker)** - `set_thread_name_impl` -> `raise_thread_name_exception`
   (`threading_win.cpp:50-64`) raises a *host* exception `0x406D1388` carrying `{0x1000, name, ...}` when
   `IsDebuggerPresent()`. This is what `w32_item1b.py` / `w32_item2.py` hook. At thread creation the
   runtime first sets the provisional name `XThread{:04X}` (`xthread.cpp:470`), where `{:04X}` is the
   **new thread's host tid** - so the tool's "provisional name" event is how the host tid of a brand-new
   guest thread is obtained (the authoritative id; the human-readable guest label comes later, and keys on
   the *creator's* tid).

### Data-file parity, re-checked this round (VERIFIED) - the last competing lead is retracted

Our log's last lines before the AV show failed lookups (`t28872`: `d:\data\sceneassets\genheadtex.big`,
`t28092`: `d:\data\ice\icenislist.txt`, both `0xc000000f`). Checked directly:

* `dist\GameData` contains **exactly** the ISO's 43 entries (`data\launcher`, `data\loc`, `data\movies`,
  `data\ui`, `data\ant.cbac`, `data0..data8.bh/.big`, `default.xex`, `fifadllzf.xex`, `nxeart`,
  `$SystemUpdate`).
* `data\sceneassets` and `data\ice` are **absent from the ISO itself** - so those lookups cannot succeed
  on either runtime, and they are **not** a port-side divergence (INFERRED that Xenia fails them too; not
  directly observed).

### Corrections to Round 7 / Round 8 in this file

| earlier claim | status after Round 9 |
|---|---|
| "the AV happens on thread 35 / `rw45_pkg_factory_seg`" | **WRONG.** The AV is on the **FEThread** (guest id 26), the thread that creates, names and resumes thread 35. Marked inline at the Round 8 item-1 and item-2 headings |
| "item 2 shows the AV is not a scheduling race" | **Weaker than claimed**: the freeze held the *creator*, so the worker was never resumed during the hold. The race hypothesis for the `+0x64` read is still open |
| "Xenia's thread-35 window contains a kernel wait" | **Retracted**: no kernel call between `NtResumeThread` and `NetDll_XNetGetTitleXnAddr` |
| "content enumeration / missing data explains the divergence" | **Retracted again** (data parity above, and Xenia logs the same "added 0 items") |

### Next (proposed, awaiting go-ahead) - one no-rebuild, no-override run each, <= 20 min each

Both use the existing item-1 tool (four hardware slots pre-armed, `DR0 = obj+0x64`) and only add a
`SuspendThread`/`ResumeThread` policy. Neither rebuilds, overrides or re-stages anything.

* **(A) "hold the worker, let the creator run"** - at the **worker's** provisional-name event (i.e. after
  the runtime's own resume), `OpenThread`+`SuspendThread` the worker's host tid and hold it for N ms while
  watching `+0x64`, then resume it. *If* `+0x64` changes during the hold, the worker (or something it
  unblocks) is the writer and our AV is a premature read.
* **(B) "hold the creator, start the worker ourselves"** - at the `0x406D1388` that names thread 35,
  `SuspendThread` the **creator** (as item 2 did), then `ResumeThread` the **worker** ourselves (the
  runtime created it suspended; the creator's own `NtResumeThread` has not run yet) and watch `+0x64` for
  N ms (50 / 500 / 2000). *If* `+0x64` goes non-zero during the hold, the worker is the writer and the
  creator's `+2 ms` read is a race; *if* it stays `0` for 2 s, the writer is elsewhere (the
  "skipped/earlier init" branch), which is the competing hypothesis.

Interpretation caveat, stated honestly: in (B) the creator is held, so the outcome "`+0x64` stays 0"
cannot by itself separate "the worker is not the writer" from "the creator is the writer".

---

## Round 10 (2026-10-17): item 4 answered; the item-3 "B" runs done (and corrected); the worker is a RenderWare pkg-segment factory and is **not** the `+0x64` writer

Tool for this round: `w32_item3b.py` (copy of the item-1/item-3 four-slot watch; adds: worker
identification by **handle match against the `XThread<hex> (F8000xxx)` provisional marker**, arming the
worker's own DRs before its resume, a nested debug-event pump, per-sample worker context/native-stack
sweep, RIP -> owning-module-export naming, `GetThreadTimes` CPU, and a "post" sampler).  Modes:
`baseline` (item-1 behaviour) / `B` (hold the creator at the `0x406D1388` that names thread 35, start the
worker ourselves).  No rebuild, no override, no re-staged data, and Xenia was **not** launched this round
(only its saved level-3 log was read).

### Item 4 - guest priority `1` / affinity `0x10` / `NtResumeThread` in our runtime, quoted (VERIFIED from source)

* `XThread::SetPriority` (`src/system/xthread.cpp:837-859`) writes the **guest** field
  `kthread->priority = clamp(increment, 0, 31)` = `1` for this thread, maps the host class as
  `increment <= 0x11 -> kNormal`, and then **gates the host call**:
  `if (!REXCVAR_GET(ignore_thread_priorities)) thread_->set_priority(target_priority);`.
  The cvar default is `true` (`REXCVAR_DEFINE_BOOL(ignore_thread_priorities, true, "Kernel", ...)`, `:40`)
  -> **the host priority is not applied in our build**.
* `XThread::SetAffinity` (`:861-863`) = `SetActiveCpu(GetFakeCpuNumber(affinity))`.
  `GetFakeCpuNumber(0x10)` (`:187-204`) is `7 - rex::lzcnt(0x10)` = `7 - 3` = **4** (it asserts
  `1 << cpu_number == proc_mask`, so the guest's `0x10` means "logical processor 4"); `SetActiveCpu` (`:880`)
  stores that cpu id into the guest `KTHREAD`/PCR and pins the **host** thread only when
  `logical_processor_count() >= 6 && !ignore_thread_affinities`; `ignore_thread_affinities` default is
  `true` (`:43`) -> **no host pinning** (Xenia's config also has `true`, so this is not a divergence).
* `NtResumeThread_entry` (`src/kernel/xboxkrnl/xboxkrnl_threading.cpp:178-195`) -> `XThread::Resume`
  (`xthread.cpp:930-940`): `guest_kthread->suspend_count.fetch_sub(1)` (out-param = **previous** count),
  then `thread_->Resume(&unused_host) ? X_STATUS_SUCCESS : X_STATUS_UNSUCCESSFUL`; `Thread::Resume`
  (`src/core/threading_win.cpp:406-418`) is only `ResumeThread(handle_)` (returns `false` on `UINT_MAX`).
  **No yield, no join, no ordering guarantee** - whether the resumed thread runs before the caller
  continues is host scheduling (INFERRED).  Observed this round: it does run *concurrently* (the worker
  self-applies its name ~1 ms before the creator's AV), so a race is possible in our runtime.

### Item 1 baseline (unmodified tool) - DONE before the B runs

`w32_item3_baseline.py` (copy of `w32_item1b.py`, only the output path changed) on the fresh build:
naming event for `rw45_pkg_factory_seg (F80003D0)` raised by tid 1444 at `t=3.990`; AV on the **same**
tid 1444 in `sub_82CBD7E0+0x236` at `t=3.991` = **naming +1.2 ms**, `+0x64 = 0`; the singleton's init
writes happened at `t=3.524-3.528` on a *different* tid (25884); the module's own
`PPCFuncMappings[]` was found at `0x7FFCA1493000` with **87182** entries ("guest order preserved when
sorted by host: False"); the DR guardian ran 880 checks / 87 clobbers / **0 on live threads**; 78
first-chance AVs plus 2 at the crash address.

### Item 3 (experiment B): what actually happened

**(a) The original B design (50 / 500 / 2000 ms) is non-discriminating - the worker never ran.**
Worker identified correctly each time from the `XThread<hex> (handle)` marker (host tids 28848 / 6124 /
23324, varying per run).  During the entire hold (3 / 41 / 165 samples), every single sample showed
`RIP = ntdll.dll!RtlUserThreadStart+0x0` with `RSP` near the top of a **fresh, untouched stack** (only the
first 0x400 bytes readable, all zero) - i.e. the thread had executed **not one instruction**.
(The first classifier's "blocked in a host wait" label was an artefact: the module is `ntdll` because the
entry point lives there; the corrected classifier reports "NOT RUNNING - parked at thread entry".)
Reason (VERIFIED behaviourally, OS rule INFERRED): Windows holds a newly created thread until its
`CREATE_THREAD_DEBUG_EVENT` is continued, and a debugger cannot receive new events while an earlier event
is still pending - and we were parked *inside* the `0x406D1388` handler precisely to hold the creator.
So the worker could not start until we released the creator; the AV then followed the release by
**+12.8 / +6.0 / +12.2 ms** (AV - naming: +63.3 / +506.5 / +2012.6 ms).  `+0x64` was never written.

**(b) Corrected B: continue the naming event while the creator stays frozen by its suspend count.**
Only then can the worker's `CREATE_THREAD` event be delivered (~25 ms later), be continued, and the
worker actually run.  Two runs (2000 / 5000 ms hold):

| hold | worker tid | first sample | worker during the hold | `+0x64` | AV |
|---|---|---|---|---|---|
| 2000 ms | 13560 | +0.1 ms, at thread entry | ~15.6 ms CPU then parked (rest of the hold) | never written | release +5.9 ms |
| 5000 ms | 25872 | +0.1 ms, at thread entry | ~15.6 ms CPU then parked (rest of the hold) | never written | release +5.9 ms |

The worker's own DRs were armed **before** it was resumed (`arming DRs=True`), so a write by it would
have been caught.  Its sampled state during the hold, quoted from the trace:

```
SAMPLE hold 2   t=  4.015 (+   35.3 ms after worker resume) prev_suspend=0 state=blocked in a host wait
     rip=ntdll.dll!ZwWaitForSingleObject+0x14 rax=0x4 rcx=0xF28 rdx=0x0 r8=0x0
     frames: KERNELBASE.dll+0x1BE9F <- MSVCP140.dll+0x17EAB <- rexruntime.dll+0xA3A90 <-
             rexruntime.dll+0x2506B6 <- rexruntime.dll+0x25DCA2 <- rexruntime.dll+0x2605C3 <-
             rexruntime.dll+0x42E2B8 <- rexruntime.dll+0x25D651 <- rexruntime.dll+0x43A87E <-
             sub_8282DD28+0x19A <- ... <- sub_8267B358+0x4BC <- sub_837018D0+0x2CE <- sub_8267CAD8+0x252
```

Guest frames (from the module's own `PPCFuncMappings[]`), innermost first:
`sub_8267CAD8+0x252` (worker body) <- `sub_837018D0+0x2CE` <- `sub_8267B358+0x4BC` <-
`sub_8282DD28+0x19A` (**the guest wait helper**, which calls `KeWaitForSingleObject`; the runtime
implements that wait through `MSVCP140`/`KERNELBASE` - i.e. a `std::condition_variable`), handle
`0xF28`, `RDX = 0` -> no timeout.  So: **the worker burns ~15.6 ms of guest CPU (its startup) and then
blocks forever on its own queue because no request ever arrives** - and `+0x64` stays `0`.

### Xenia's worker is a RenderWare segment factory (VERIFIED from the saved level-3 log)

In Xenia the same guest thread is 35, handle `F80003BC` (handles differ per run), native tid `0x27A4`.
Its own log lines (99 of them) are almost entirely **one continuous loop of
`RtlInitializeCriticalSection`** over a contiguous region with stride `0x60`:

```
17889: K> F80003BC XThread::Execute thid 35 (handle=F80003BC, 'rw45_pkg_factory_seg (F80003BC)', native=000027A4)
17890: d> F80003BC KeTlsSetValue(00000001, 40103E40)
17891: d> F80003BC ObReferenceObjectByHandle(F8000068, ...)
17893: d> F80003BC KeTlsSetValue(00000002, F80003BC)
17898: d> F80003BC RtlInitializeCriticalSection(B5415110)
17985..18144: d> F80003BC RtlInitializeCriticalSection(B5415170) ... (B5415FB0, then B53FE050 ... B53F94D0)
115501: d> F80003BC RtlInitializeCriticalSection(B53F93B0)          <- still looping at the log's tail
```

`rw45_pkg_factory_seg` = **RenderWare 4.5 package segment factory**: a long-lived, request-serving
producer of ~96-byte segment objects that each own a critical section.  It is *not* a one-shot init.
Our runtime does not log `RtlInitializeCriticalSection` (checked: 0 matches in our log), so the same loop
cannot be counted on our side; our worker is simply parked on its queue because the creator crashes
~6 ms after the resume (no further requests).

### What this settles, and what it does not

* VERIFIED: the AV is gated on the **creator**, not on the worker's progress.  Every hold length
  (50 / 500 / 2000 / 2000-corrected / 5000-corrected ms) gives an AV at release +6..13 ms, regardless of
  whether the worker has executed nothing or has finished its startup.
* VERIFIED: `+0x64` is written by **nothing** in any run (baseline, 3 old-B, 2 corrected-B).  The complete
  write history of that address remains the 3 item-1 stores - `0`, `0xCDCDCDCD`, `0` (ctor) - all at/just
  before the singleton's publish, i.e. **before** the read; a valid pointer is never stored.
* INFERRED (now the leading branch): the assignment of a valid pointer must be a code path that runs in
  Xenia before the creator's read and **never executes** in our build (watched address, all threads, all
  runs) - i.e. the "skipped earlier init" branch rather than "runs with a wrong value".
* INFERRED (narrower race variant that is still open): the factory serves *requests*; the creator may
  issue the request that fills `+0x64` only *after* it resumes the worker, and may reach the read before
  the factory has served it.  Corrected B cannot exclude this, because the creator was frozen and so could
  never issue a request.

### Corrections to Round 9 in this file

| Round 9 wording | status after Round 10 |
|---|---|
| "during the hold the worker is blocked in a wait (ntdll)" | **WRONG for the original B design**: the worker had not started at all (`RIP` pinned at the thread entry, untouched stack). It is only in the corrected B that the worker really runs and ends up in a `KeWaitForSingleObject` |
| "item 2/B show the `+0x64` race is closed" | **Only partly**: the worker's *startup* is exonerated; a race on the factory *serving a request* is still open |
| "the worker does nothing / has nothing to do" | **Refined**: in Xenia the worker is a continuous RenderWare segment factory (thousands of `RtlInitializeCriticalSection` calls over the whole run); in our run it finishes its startup and waits, because the game dies ~6 ms after the resume |

### Next (proposed, awaiting go-ahead; no rebuild / no override / no re-staged data)

1. **(no run) Locate the intended writer statically.**  In the generated sources, enumerate every store to
   offset `+0x64` inside the singleton's *populate* paths (`sub_82821808`, `sub_82C6B358`, `sub_82C50EF0`,
   `sub_82C6AFC8`) and identify the store(s) that never executed at runtime (the DR watch proves which did).
   The never-executed store is the intended assignment and the branch guarding it is the missing
   condition.  This is the cheapest way to turn "skipped init" from a hypothesis into a located path.
2. **(one run, needs approval) Throttle the creator instead of freezing it.**  From the naming event
   onward, duty-cycle `SuspendThread`/`ResumeThread` the creator (e.g. 1 ms on / 1 ms off for a few
   seconds) so it advances at roughly half speed while the factory runs at full speed.  If the crash
   disappears and DR0 fires on the worker, the writer is the factory serving a creator request (the
   narrower race).  If the crash persists, the missing init is on the creator's own path.  No guest state
   or code is modified - only host scheduling.

---

## Round 11 (2026-10-17): items 1+2 (throttle runs, vtable slot) and items 3+4 (static dig, sibling-port search)

Approved work: option 3 with the four additions, time-boxed to ~1 hour. No rebuild, no override, no
re-staged data, no Xenia launch. Two tool changes were needed first: `Runner.slots`/`dr7_val` are now
derived from the slot set (so the offset-0 run needs no second tool), and a new `T` mode duty-cycles
the creator with `SuspendThread`/`ResumeThread`.

### Tool change: slots and DR7 computed from the slot table

| config | slots | DR7 |
|---|---|---|
| default (all previous rounds) | `+0x64`(4B) `+0x08`(8B) `+0x10`(8B) `ptr-var`(4B) | `0x0D99D0055` (unchanged) |
| `W32_VTABLE=1` | `+0x64`(4B) `+0x00`(4B) `+0x08`(8B) `ptr-var`(4B) | `0xD9DD0055` |

The default value reproduces the hard-coded constant exactly, which validates the formula.

### Item 1 answer - throttling the creator does **not** close the crash, and the worker is still not the writer

| run | duty | NAMED | guest AV | AV-naming | AV on worker? | duty cycles | `+0x64` |
|---|---|---|---|---|---|---|---|
| `T 1 1 3000` | 1 ms on / 1 ms off | t=3.99x | yes | **+48.7 ms** | no | 3 | never written |
| `T 5 1 3000` | 5 ms on / 1 ms off | t=4.094 | yes | **+37.0 ms** | `worker=False` | 2 | never written |
| baseline, unthrottled | - | t=3.841 | yes | +1.6 ms | - | - | never written |

Worker identity in the 5/1 run: tid 9840, handle `F80003D0`, matched from the provisional marker
`XThread2670 (F80003D0)`; DR arming at the naming event succeeded. Worker samples:

    SAMPLE thr  1    +0.3 ms   prev_suspend=1  state=suspended (still CREATE_SUSPENDED)
    SAMPLE thr  2   +28.3 ms   prev_suspend=0  state=blocked in a host wait/syscall (ntdll.dll)
    SAMPLE thr-end 3 +40.8 ms (just after the AV) state=blocked in a host wait/syscall (ntdll.dll)

The worker was therefore resumed by the creator, completed its startup and parked in its wait
**28.3 ms before the creator's fatal read**, and `+0x64` stayed 0 throughout. In the 1/1 run the
worker was observed *running guest code* (`sub_836FEFE0+0x8E1`) at +45.0 ms, i.e. also mid-startup,
and the AV came 3.7 ms later. (Caution: the 1/1 numbers are from the console output; both throttle
runs used `total_ms=3000` and so wrote the same trace filename, and the 5/1 run overwrote the 1/1
trace.)

Conclusions (verified): the throttle works as a scheduling brake - the AV moved from +1.6 ms to
+37/+49 ms - so host scheduling alone is not what fixes this; the worker's startup, its wait and its
whole life up to the AV are exonerated again, now with the creator *running concurrently* rather than
frozen; the crash is on the creator's own path, ~2-3 ms of guest work after the resume.

Design flaw to fix before repeating: the throttle loop breaks as soon as the AV is detected, so only
2-3 of the intended ~3000 ms of duty cycles ran. These runs test "creator at ~50% speed for ~40 ms",
not "creator at 1/100 speed for 3 s". The duty that would actually give the factory a head start is
the opposite one: **short on / long off** (1 ms on / 100 ms off), so the creator issues its request
and the worker then gets ~100 ms of wall time to service it before the creator's next 1 ms step.

### Item 2 answer - the object's offset 0 is written, and it is not a vtable slot

`W32_VTABLE=1` run (DR0 `+0x64`, DR1 `+0x00`, DR2 `+0x08`, DR3 `ptr-var`, DR7 `0xD9DD0055`):
`+0x00` had 4 hits, all before the AV (t=3.334-3.336).

| t | tid | site | value | meaning |
|---|---|---|---|---|
| 3.334 | 1476 | `sub_82689490+0x1C91` | `0xBF3C57C8` | `obj - 8` |
| 3.335 | 1476 | `sub_82689D08+0x1A12` | `0xBF3C57C8` | `obj - 8` |
| 3.335 | 1476 | `sub_82821808+0x478` | `0xCDCDCDCD` | memset poison (see item 3) |
| 3.336 | 1476 | `sub_82C50EF0+0x5C` | `0` | ctor |

So offset 0 is a **back-pointer to `obj-8`** (the allocation/header word), written by two different
functions before the poison and ctor passes - not a vtable. Every field the game writes on this
object except `+0x64` gets a real value: `+0x00 = obj-8`, `+0x08 = 0xBF8EE0DC`, `+0x0C = 0xBF8D1018`
(the single 8-byte store at `+0x08` covers both), `+0x10 = 0xBF8EE0E0`, and the pointer variable =
the object itself. AV still at +1.6 ms with `+0x64 = 0`.

### Item 3 answer - the static dig (bctr inventory, and who writes what)

All paths under `C:\FWC10B\fwc10stage4\WorldCup2010Rex\generated\fifadllzf_xex` (read-only).

| function | generated | bctr sites | stores to `+0x00/+0x08/+0x0C/+0x10/+0x64` in its own body |
|---|---|---|---|
| `sub_82CA1138` (populate) | `recomp.246.cpp:11757..13347` (1591 lines) | **0** | 31 stores, incl. `stw r3,8(r31)`, `stw r3,12(r31)`, `stw r11,16(r31)` - **no store to `+0x64`** |
| `sub_82821808` | `recomp.18.cpp:2934..3204` (271 lines) | **0** | none in the body - it is `memset` |
| `sub_82C50EF0` (ctor) | `recomp.183.cpp:11333..11446` (114 lines) | **0** | `stw r11,{0,8,12,16,100}(r3)` with r11=0 |
| `sub_82C6B358` | `recomp.134.cpp:11954..12023` (70 lines) | **0** | none - it allocates 520 bytes, calls `sub_829A5720(static_base, *(obj+0xAC))` and stores the result at `+0x14` |
| `sub_82C50840` | `recomp.70.cpp:11251..11258` (8 lines) | **0** | none - it is `*(u32*)(r3+172) = r4` |
| `sub_82C6AFC8` (publish) | `recomp.317.cpp:11538..11590` (53 lines) | **0** | none in the body |
| `sub_82689490` | `recomp.274.cpp:308..1220` (913 lines) | 4 | writes `+0x08`/`+0x0C` pairs |
| `sub_82689D08` | `recomp.178.cpp:317..1050` (734 lines) | 4 | writes `+0x00` (twice), `+0x08`/`+0x0C` pairs |
| `sub_82CBD7E0` (fault site) | `recomp.322.cpp:12356..12992` (637 lines) | 12 | `stw r29,8(r31)`, `stb r25,0(r11)` |
| `sub_82C501D0` (get singleton) | `recomp.79.cpp:11475..11484` (10 lines) | **0** | none - it is `return *(0x83A4648C)` |
| `sub_832BF128` | `recomp.268.cpp:23168..23175` (8 lines) | **0** | none - it is `return *(u32*)(r3+100)` |

**What is new versus the earlier enumeration (rounds 7-10):**

1. `sub_82821808` is **`memset`**. Its generated body is a textbook `memset` (count<16 fast path, then
   `stbu r10,1(r11)`), which is why the DR hits attributed to it (`+0x478`, `+0x4CE`, `+0x5E9`,
   `+0xA01`) are *stores inside memset*, not field initialisations: the `0xCDCDCDCD` writes into
   `+0x00`, `+0x08`, `+0x10`, `+0x64` are one `memset(obj, 0xCD, n)` (the object is deliberately
   poisoned) and the two 0-writes are a zeroing memset. All earlier statements of the form
   "`sub_82821808` writes `+0x64` (0 / 0xCDCDCDCD)" must be read as "a memset call did".
2. The function that writes the singleton's real pointers is **`sub_82CA1138`**, not named in any
   earlier round. It is a master initialiser (1591 generated lines, dozens of `bl` sub-inits) called
   exactly once, by the top-level starter `sub_8265EF40`, *after* the publish, and it writes `+0x08`,
   `+0x0C`, `+0x10` with real heap pointers. It contains **no store to `+0x64` at all**: `+0x64` is
   not a skipped branch of the populate function - the populate function has no such store.
3. `sub_82C50840` (the function specifically asked about) is a one-instruction **field setter**,
   `*(u32*)(r3+172) = r4` (i.e. `+0xAC`), called from `sub_8265EF40` between the publish and the
   populate. The same address range holds a family of one-instruction accessors (in `recomp.70`,
   `.33`, `.79`, `.101`, `.102`, `.185`, `.196`, `.252`, `.267`, `.294`, `.319`): getters for
   `+0x00`, `+0x10`, `+0x14`, `+0x28`, `+0x34`, `+0x48`, `+0x74`, `+0x78`, `+0x7C`, `+0x84`, and the
   `+0xAC` setter. **There is no accessor for `+0x64` in that family.**
4. Exhaustive scan for a one-instruction `+0x64` setter (`stw r4,100(r3); blr`) across the whole
   module: exactly one exists, **`sub_82BDB2F8`** (`recomp.56.cpp:10789`), and it has **no call site**
   anywhere in the module's generated code (only its definition and its registration). The `+0x64`
   getter used by the fault path is `sub_832BF128` (`lwz r3,100(r3); blr`) - the same accessor
   convention. Whether the setter is reached through the indirect table (`bctr`) from another module
   cannot be decided statically; it is not called directly.
5. `sub_82C6B358` does not in fact write `+0x10` in its own body (70 generated lines): it allocates
   520 bytes, calls `sub_829A5720(static_base, *(obj+0xAC))` with the very field the `+0xAC` setter
   wrote, and stores the result at `+0x14`. The runtime hit "`sub_82C6B358+0x197` writes `+0x10`" is
   therefore **one level too coarse**: the store happened inside one of its callees (`sub_82684490`,
   `sub_829A5720`, `sub_829A9718`) while the IP was inside the host range attributed to
   `sub_82C6B358`. Recorded as an open discrepancy in the attribution method, not as a finding.
6. The populate path (`sub_82C50EF0`, `sub_82C6AFC8`, `sub_82CA1138`, `sub_82C6B358`,
   `sub_82821808`) contains **zero `bctr`**: every call on it is a direct `bl`. The indirect calls in
   the neighbourhood live in `sub_82CBD7E0` (12), `sub_82689490` (4) and `sub_82689D08` (4).
7. Independent negative result on the same theory: our runtime's indirect dispatch
   (`ReXGlue/src/system/function_dispatcher.cpp:172`, `ResolveIndirectFunction`) resolves an
   unregistered target to `InvalidFunctionTrap`, whose handler prints
   `REX_FATAL("Call to invalid or unregistered function at guest address ...")`. Across 38012 log
   lines of the last run there is **no such line and no "EXECUTE MISS"**. A silently skipped code
   path caused by a failed indirect dispatch is therefore ruled out by evidence.

### Item 4 answer - the sibling port's notes and code (read-only)

`D:\FWC10\fifa-street-pc-port` is ReStreet v1.3, a released ReXGlue port of FIFA Street (same
publisher/engine family), and **the tree our own `ReXGlue` is derived from**. Its patch file
`patches/rexglue-local-changes.patch` (95 files) carries every runtime fix its author needed. The
three relevant ones, quoted:

1. `src/core/clock.cpp`, on the guest timebase and the game's busy-wait loops:
   > "The game polls the timebase (mftb) in tight busy-wait loops, for example its Direct3D fence and
   > vblank waits, which on a 360 owned a dedicated hardware thread. On a shared host that loop burns
   > a core and its SMT sibling. Calls that follow each other within ~2 us on a thread are such a loop:
   > pause between them and, in a long run, give the core to another ready thread. The time that is
   > returned is unaffected."
   (`_mm_pause()` on each rapid call, `::SwitchToThread()` every 256) plus the lock-free timebase:
   "Readers (every mftb the game executes, including its busy-wait loops) take no lock".
2. `src/kernel/xboxkrnl/xboxkrnl_rtl.cpp`, `RtlEnterCriticalSection`:
   > "Spin loop. Test before the locked compare-exchange and pause between tries; the guest's spin
   > counts (up to 65k) were meant for a dedicated hardware thread, so cap them on a shared host."
   (`spin_count = std::min<uint32_t>(spin_count, 2048);` + `_mm_pause()`)
3. `resources/templates/codegen/_indirect_call.inja`, `src/system/function_dispatcher.cpp` and
   `src/system/xmemory.cpp`:
   > "Resolve through the runtime: function tables are independent of XEX images. The dispatcher
   > handles calls across all loaded modules."
   > "FIFA Street fifadllzf.xex.dll. Generated indirect calls expect this module's function table
   > immediately after the original XEX image." (`if (code_base == 0x82610000)`)

**Applicability here: all three are already present in our tree, verbatim**
(`ReXGlue/src/core/clock.cpp:48-118,200-211` has `clock_seq_`/`UpdateGuestClockAt`/`_mm_pause`/
`SwitchToThread`; `xboxkrnl_rtl.cpp:391-402` has the capped spin and `_mm_pause`;
`xmemory.cpp:799` and `_indirect_call.inja:20` have the table fix). So the sibling's thread/wait/
timing work is **not** the missing piece - it is already inside the build that crashes. One detail
worth keeping: the adjacent-table fix is keyed to `code_base == 0x82610000` (FIFA Street's DLL). Our
DLL's code base is `0x82650000`, so our module takes the `else` branch - a dynamically allocated
table plus the dispatcher, which the author describes as the safe branch. No other thread, wait,
event or RenderWare item appears in the sibling's notes.

### Verified vs inferred

Verified by measurement this round: the two throttle runs' timings; the worker's three sample states;
that no `+0x64` write occurs in either; the `+0x00` hits and their values; every static claim in the
item-3 table (line ranges, store lists, `bctr` counts, the `memset`/accessor bodies); the absence of
dispatch-failure lines in the 38012-line runtime log; the presence of all three sibling fixes in our
tree. No rebuild, no override, no re-staged data, no Xenia launch.

Inferred, **not** verified: that `sub_82BDB2F8` is the setter for *this* object's `+0x64` (it is an
offset match only; the class identity is unproven and its callers are unknown); the callee
attribution of the `sub_82C6B358+0x197` store; that the throttle would behave differently with a
short-on/long-off duty.

### Next (proposed, awaiting go-ahead; no rebuild / no override / no re-staged data)

1. **Repeat the throttle with the correct duty (one run each, needs approval):** `1 ms on / 100 ms
   off` for ~3 s, and `2 ms on / 200 ms off`, **without** breaking the loop on the AV (report the AV
   time instead). That is the configuration that gives the factory ~100-200 ms of wall time to serve
   a request the creator has already issued, i.e. the only form of the race still open.
2. **(no run) Callers of `sub_82BDB2F8`.** Find its callers in `default.xex`'s generated sources and
   in the function-pointer data of both modules; if its only references are as *data*, its guest
   address is the intended indirect target and the question becomes which `bctr` should reach it.
3. **(no run) Cross-module `bctr` targets** in `sub_82CBD7E0` (12 sites), the faulting function,
   resolved through the guest pointer tables: if one of them is meant to be the producer that fills
   `+0x64`, the crash is a dispatch/timing issue rather than a skipped init.

---

