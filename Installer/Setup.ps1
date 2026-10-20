$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Fwc10SetupWindowIcon {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam);
    public static void Apply(IntPtr hWnd, IntPtr hIcon) {
        SetCurrentProcessExplicitAppUserModelID("FWC10.WorldCup2010.Setup");
        SendMessage(hWnd, 0x0080, IntPtr.Zero, hIcon);
        SendMessage(hWnd, 0x0080, new IntPtr(1), hIcon);
    }
}
'@

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$worker = Join-Path $root 'Installer\SetupWorker.ps1'
$iconPath = Join-Path $root 'icons\game_logo.ico'

$form = New-Object System.Windows.Forms.Form
$form.Text = 'FIFA World Cup 2010 - Setup'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size(700, 540)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.BackColor = [System.Drawing.Color]::FromArgb(24, 35, 40)
$form.ForeColor = [System.Drawing.Color]::WhiteSmoke
if (Test-Path -LiteralPath $iconPath) {
    $form.Icon = New-Object System.Drawing.Icon($iconPath)
    $form.ShowIcon = $true
    $form.ShowInTaskbar = $true
    $form.Add_Shown({ if ($form.Icon) { [Fwc10SetupWindowIcon]::Apply($form.Handle, $form.Icon.Handle) } })
}

$banner = New-Object System.Windows.Forms.Panel
$banner.Location = New-Object System.Drawing.Point(0, 0)
$banner.Size = New-Object System.Drawing.Size(700, 82)
$banner.BackColor = [System.Drawing.Color]::FromArgb(0, 145, 132)
$form.Controls.Add($banner)
$banner.Add_Paint({
    param($sender, $eventArgs)
    $r = New-Object System.Drawing.Rectangle(0, 0, $sender.Width, $sender.Height)
    $b = New-Object System.Drawing.Drawing2D.LinearGradientBrush($r,
        [System.Drawing.Color]::FromArgb(0, 174, 157),
        [System.Drawing.Color]::FromArgb(18, 67, 83), 0)
    $eventArgs.Graphics.FillRectangle($b, $r)
    $b.Dispose()
})
$title = New-Object System.Windows.Forms.Label
$title.Text = 'FIFA WORLD CUP 2010'
$title.Location = New-Object System.Drawing.Point(24, 12)
$title.Size = New-Object System.Drawing.Size(540, 38)
$title.Font = New-Object System.Drawing.Font('Segoe UI', 22, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::White
$title.BackColor = [System.Drawing.Color]::Transparent
$banner.Controls.Add($title)
$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'SOUTH AFRICA  |  INSTALLATION WIZARD'
$subtitle.Location = New-Object System.Drawing.Point(28, 51)
$subtitle.Size = New-Object System.Drawing.Size(470, 20)
$subtitle.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(247, 222, 160)
$subtitle.BackColor = [System.Drawing.Color]::Transparent
$banner.Controls.Add($subtitle)

$page = New-Object System.Windows.Forms.Panel
$page.Location = New-Object System.Drawing.Point(18, 98)
$page.Size = New-Object System.Drawing.Size(664, 370)
$page.BackColor = [System.Drawing.Color]::FromArgb(239, 242, 239)
$form.Controls.Add($page)

function Add-FieldLabel([string]$text, [int]$y) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $text
    $label.Location = New-Object System.Drawing.Point(20, $y)
    $label.Size = New-Object System.Drawing.Size(130, 26)
    $label.TextAlign = 'MiddleLeft'
    $label.ForeColor = [System.Drawing.Color]::FromArgb(38, 53, 49)
    $page.Controls.Add($label)
}

