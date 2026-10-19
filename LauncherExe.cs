using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class LauncherExe
{
    [STAThread]
    private static int Main()
    {
        string folder = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(folder, "Launcher.ps1");
        if (!File.Exists(script))
        {
            MessageBox.Show(
                "Launcher.ps1 was not found next to this executable.",
                "2010 FIFA World Cup Settings",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 1;
        }

        try
        {
            ProcessStartInfo start = new ProcessStartInfo();
            start.FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell\\v1.0\\powershell.exe");
            start.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File \"" + script.Replace("\"", "\\\"") + "\"";
            start.WorkingDirectory = folder;
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            Process.Start(start);
            return 0;
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                "Could not open the launcher settings window.\r\n\r\n" + ex.Message,
                "2010 FIFA World Cup Settings",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 1;
        }
    }
}
