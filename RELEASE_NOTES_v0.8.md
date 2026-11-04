## 2010 FIFA World Cup South Africa PC Port - Version 0.8

This release adds offline achievement support and tools for installing DLC and squad saves copied from your own Xbox 360. The game is still built locally from your own ISO; no game ISO, copyrighted game assets, or generated game executable is distributed.

### What's new

- **Offline achievements:** Track 31 offline achievements, with persistent unlocks and progress displayed in the Settings Achievements tab.
- **Achievement notifications:** Unlocks display an animated notification using the game's achievement icons and an unlock sound.
- **Install your own DLC and squads:** `InstallDLC.exe` provides a graphical installer, and `tools/install_xcontent.py` offers the same functionality from Python. Both install supported STFS packages copied from your own console; no DLC or save packages are included.
- **Updated installers and Settings:** The v0.8 Settings launcher and matched runtime are included in refreshed online and offline installer packages.

### DLC tool credit

The DLC and squad installation tools were contributed by **Miguel Gonzalez (`@miguel-gl`)** in [PR #16](https://github.com/RamiChaaben8/Fifa_World_Cup_2010_PC_Port/pull/16). Thank you!

### Downloads

- `FIFA-World-Cup-2010-Offline-Installer-v2.zip` — bundles LLVM and the ReXGlue SDK; Visual Studio C++ Build Tools are required.
- `FIFA-World-Cup-2010-Online-Installer-v2.zip` — downloads missing build prerequisites when needed.
- `FWC10-ReXGlue-SDK-0.3.3-win64.zip` — SDK archive used by the online installer.
- `InstallDLC.exe` — standalone GUI for installing your own DLC and squad packages.

### Install

1. Download and extract an installer ZIP.
2. Run `FWC10OfflineInstaller.exe` or `FWC10OnlineInstaller.exe`.
3. Select your unmodified Xbox 360 ISO and an install folder; the game is compiled locally.
4. Open `Settings.exe` to configure the game and view achievement progress.

Requirements: Windows 10/11 x64, your own Xbox 360 ISO, Visual Studio C++ Build Tools, and approximately 12 GB free disk space. The offline installer requires no internet connection at install time.

### SHA-256

- `FIFA-World-Cup-2010-Offline-Installer-v2.zip`: `0b24e5eee79463df37fa55cb5a10616eb2c03ea40dfcb9a16f9d847e0758332c`
- `FIFA-World-Cup-2010-Online-Installer-v2.zip`: `d819010f09573b2fa64ff6db782d285c28d538bb8e0e155d625be569c69974cc`
- `FWC10-ReXGlue-SDK-0.3.3-win64.zip`: `d1065d84e0f63bc9da010eb7bda2dcd468811dec56757af208eb7097f1226a24`
- `InstallDLC.exe`: `97a984345b02677952315e3ce0416093912632e4ef78c109cdacc6a2dcd34863`
