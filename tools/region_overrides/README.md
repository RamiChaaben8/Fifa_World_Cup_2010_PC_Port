# Region overrides for fifadllzf.xex

`fifadllzf.xex` is laid out differently in each release of the game (`default.xex` is identical), so the `[functions]` overrides in `Installer/recomp-template/config` only fit the release they were made from:

| Release | fifadllzf.xex SHA-256 | Overrides |
|---|---|---|
| PAL | `462676f9fbab83530c2659e79aa43e3dbe81b43dc917db9299933c19fa34905d` | `fifadllzf_overrides.toml` |
| USA/Asia (En,Fr,Es) | `701b4737d057b64a228fc8fdbe7a83546fe4b5078ef728b239176fcaa617c1da` | `fifadllzf_overrides_usa.toml` |

`Installer/BuildWorldCup2010.ps1` picks the list by that hash. On USA/Asia it also builds with `REX_R32_DISABLE_QI_CHAIN_OVERRIDE=1`, because `0x8323FB38` is a different function in that release.

## Making the list for another release

1. **Build without region overrides.** Leave `[functions]` empty in `fifadllzf_overrides.toml` and run the build once. Keep the workspace.
2. **Dump the loaded image.** It stays on your PC, because it is game code.
   ```powershell
   .\Dump-GuestImage.ps1 -Exe "<install>\FIFA World Cup 2010.exe" -OutFile fifadllzf.bin `
       -ProbeAddr 0x82650648L -ProbeWord 0x4BFFFFA0L
   ```
   The probe is any `.text` address and its instruction word. Take it from a crash log's `[code around LR=...]` dump.
3. **Find the missing functions.**
   ```powershell
   .\Find-MissingFunctions.ps1 -GenDir "<workspace>\WorldCup2010Rex\generated\fifadllzf_xex" `
       -Image fifadllzf.bin -OutToml found.toml -OutReport found.txt
   ```
   Check the section bounds in the PE header of the dump. `-TextLo`/`-TextHi`/`-DataRange` default to the USA/Asia layout.
4. **Use `found.toml` as the `[functions]` list and rebuild.** Then drop every entry that `codegen.log` reports as `[functions] 0x... outranked by import`, because those are import thunks that leave undefined `sub_` symbols at link time.

A candidate is a 32-bit pointer in `.rdata`/`.data`, or a `lis` + `addi`/`ori` pair in `.text`, that targets code not covered by any recompiled function. It is accepted when the gap run is at most 0x400 bytes, has no zero word, and ends with `blr` / `bctr` / `b`.
