param(
    [Parameter(Mandatory = $true)][string]$GenDir,      # <workspace>\WorldCup2010Rex\generated\fifadllzf_xex
    [Parameter(Mandatory = $true)][string]$Image,       # output of Dump-GuestImage.ps1
    [Parameter(Mandatory = $true)][string]$OutToml,     # proposed [functions] entries
    [Parameter(Mandatory = $true)][string]$OutReport,   # every candidate, accepted or skipped
    [UInt32]$ImageBase = 0x82300000L,
    [UInt32]$TextLo = 0x82650000L,
    [UInt32]$TextHi = 0x838D8DD4L,
    [UInt32[]]$DataRange = @(0x82300400L, 0x825D5FA4L, 0x838E0000L, 0x83AECAE0L)  # .rdata lo,hi, .data lo,hi
)
# Finds code addresses that the game reaches indirectly (32-bit pointers stored in .rdata/.data,
# or materialised in .text with lis + addi/ori) but that lie in gaps not covered by any
# recompiled function, and proposes a ReXGlue [functions] override for each.
#
# Coverage comes from the generated C++ of a build WITHOUT region overrides: every
# DEFINE_REX_FUNC(sub_X) body lists its PPC instructions in address order as "// insn"
# comments, with loc_X labels as checkpoints.
#
# A candidate is accepted when its gap run is <= 0x400 bytes, contains no zero word and its
# last instruction is an unconditional terminator (blr / bctr / b). `end` (exclusive) is the
# first covered address, the next candidate or the padding that follows.
#
# After a codegen run with the result, drop the entries that ReXGlue logs as
# "[functions] 0x... outranked by import" (import thunks): they leave undefined sub_ symbols.
$src = @"
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
public static class Finder {
  static uint Base;
  static byte[] img;
  static uint W(uint ga) { int o = (int)(ga - Base); return (uint)(img[o] << 24 | img[o+1] << 16 | img[o+2] << 8 | img[o+3]); }
  static HashSet<uint> covered = new HashSet<uint>();
  static Regex fn = new Regex(@"^DEFINE_REX_FUNC\(sub_([0-9A-F]{8})\)");
  static Regex lbl = new Regex(@"^loc_([0-9A-F]{8}):");
  static bool IsTerm(uint w) {
    if (w == 0x4E800020 || w == 0x4E800420) return true;   // blr, bctr
    if ((w >> 26) == 18 && (w & 1) == 0) return true;     // b (no link)
    return false;
  }
  public static string[] Run(string genDir, string image, uint imageBase, uint textLo, uint textHi, uint[] data, string outToml, string outReport) {
    Base = imageBase; img = File.ReadAllBytes(image);
    foreach (var file in Directory.GetFiles(genDir, "*_recomp.*.cpp")) {
      uint addr = 0; bool inFn = false;
      foreach (var raw in File.ReadLines(file)) {
        var m = fn.Match(raw);
        if (m.Success) { addr = Convert.ToUInt32(m.Groups[1].Value, 16); inFn = true; continue; }
        if (!inFn) continue;
        var l = lbl.Match(raw);
        if (l.Success) { addr = Convert.ToUInt32(l.Groups[1].Value, 16); continue; }
        string t = raw.TrimStart();
        if (t.StartsWith("// ") && t.Length > 3) { covered.Add(addr); addr += 4; }
      }
    }
    var cand = new Dictionary<uint, string>();
    for (int r = 0; r + 1 < data.Length; r += 2) {
      for (uint a = data[r]; a + 4 <= data[r + 1]; a += 4) {
        uint v = W(a);
        if (v >= textLo && v < textHi && (v & 3) == 0 && !covered.Contains(v) && !cand.ContainsKey(v)) cand[v] = "data@" + a.ToString("X8");
      }
    }
    for (uint a = textLo; a + 4 <= textHi; a += 4) {
      uint w = W(a);
      if ((w >> 26) != 15 || ((w >> 16) & 31) != 0) continue;   // lis rD,hi
      uint rd = (w >> 21) & 31; uint hi = (w & 0xFFFF) << 16;
      for (uint k = 1; k <= 6 && a + 4 * k < textHi; k++) {
        uint w2 = W(a + 4 * k); uint op = w2 >> 26; uint ra = (w2 >> 16) & 31; uint rs = (w2 >> 21) & 31;
        uint v = 0; bool hit = false;
        if (op == 14 && ra == rd) { v = (uint)(hi + (uint)(short)(w2 & 0xFFFF)); hit = true; }   // addi
        if (op == 24 && rs == rd) { v = hi | (w2 & 0xFFFF); hit = true; }                         // ori
        if (hit) {
          if (v >= textLo && v < textHi && (v & 3) == 0 && !covered.Contains(v) && !cand.ContainsKey(v)) cand[v] = "code@" + (a + 4 * k).ToString("X8");
          break;
        }
      }
    }
    var keys = new List<uint>(cand.Keys); keys.Sort();
    var toml = new StringBuilder(); var rep = new List<string>();
    int good = 0, bad = 0;
    for (int i = 0; i < keys.Count; i++) {
      uint s = keys[i]; uint next = (i + 1 < keys.Count) ? keys[i + 1] : textHi;
      uint e = s; uint last = 0; string why = "";
      while (e < textHi && e < next && !covered.Contains(e)) {
        uint w = W(e);
        if (w == 0) { why = "pad"; break; }
        last = w; e += 4;
      }
      if (why == "") why = covered.Contains(e) ? "covered" : (e >= next ? "next-candidate" : "end");
      bool ok = e > s && IsTerm(last) && (e - s) <= 0x400;
      rep.Add(string.Format("{0:X8}..{1:X8} n={2,3} last={3:X8} stop={4} src={5} {6}", s, e, (e - s) / 4, last, why, cand[s], ok ? "OK" : "SKIP"));
      if (ok) { good++; toml.AppendFormat("\"{0:X8}\" = {{ end = 0x{1:X8} }}  # {2}, {3} insns\n", s, e, cand[s], (e - s) / 4); } else bad++;
    }
    File.WriteAllText(outToml, toml.ToString());
    File.WriteAllLines(outReport, rep.ToArray());
    return new string[] { "covered instructions: " + covered.Count, "candidates: " + keys.Count + "  accepted: " + good + "  skipped: " + bad };
  }
}
"@
Add-Type -TypeDefinition $src -Language CSharp
[Finder]::Run($GenDir, $Image, $ImageBase, $TextLo, $TextHi, $DataRange, $OutToml, $OutReport)
