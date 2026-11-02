## 2010 FIFA World Cup South Africa PC Port - Version 0.7

This release focuses on smoother high-resolution rendering, an updated Settings experience, and installer/runtime maintenance. The installer builds the port locally from your own Xbox 360 ISO; no game ISO, game assets, or generated game executable is distributed.

### What's new

- **High-resolution performance:** Updated, matched D3D12 renderer/runtime binaries improve readback and presentation performance at higher internal resolutions. The default remains 1x; higher render scales are optional in Settings and may still require a capable GPU.
- **Native performance profile:** Renamed the Settings graphics preset from "Xenia" to "Native." Its tuning and saved-config behavior are unchanged.
- **Settings and runtime maintenance:** Settings identifies itself as v0.7, checks the latest GitHub release, and retains the existing reset-defaults and log-pruning behavior.
- **Installer updates:** Refreshed online and offline installers include the updated Settings launcher and renderer/runtime pair. Existing installs can be updated by running the v0.7 installer into a new folder or manually replacing the runtime/GPU DLLs in both the game root and `Backends\D3D12\`, plus `Settings.exe`.

### Downloads

| File | Description |
|---|---|
| `FIFA-World-Cup-2010-Offline-Installer-v2.zip` | Includes LLVM and the ReXGlue SDK. Visual Studio C++ Build Tools must already be installed. |
| `FIFA-World-Cup-2010-Online-Installer-v2.zip` | Downloads missing build prerequisites on first run. |
| `FWC10-ReXGlue-SDK-0.3.3-win64.zip` | SDK required by the online installer; normally downloaded by the installer automatically. |

### Install

1. Download and extract one installer ZIP.
2. Run `FWC10OfflineInstaller.exe` or `FWC10OnlineInstaller.exe`.
3. Select your unmodified Xbox 360 ISO and an install folder. The game is compiled locally.
4. Configure display, controls, and graphics in `Settings.exe` before launching the game.

Requirements: Windows 10/11 x64, your own Xbox 360 ISO, Visual Studio C++ Build Tools, and approximately 12 GB free disk space. The offline installer requires no internet at install time.

### SHA-256

- `FIFA-World-Cup-2010-Offline-Installer-v2.zip`: `339d6bf4346a9ab29904f2dee7ea7fa14e1396b717f3bab3e09829df39d1c4ab`
- `FIFA-World-Cup-2010-Online-Installer-v2.zip`: `37513436ee09e5ed5cd6a7290b8931ecd0026a56f6d6ec1da8f1cd010eb35bd5`
- `FWC10-ReXGlue-SDK-0.3.3-win64.zip`: `d1065d84e0f63bc9da010eb7bda2dcd468811dec56757af208eb7097f1226a24`
