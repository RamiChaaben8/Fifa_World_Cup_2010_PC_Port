# 2010 FIFA World Cup South Africa – PC Port

This project contains no game files, game data or generated game code. It requires your own
legally obtained copy of the game. It is an unofficial, experimental, incomplete work in
progress, not affiliated with or endorsed by EA. Game and club names are trademarks of their
owners. Based on [fifa-street-pc-port](https://github.com/samuelit0davila/fifa-street-pc-port)
and the [ReXGlue SDK](https://github.com/rexglue/rexglue-sdk). This remains an experimental port;
some game paths may stop on missing recompiled functions or other compatibility issues.

## Building

### Installing from your own ISO (Windows x64)

Download the **v0.7** online or offline installer from the [GitHub Releases page](https://github.com/RamiChaaben8/Fifa_World_Cup_2010_PC_Port/releases/latest), then select your legally obtained Xbox 360 ISO and an install folder. Both installers compile the port locally from your ISO; no ISO, game data, or generated game code is included. The online installer downloads missing build tools, while the offline installer bundles LLVM and the ReXGlue SDK (Visual Studio C++ Build Tools must already be installed). When setup completes, configure the game with `Settings.exe` in the install folder.

### Launcher

On Windows, run `Settings.exe` to open the display settings and choose the game executable. Keep
`Launcher.ps1` and the `icons/` folder beside it. The launcher does not include the game; select
your own legally obtained game files when building or running the port. The executable starts the
settings UI through Windows PowerShell 5.1, which is included with supported Windows installations.
Builds produce `FIFA World Cup 2010.exe`; game save data is stored under
`Documents/FIFA World Cup 2010`.

### Prerequisites

- **Your own ISO** of *2010 FIFA World Cup South Africa* (Xbox 360, any region), extracted
  with [extract-xiso](https://github.com/XboxDev/extract-xiso). You supply the ISO; it is not
  included here.
- **ReXGlue SDK** — clone at the pinned commit and apply the patches in `patches/`:

  ```powershell
  git clone https://github.com/rexglue/rexglue-sdk.git
  cd rexglue-sdk
  git checkout c94f5ebdcb3c9d1a460ca48e04f9758448f8d518
  git apply ..\patches\rexglue-v0.3-local.patch
  ```

- **Fix the 14 libmspack symlink stubs on Windows** — ReXGlue's `thirdparty/libmspack`
  uses Unix symlinks that do not survive a Windows `git clone`. Replace each stub with a
  real copy of the target file before building (or clone inside WSL and copy out), then apply
  `patches\rexglue-libmspack-v0.3.patch`.

- **Build tools on PATH:**
  - CMake and Ninja (ship with Visual Studio 2022; add their `bin/` dirs to the session PATH)
  - LLVM / Clang (required by ReXGlue's CMake toolchain)

  Example (Visual Studio 2022 Community):

  ```powershell
  $vs = "C:\Program Files\Microsoft Visual Studio\18\Community"
  $env:PATH = "$vs\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin;" +
              "$vs\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja;" +
              $env:PATH
  ```

### Build

```powershell
powershell -ExecutionPolicy Bypass -File "Installer\BuildWorldCup2010.ps1" `
    -GameData  "<path to extracted ISO contents>" `
    -Output    "<output directory>" `
    -Workspace "<workspace directory>" `
    -SourceBuild -Jobs 2
```

Use `-Workspace` to point at an existing codegen output directory so codegen is not
re-run on incremental builds. The first run runs codegen (~10 min) and compiles (~8 min).

## DLC and saves from your own console

The game can use its official downloadable content (kits, balls, adboards) and save files,
such as squad files, copied from **your own** Xbox 360. Nothing is included here: you supply
the packages. These are the files under `Content\0000000000000000\454108E4\00000002\` (DLC) or
`Content\<profile>\454108E4\00000001\` (saves) on the console drive.

Two tools extract those STFS packages into the folder the port reads. Both produce identical
files, do not change the game or the runtime, and need no rebuild:

- **`InstallDLC.exe`**: a small window for players. No Python or command line needed.
- **`tools\install_xcontent.py`**: the same as a Python 3 script, for scripting and advanced use.

### Common uses

| What you want | Package to install | Where it shows up in game |
|---|---|---|
| **Updated squads / rosters** | A squad save, e.g. `Squads0 <date>` (type `00000001`, a `CON` file) | Load it from the game's squad load/save menu. It then replaces the active squads. |
| **Official kits update** | DLC *Official Kits Update* | New kits for the updated teams (e.g. Chile, Honduras, North Korea, Peru) in team/kit selection and matches |
| **Extra balls** | DLC *Flag Themed Ball Updates* | Additional balls in the match settings ball selection |
| **Tournament adboards** | DLC *Adboards* | Pitch-side advertising boards in stadiums |

Notes on squads:

- A squad file is a **save**, not DLC, so console unlock tools such as XM360 do not apply to it.
  In the port it only needs to be installed like any other package.
- When the game loads a squad file, it saves it again as a new `Squads0 <current date>` and
  removes the old entry. Keep your original package if you want to install it again later.
- Squad files made by another region of the game (e.g. the German "2010 FIFA WM") have loaded
  in testing, but this is not guaranteed for every file.

### Using InstallDLC.exe

1. Copy the packages from your console to a folder on your PC (for example the whole
   `454108E4` folder).
2. Open `InstallDLC.exe` and choose that folder under **1. Folder with your packages**.
3. The list shows each package with its type (DLC, Squads) and status: *Ready*,
   *Already installed* or *Skipped* (for example, content for another game). Tick what you want
   and press **Install selected**.
4. Start the game. DLC loads automatically; squads are loaded from the game's squad menu.

Leave **2. Game save folder** at its default (`Documents\FIFA World Cup 2010`) unless you
moved it. To pre-select a folder, pass it as an argument: `InstallDLC.exe "<folder>"`. A
launcher or script can also install without a window:
`InstallDLC.exe --install "<file or folder>" [--root "<dir>"]`. This returns `0` on success.

Build it with the C# compiler included in Windows (no Visual Studio needed):

```powershell
powershell -ExecutionPolicy Bypass -File tools\XContentInstaller\Build.ps1
# -> tools\XContentInstaller\bin\InstallDLC.exe
```

### Using the Python script

```powershell
# Show what a package or folder contains (writes nothing)
py tools\install_xcontent.py --list "<folder with your packages>"

# Install into %USERPROFILE%\Documents\FIFA World Cup 2010
py tools\install_xcontent.py "<folder with your packages>"
```

Use `--root <dir>` for a different save location and `--profile-xuid <hex>` for a different
profile.

### Notes

- DLC is installed to `0000000000000000\454108E4\00000002\<package>\`, and saves to
  `B13EBABEBABEBABE\454108E4\00000001\<package>\` (the port's local profile), both under
  `Documents\FIFA World Cup 2010`. Each package also gets a `Headers\...\<package>.header` file.
- Re-running either tool overwrites only the packages you give it. To uninstall, delete the
  package folder and its `.header` file.
- Packages from another console do not need XM360 or any other unlock tool; the port does not
  check console signatures.
- Tested with the kits, balls and adboards DLC and a 2010 squad file.

## License

This repository is released under the MIT License — see [LICENSE](LICENSE).

The patches in `patches/` are modifications to the ReXGlue SDK, which is © Tom Clay and
contributors and licensed under BSD 3-Clause. See `ReXGlue/LICENSE` for the full text
(not included here; clone ReXGlue separately).

The ReXGlue BSD 3-Clause license requires: (1) source redistributions retain the
copyright notice, conditions, and disclaimer; (2) binary redistributions reproduce the
notice in documentation; (3) no endorsement use of the copyright holder's name without
permission.
