param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [Parameter(Mandatory = $true)][string]$OutFile,
    [UInt64]$GuestBase = 0x82300000L,
    [UInt32]$Size = 0x1850000,
    [UInt64]$MemBase = 0x100000000L,
    [Parameter(Mandatory = $true)][UInt32]$ProbeAddr,
    [Parameter(Mandatory = $true)][UInt32]$ProbeWord,
    [int]$SettleMs = 300
)
# Starts the port and copies the loaded (decrypted, decompressed) fifadllzf.xex image out of
# the guest memory mapping (host address = MemBase + guest address) as soon as it is in place.
#
# ProbeAddr/ProbeWord: any guest address inside .text and the big-endian instruction word
# expected there once the image is loaded (take one from a crash log's "[code around LR=...]"
# dump). The game can crash shortly after boot on an unsupported region, so the copy is made
# SettleMs after the probe matches. The output stays on your machine: it is game code.
$src = @"
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
public static class GuestDump {
  [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenProcess(int access, bool inherit, int pid);
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  public static string Run(string exe, string outFile, ulong guestBase, uint size, ulong memBase, uint probeAddr, uint probeWord, int settleMs) {
    var psi = new ProcessStartInfo(exe); psi.WorkingDirectory = Path.GetDirectoryName(exe); psi.UseShellExecute = false;
    var p = Process.Start(psi);
    IntPtr h = OpenProcess(0x0410, false, p.Id); // PROCESS_VM_READ | PROCESS_QUERY_INFORMATION
    var probe = new byte[4]; IntPtr rd;
    var sw = Stopwatch.StartNew();
    try {
      while (!p.HasExited && sw.ElapsedMilliseconds < 60000) {
        if (ReadProcessMemory(h, new IntPtr((long)(memBase + probeAddr)), probe, new IntPtr(4), out rd)) {
          uint w = (uint)(probe[0] << 24 | probe[1] << 16 | probe[2] << 8 | probe[3]);
          if (w == probeWord) {
            System.Threading.Thread.Sleep(settleMs);
            var buf = new byte[size]; int ok = 0; const int chunk = 0x1000; var page = new byte[chunk];
            for (uint o = 0; o < size; o += chunk) {
              if (ReadProcessMemory(h, new IntPtr((long)(memBase + guestBase + o)), page, new IntPtr(chunk), out rd)) {
                Buffer.BlockCopy(page, 0, buf, (int)o, chunk); ok++;
              }
            }
            File.WriteAllBytes(outFile, buf);
            return string.Format("dump OK at {0} ms: {1}/{2} pages readable", sw.ElapsedMilliseconds, ok, size / chunk);
          }
        }
        System.Threading.Thread.Sleep(20);
      }
      return "probe never matched (exited=" + p.HasExited + ")";
    } finally {
      CloseHandle(h);
      try { if (!p.HasExited) p.Kill(); } catch {}
    }
  }
}
"@
Add-Type -TypeDefinition $src -Language CSharp
[GuestDump]::Run($Exe, $OutFile, $GuestBase, $Size, $MemBase, $ProbeAddr, $ProbeWord, $SettleMs)
