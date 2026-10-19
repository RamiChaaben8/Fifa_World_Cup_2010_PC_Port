using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class SetupExe
{
    [STAThread]
    private static int Main()
    {
        string root = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(root, "Installer", "Setup.ps1");
        if (!File.Exists(script))
        {
            MessageBox.Show("Installer\\Setup.ps1 is missing. Extract the complete v0.3 setup package first.",
                "FIFA World Cup 2010 Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }

        try
        {
            ProcessStartInfo start = new ProcessStartInfo();
            start.FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                "WindowsPowerShell\\v1.0\\powershell.exe");
            start.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File \"" + script + "\"";
            start.WorkingDirectory = root;
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            Process.Start(start);
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
