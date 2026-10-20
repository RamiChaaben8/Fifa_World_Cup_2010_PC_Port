# 2010 FIFA World Cup South Africa – PC Port

This project contains no game files, game data or generated game code. It requires your own
legally obtained copy of the game. It is an unofficial, experimental, incomplete work in
progress, not affiliated with or endorsed by EA. Game and club names are trademarks of their
owners. Based on [fifa-street-pc-port](https://github.com/SAMUELITODAVILA/fifa-street-pc-port)
and the [ReXGlue SDK](https://github.com/RexGlue/ReXGlue). This remains an experimental port;
some game paths may stop on missing recompiled functions or other compatibility issues.

## Building

### Installing from your own ISO (Windows x64)

Download and run `FIFA-World-Cup-2010-Setup-v0.3.4.exe` from the GitHub v0.3 release, then select
your legally obtained Xbox 360 ISO and an empty parent folder. Setup creates `FIFA World Cup 2010`
inside the folder you choose. The single-file installer embeds LLVM and the pinned ReXGlue source
and builds the port locally; it does not include your ISO/game data. Visual Studio C++ Build Tools
are still downloaded from Microsoft if they are not already installed. The first run may take a
while and several gigabytes of disk space. Approve the Microsoft UAC prompt if Build Tools or a
protected install location require it. When setup completes, run `Settings.exe` in the chosen folder.

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

## License

This repository is released under the MIT License — see [LICENSE](LICENSE).

The patches in `patches/` are modifications to the ReXGlue SDK, which is © Tom Clay and
contributors and licensed under BSD 3-Clause. See `ReXGlue/LICENSE` for the full text
(not included here; clone ReXGlue separately).

The ReXGlue BSD 3-Clause license requires: (1) source redistributions retain the
copyright notice, conditions, and disclaimer; (2) binary redistributions reproduce the
notice in documentation; (3) no endorsement use of the copyright holder's name without
permission.