function Test-NeedsElevation([string]$Path) {
    $candidate = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $protectedRoots = @(
        [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles),
        [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFilesX86),
        [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($rootPath in $protectedRoots) {
        $rootFull = [IO.Path]::GetFullPath($rootPath).TrimEnd('\')
        if ($candidate.Equals($rootFull, [StringComparison]::OrdinalIgnoreCase) -or
            $candidate.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

Add-FieldLabel 'Game ISO' 20
$isoBox = New-Object System.Windows.Forms.TextBox
$isoBox.Location = New-Object System.Drawing.Point(152, 21)
$isoBox.Size = New-Object System.Drawing.Size(410, 25)
$page.Controls.Add($isoBox)
$isoBrowse = New-Object System.Windows.Forms.Button
$isoBrowse.Text = 'Browse...'
$isoBrowse.Location = New-Object System.Drawing.Point(570, 19)
$isoBrowse.Size = New-Object System.Drawing.Size(78, 29)
$isoBrowse.FlatStyle = 'Flat'
$isoBrowse.BackColor = [System.Drawing.Color]::FromArgb(0, 139, 105)
$isoBrowse.ForeColor = [System.Drawing.Color]::White
$page.Controls.Add($isoBrowse)
$isoBrowse.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = 'Xbox game images (*.iso)|*.iso|All files (*.*)|*.*'
    $dialog.Title = 'Select your legally obtained game ISO'
    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) { $isoBox.Text = $dialog.FileName }
})

Add-FieldLabel 'Install folder' 68
$destinationBox = New-Object System.Windows.Forms.TextBox
$destinationBox.Location = New-Object System.Drawing.Point(152, 69)
$destinationBox.Size = New-Object System.Drawing.Size(410, 25)
$destinationBox.Text = Join-Path $env:LOCALAPPDATA 'Programs\FIFA World Cup 2010'
$page.Controls.Add($destinationBox)
$destinationBrowse = New-Object System.Windows.Forms.Button
$destinationBrowse.Text = 'Browse...'
$destinationBrowse.Location = New-Object System.Drawing.Point(570, 67)
$destinationBrowse.Size = New-Object System.Drawing.Size(78, 29)
$destinationBrowse.FlatStyle = 'Flat'
$destinationBrowse.BackColor = [System.Drawing.Color]::FromArgb(0, 139, 105)
$destinationBrowse.ForeColor = [System.Drawing.Color]::White
$page.Controls.Add($destinationBrowse)
$destinationBrowse.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Choose the parent folder. Setup will create FIFA World Cup 2010 inside it.'
    $currentDestination = $destinationBox.Text.TrimEnd('\')
    if ([IO.Path]::GetFileName($currentDestination) -ieq 'FIFA World Cup 2010') {
        $dialog.SelectedPath = Split-Path -Parent $currentDestination
    } else {
        $dialog.SelectedPath = $currentDestination
    }
    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $selectedFolder = [IO.Path]::GetFullPath($dialog.SelectedPath)
        $selectedFolderName = [IO.Path]::GetFileName($selectedFolder.TrimEnd('\'))
        if ($selectedFolderName -ieq 'FIFA World Cup 2010') {
            $destinationBox.Text = $selectedFolder.TrimEnd('\')
        } else {
            $destinationBox.Text = Join-Path $selectedFolder 'FIFA World Cup 2010'
        }
    }
})

$notice = New-Object System.Windows.Forms.Label
$notice.Location = New-Object System.Drawing.Point(152, 108)
$notice.Size = New-Object System.Drawing.Size(490, 55)
$notice.ForeColor = [System.Drawing.Color]::FromArgb(76, 91, 83)
$notice.Text = 'Setup extracts the ISO and builds the PC port locally. LLVM and the ReXGlue source are included; Visual Studio C++ build tools are installed from Microsoft if missing. Several gigabytes of free space and an internet connection are required.'
$page.Controls.Add($notice)

$ownership = New-Object System.Windows.Forms.CheckBox
$ownership.Text = 'I own a legally obtained copy of the selected game.'
$ownership.Location = New-Object System.Drawing.Point(152, 170)
$ownership.Size = New-Object System.Drawing.Size(480, 26)
$ownership.ForeColor = [System.Drawing.Color]::FromArgb(38, 53, 49)
$page.Controls.Add($ownership)

$status = New-Object System.Windows.Forms.Label
$status.Text = 'Ready. The ISO and game data stay on this PC.'
$status.Location = New-Object System.Drawing.Point(20, 207)
$status.Size = New-Object System.Drawing.Size(620, 24)
$status.ForeColor = [System.Drawing.Color]::FromArgb(0, 111, 78)
$page.Controls.Add($status)

$log = New-Object System.Windows.Forms.TextBox
$log.Location = New-Object System.Drawing.Point(20, 236)
$log.Size = New-Object System.Drawing.Size(622, 118)
$log.Multiline = $true
$log.ReadOnly = $true
$log.ScrollBars = 'Vertical'
$log.Font = New-Object System.Drawing.Font('Consolas', 8)
$log.BackColor = [System.Drawing.Color]::White
$log.ForeColor = [System.Drawing.Color]::FromArgb(36, 47, 44)
$page.Controls.Add($log)

$installButton = New-Object System.Windows.Forms.Button
$installButton.Text = 'Install'
$installButton.Location = New-Object System.Drawing.Point(520, 482)
$installButton.Size = New-Object System.Drawing.Size(145, 42)
$installButton.FlatStyle = 'Flat'
$installButton.FlatAppearance.BorderSize = 0
$installButton.BackColor = [System.Drawing.Color]::FromArgb(0, 139, 105)
$installButton.ForeColor = [System.Drawing.Color]::White
$installButton.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($installButton)
$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = 'Close'
$cancelButton.Location = New-Object System.Drawing.Point(412, 482)
$cancelButton.Size = New-Object System.Drawing.Size(98, 42)
$cancelButton.FlatStyle = 'Flat'
$cancelButton.BackColor = [System.Drawing.Color]::FromArgb(48, 61, 62)
$cancelButton.ForeColor = [System.Drawing.Color]::WhiteSmoke
$cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$form.Controls.Add($cancelButton)
$form.CancelButton = $cancelButton

$script:workerProcess = $null
$script:workerLog = Join-Path $env:LOCALAPPDATA 'FWC10\setup.log'
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 600
$timer.Add_Tick({
    if (Test-Path -LiteralPath $script:workerLog) {
        try { $log.Lines = @(Get-Content -LiteralPath $script:workerLog -Tail 120); $log.SelectionStart = $log.TextLength; $log.ScrollToCaret() } catch {}
    }
    if ($script:workerProcess -and $script:workerProcess.HasExited) {
        $timer.Stop()
        $installButton.Enabled = $true
        $cancelButton.Enabled = $true
        if ($script:workerProcess.ExitCode -eq 0) {
            $status.Text = 'Installation complete.'
            $status.ForeColor = [System.Drawing.Color]::FromArgb(0, 111, 78)
            [System.Windows.Forms.MessageBox]::Show($form, 'The game was installed successfully. Start it with Settings.exe in the install folder.', 'Setup complete', 'OK', 'Information') | Out-Null
        } else {
            $status.Text = 'Setup did not complete. Review the log above.'
            $status.ForeColor = [System.Drawing.Color]::DarkRed
        }
        $script:workerProcess.Dispose()
        $script:workerProcess = $null
    }
})

$installButton.Add_Click({
    if (-not $ownership.Checked) {
        [System.Windows.Forms.MessageBox]::Show($form, 'Please confirm that you own a legally obtained copy of the game.', 'Confirmation required', 'OK', 'Warning') | Out-Null
        return
    }
    if (-not (Test-Path -LiteralPath $isoBox.Text -PathType Leaf) -or [IO.Path]::GetExtension($isoBox.Text) -ine '.iso') {
        [System.Windows.Forms.MessageBox]::Show($form, 'Select a valid ISO file first.', 'ISO required', 'OK', 'Warning') | Out-Null
        return
    }
    if (-not (Test-Path -LiteralPath $worker -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show($form, 'SetupWorker.ps1 is missing from this package.', 'Package incomplete', 'OK', 'Error') | Out-Null
        return
    }
    $destination = $destinationBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($destination)) { return }
    if (Test-Path -LiteralPath $destination -PathType Container) {
        $existingItems = @(Get-ChildItem -LiteralPath $destination -Force)
        $existingGameData = Join-Path $destination 'GameData'
        $unexpectedItems = @($existingItems | Where-Object { $_.Name -ine 'GameData' -and $_.Name -ine '.GameData-extracting' })
        $gameDataIsValid = -not (Test-Path -LiteralPath $existingGameData -PathType Container) -or
            ((Test-Path -LiteralPath (Join-Path $existingGameData 'default.xex') -PathType Leaf) -and
             (Test-Path -LiteralPath (Join-Path $existingGameData 'fifadllzf.xex') -PathType Leaf))
        if ($existingItems.Count -gt 0 -and ($unexpectedItems.Count -gt 0 -or -not $gameDataIsValid)) {
            [System.Windows.Forms.MessageBox]::Show($form, 'Choose an empty install folder, or a folder left by a previous interrupted setup (GameData or .GameData-extracting).', 'Folder is not empty', 'OK', 'Warning') | Out-Null
            return
        }
    }
    try {
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $script:workerLog))
        Set-Content -LiteralPath $script:workerLog -Value '' -Encoding UTF8
        $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $args = @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"{0}"' -f $worker),'-IsoPath',('"{0}"' -f $isoBox.Text),'-Destination',('"{0}"' -f $destination),'-PackageRoot',('"{0}"' -f $root),'-LogPath',('"{0}"' -f $script:workerLog))
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $powershell
        $psi.Arguments = $args -join ' '
        $psi.WorkingDirectory = $root
        $psi.UseShellExecute = Test-NeedsElevation $destination
        if ($psi.UseShellExecute) {
            $psi.Verb = 'runas'
            $status.Text = 'Windows will ask you to approve access to the protected install folder.'
        }
        $psi.CreateNoWindow = $true
        $script:workerProcess = [System.Diagnostics.Process]::Start($psi)
        $installButton.Enabled = $false
        $cancelButton.Enabled = $false
        $status.Text = 'Installing. Setup stays silent only briefly while it unpacks; the build can take a while.'
        $status.ForeColor = [System.Drawing.Color]::FromArgb(0, 111, 78)
        $timer.Start()
    } catch {
        [System.Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, 'Could not start setup', 'OK', 'Error') | Out-Null
    }
})

[void]$form.ShowDialog()
if ($script:workerProcess) { $script:workerProcess.Dispose() }
