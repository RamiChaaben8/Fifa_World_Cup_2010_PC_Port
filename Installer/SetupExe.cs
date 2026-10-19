using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Windows.Forms;

internal static class SetupExe
{
    [STAThread]
    private static int Main()
    {
        try
        {
            string root = Path.Combine(Path.GetTempPath(), "FWC10-Setup-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(root);
            Assembly assembly = Assembly.GetExecutingAssembly();
            using (Stream payload = assembly.GetManifestResourceStream("FWC10.Payload.zip"))
            {
                if (payload == null) throw new InvalidOperationException("Embedded setup payload is missing.");
                using (ZipArchive archive = new ZipArchive(payload, ZipArchiveMode.Read))
                {
                    string rootPrefix = Path.GetFullPath(root) + Path.DirectorySeparatorChar;
                    foreach (ZipArchiveEntry entry in archive.Entries)
                    {
                        string relative = entry.FullName.Replace('/', Path.DirectorySeparatorChar);
                        string target = Path.GetFullPath(Path.Combine(root, relative));
                        if (!target.StartsWith(rootPrefix, StringComparison.OrdinalIgnoreCase))
                            throw new InvalidDataException("The embedded setup payload contains an invalid path.");
                        if (entry.FullName.EndsWith("/", StringComparison.Ordinal))
                        {
                            Directory.CreateDirectory(target);
                            continue;
                        }
                        Directory.CreateDirectory(Path.GetDirectoryName(target));
                        using (Stream input = entry.Open())
                        using (Stream output = File.Create(target)) input.CopyTo(output);
                    }
                }
            }

            string script = Path.Combine(root, "Installer", "Setup.ps1");
            if (!File.Exists(script)) throw new FileNotFoundException("The embedded setup script is missing.", script);
            ProcessStartInfo start = new ProcessStartInfo();
            start.FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                "WindowsPowerShell\\v1.0\\powershell.exe");
            start.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File \"" + script + "\"";
            start.WorkingDirectory = root;
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            if (Process.Start(start) == null) throw new InvalidOperationException("Could not start the setup user interface.");
            return 0;
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "FIFA World Cup 2010 Setup",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
