## 2010 FIFA World Cup South Africa (PC Port) — Version 0.6

Big update focused on graphics, World Cup mode UI, stability, team select, and keyboard controls. Both installers still build the port **on your PC from your own Xbox 360 ISO** — no game assets or executables are redistributed.

### Highlights & Fixes

- **Resolution & upscaling**
  - Reliable resolution list (720p–5K), native-first ordering, renderer max respected
  - Graphics & Upscaling tab: profiles, internal resolution (1x–4x), FXAA, MSAA, readback, anisotropic filter
  - **FSR present path** with quality modes (Quality / Balanced / Performance / Ultra / Native AA)
  - Default **1x + FSR Quality**, FXAA off — keeps the yellow capital markers on the Select Team globe
  - At 2x+: safer combos (Standard VSync, AF8, no stadium force-sync) so matches stay playable

- **Select Team (right stick / globe)**
  - Crosshair now updates the selected nation again (`readback_resolve = some`)
  - Fixed wrong-nation picks under internal upscale (half-pixel / average-color tuning)
  - Capital city markers stay visible with FSR (GPU min point size; FXAA no longer eats 1px dots)

- **World Cup mode / HUD / UI**
  - Missing UI elements addressed via upscale threshold **640** (bloom/DoF/replay RTs stay native)
  - Black replays and cutscenes fixed when using internal resolution scale

- **Performance / frame pacing**
  - Hard **30 FPS lock** fixed: present-interval cap for WC2010’s `fifadllzf.xex` (interval 2 → 1)
  - Runtime/GPU deployed to **both** install root and `Backends\D3D12\` (the path the game actually loads)
  - Removed harmful readback sync-budget that caused fence timeouts and broke picking

- **Keyboard & Settings**
  - Full keyboard remapping in Settings (presets + per-action binds)
  - Official game icons on Settings, game exe, Desktop and Start Menu shortcuts

- **Crashes & installer**
  - Prior crash / QI-chain / fault-loop hardening carried forward from the ReXGlue patch set
  - USA/Asia disc support and resilient VS Build Tools detection (from v0.4) retained
  - Fresh installs get sane defaults: FSR Quality, present-interval cap, no sync budget

### Downloads

| Asset | Description |
|---|---|
| `FIFA-World-Cup-2010-Offline-Installer-v2.zip` | **Offline installer.** Bundles LLVM 20.1.8 and the ReXGlue SDK. Requires VS C++ Build Tools already installed. |
| `FIFA-World-Cup-2010-Online-Installer-v2.zip` | **Online installer.** Downloads missing toolchain pieces on first run (~500 MB) into `%LOCALAPPDATA%\FWC10`. |
| `FWC10-ReXGlue-SDK-0.3.3-win64.zip` | ReXGlue SDK used by the online installer. **Do not download manually** — the installer fetches it. |

### How to install

1. Download and extract one of the installer zips.
2. Run `FWC10OfflineInstaller.exe` or `FWC10OnlineInstaller.exe`.
3. Pick your unmodified Xbox 360 ISO (**PAL** or **USA/Asia En,Fr,Es**) and a destination folder.
4. Start installation (local compile, roughly 20–40 minutes), then use **Settings** before Play.

Requirements: Windows 10/11 x64, ~12 GB free, Visual Studio C++ Build Tools (CMake/Ninja/MSVC).

Headless: `FWC10OnlineInstaller.exe --install "<iso>" "<folder>"` (optional `--jobs N`).

### Notes for existing installs

If you already installed an older build, either re-run the v0.6 installer into a fresh folder, or copy the updated `rexruntime.dll` / `rexgpu-xenos.dll` into **both** the game folder and `Backends\D3D12\`, and refresh `Settings.exe` from the new package.

### SHA-256 Hashes

- `FIFA-World-Cup-2010-Offline-Installer-v2.zip`: `da4f227adb5a4d3e8b0c53834ab48c317ad6e8190780da7cc1f778642cbf863b`
- `FIFA-World-Cup-2010-Online-Installer-v2.zip`: `7cee0bde3c83d916da10e3f2589ed6fbd50d83f80ddd615505b1da6918acba3d`
- `FWC10-ReXGlue-SDK-0.3.3-win64.zip`: `d1065d84e0f63bc9da010eb7bda2dcd468811dec56757af208eb7097f1226a24`
