## 2010 FIFA World Cup South Africa (PC Port) - Version 0.3

### Highlights & Fixes
- **Full Keyboard / Mouse Controller Emulation & Customization**:
  - Fixed ReXGlue XAM input capability filtering bug (`XamInputGetCapabilities` now properly responds to game queries, spawning `InputThread` for player 1).
  - Added dedicated **Keyboard Controls** tab in `Settings.exe` with full customization for all 18 controller inputs (Movement, Actions, Triggers, Bumpers, D-Pad, Start, Back).
  - Presets for Classic FIFA, WASD, and Custom mapping.
  - Fixed TOML configuration persistence to properly escape backslashes.

- **Installer Improvements**:
  - Fixed ISO extraction error on Xbox 360 `$SystemUpdate` folder (`-s` flag).
  - Standardized installation target directory to `\Fifa World Cup 2010` by default.
  - Automated official game icon embedding directly into `FIFA World Cup 2010.exe`.
  - Added Desktop and Start Menu shortcuts creation.
  - Granted standard user write permissions on install folder for config and logs without requiring run-as-admin.

### Available Assets
- `FIFA-World-Cup-2010-Setup-v0.3.exe`: Complete self-extracting standalone setup.
- `FIFA-World-Cup-2010-Installer-v2.zip`: Native Win32 C++ installer package.

### SHA-256 Hashes
- `FIFA-World-Cup-2010-Setup-v0.3.exe`: `3CF9F8466CE07204F8ACE34C92DEEE51937402118AEDE614B83771A1DBF04347`
- `FIFA-World-Cup-2010-Installer-v2.zip`: `3CFB95D1DC2B9E9F46ED6F09879C414C409C3813DE4FA616CE03AF2A033413D5`
