[CmdletBinding()]
param(
    [switch]$ListModes
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ('Fwc10WindowIcon' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Fwc10WindowIcon {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    private static extern IntPtr SendMessage(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
    public static void SetApplicationId() {
        SetCurrentProcessExplicitAppUserModelID("FWC10.WorldCup2010.Settings");
    }
    public static void Set(IntPtr hWnd, IntPtr hIcon) {
        SendMessage(hWnd, 0x0080, IntPtr.Zero, hIcon);
        SendMessage(hWnd, 0x0080, new IntPtr(1), hIcon);
    }
}
'@
}

if (-not ('Fwc10DisplayModes' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class Fwc10DisplayModes {
    private const int ENUM_CURRENT_SETTINGS = -1;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;
        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);

    public sealed class Mode {
        public int Width { get; set; }
        public int Height { get; set; }
        public int Refresh { get; set; }
        public int BitsPerPixel { get; set; }
    }

    private static DEVMODE CreateMode() {
        DEVMODE mode = new DEVMODE();
        mode.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        return mode;
    }

    public static Mode GetCurrent(string deviceName) {
        DEVMODE mode = CreateMode();
        if (!EnumDisplaySettings(deviceName, ENUM_CURRENT_SETTINGS, ref mode)) return null;
        return new Mode { Width = mode.dmPelsWidth, Height = mode.dmPelsHeight,
                          Refresh = mode.dmDisplayFrequency, BitsPerPixel = mode.dmBitsPerPel };
    }

    public static List<Mode> GetAll(string deviceName) {
        List<Mode> modes = new List<Mode>();
        for (int i = 0; i < 10000; ++i) {
            DEVMODE mode = CreateMode();
            if (!EnumDisplaySettings(deviceName, i, ref mode)) break;
            if (mode.dmPelsWidth < 640 || mode.dmPelsWidth > 4095 ||
                mode.dmPelsHeight < 480 || mode.dmPelsHeight > 4095 ||
                mode.dmBitsPerPel < 24 || mode.dmDisplayFrequency < 24 ||
                mode.dmDisplayFrequency > 240) continue;
            modes.Add(new Mode { Width = mode.dmPelsWidth, Height = mode.dmPelsHeight,
                                 Refresh = mode.dmDisplayFrequency, BitsPerPixel = mode.dmBitsPerPel });
        }
        return modes;
    }
}
'@
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$exeCandidates = @(
    (Join-Path $scriptRoot 'dist\Output\worldcup2010.exe'),
    (Join-Path $scriptRoot 'worldcup2010.exe'),
    (Join-Path $scriptRoot 'Output\worldcup2010.exe')
)
$defaultExe = $exeCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
$settingsPath = Join-Path $env:LOCALAPPDATA 'FWC10\launcher-settings.json'

$screens = @([System.Windows.Forms.Screen]::AllScreens | Sort-Object { $_.DeviceName })
$modeMap = @{}
$currentMap = @{}
foreach ($screen in $screens) {
    $modeMap[$screen.DeviceName] = [Fwc10DisplayModes]::GetAll($screen.DeviceName)
    $currentMap[$screen.DeviceName] = [Fwc10DisplayModes]::GetCurrent($screen.DeviceName)
}

if ($ListModes) {
    foreach ($screen in $screens) {
        $current = $currentMap[$screen.DeviceName]
        Write-Output ("{0}{1}: current {2}x{3} @ {4} Hz" -f $screen.DeviceName,
            $(if ($screen.Primary) { ' (primary)' } else { '' }), $current.Width, $current.Height, $current.Refresh)
        $modeMap[$screen.DeviceName] |
            Sort-Object Width, Height, Refresh -Unique |
            ForEach-Object { Write-Output ("  {0}x{1} @ {2} Hz" -f $_.Width, $_.Height, $_.Refresh) }
    }
    return
}

$saved = $null
if (Test-Path -LiteralPath $settingsPath) {
    try { $saved = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json } catch { $saved = $null }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Settings - 2010 FIFA World Cup'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size(700, 540)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.BackColor = [System.Drawing.Color]::FromArgb(22, 31, 37)
$form.ForeColor = [System.Drawing.Color]::FromArgb(239, 240, 232)
$logoIconPath = Join-Path $scriptRoot 'icons\game_logo.ico'
if (Test-Path -LiteralPath $logoIconPath -PathType Leaf) {
    $form.Icon = New-Object System.Drawing.Icon($logoIconPath)
    $form.ShowIcon = $true
    $form.ShowInTaskbar = $true
    [Fwc10WindowIcon]::SetApplicationId()
    $form.Add_Shown({
        if ($form.Icon) { [Fwc10WindowIcon]::Set($form.Handle, $form.Icon.Handle) }
    })
}

$header = New-Object System.Windows.Forms.Panel
$header.Location = New-Object System.Drawing.Point(0, 0)
$header.Size = New-Object System.Drawing.Size(700, 72)
$header.BackColor = [System.Drawing.Color]::FromArgb(0, 139, 132)
$form.Controls.Add($header)
$header.Add_Paint({
    param($sender, $eventArgs)
    $g = $eventArgs.Graphics
    $rect = New-Object System.Drawing.Rectangle(0, 0, $sender.Width, $sender.Height)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect,
        [System.Drawing.Color]::FromArgb(0, 174, 157),
        [System.Drawing.Color]::FromArgb(22, 72, 88), 0)
    $g.FillRectangle($brush, $rect)
    $brush.Dispose()
    $gold = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(235, 183, 55))
    $points = [System.Drawing.Point[]]@(
        (New-Object System.Drawing.Point(580, 0)),
        (New-Object System.Drawing.Point(700, 0)),
        (New-Object System.Drawing.Point(700, 72)),
        (New-Object System.Drawing.Point(630, 72)))
    $g.FillPolygon($gold, $points)
    $gold.Dispose()
})
$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = 'GAME SETTINGS'
$titleLabel.Location = New-Object System.Drawing.Point(23, 8)
$titleLabel.Size = New-Object System.Drawing.Size(520, 37)
$titleLabel.Font = New-Object System.Drawing.Font('Segoe UI', 21, [System.Drawing.FontStyle]::Bold)
$titleLabel.ForeColor = [System.Drawing.Color]::White
$titleLabel.BackColor = [System.Drawing.Color]::Transparent
$header.Controls.Add($titleLabel)
$subtitleLabel = New-Object System.Windows.Forms.Label
$subtitleLabel.Text = 'SOUTH AFRICA 2010  |  PC EDITION'
$subtitleLabel.Location = New-Object System.Drawing.Point(27, 46)
$subtitleLabel.Size = New-Object System.Drawing.Size(400, 20)
$subtitleLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$subtitleLabel.ForeColor = [System.Drawing.Color]::FromArgb(245, 221, 157)
$subtitleLabel.BackColor = [System.Drawing.Color]::Transparent
$header.Controls.Add($subtitleLabel)
$logoPath = Join-Path $scriptRoot 'icons\game_logo.png'
if (Test-Path -LiteralPath $logoPath -PathType Leaf) {
    $logoBox = New-Object System.Windows.Forms.PictureBox
    $logoBox.Location = New-Object System.Drawing.Point(626, 5)
    $logoBox.Size = New-Object System.Drawing.Size(66, 62)
    $logoBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    $logoBox.BackColor = [System.Drawing.Color]::Transparent
    $logoBox.Image = [System.Drawing.Image]::FromFile($logoPath)
    $header.Controls.Add($logoBox)
}

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(18, 82)
$tabs.Size = New-Object System.Drawing.Size(664, 365)
$tabs.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$settingsTab = New-Object System.Windows.Forms.TabPage
$settingsTab.Text = 'Display'
$settingsTab.BackColor = [System.Drawing.Color]::FromArgb(237, 240, 237)
$aboutTab = New-Object System.Windows.Forms.TabPage
$aboutTab.Text = 'About'
$aboutTab.BackColor = [System.Drawing.Color]::FromArgb(237, 240, 237)
[void]$tabs.TabPages.Add($settingsTab)
[void]$tabs.TabPages.Add($aboutTab)
$form.Controls.Add($tabs)
$aboutText = New-Object System.Windows.Forms.Label
$aboutText.Text = "2010 FIFA World Cup South Africa`r`n`r`nChoose your display, screen mode, resolution, and refresh rate before starting the game.`r`n`r`nThe launcher saves your last-used settings on this PC."
$aboutText.Location = New-Object System.Drawing.Point(28, 24)
$aboutText.Size = New-Object System.Drawing.Size(590, 130)
$aboutText.Font = New-Object System.Drawing.Font('Segoe UI', 11)
$aboutText.ForeColor = [System.Drawing.Color]::FromArgb(35, 48, 48)
$aboutTab.Controls.Add($aboutText)

function Add-RowLabel([string]$text, [int]$top) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $text
    $label.Location = New-Object System.Drawing.Point(22, $top)
    $label.Size = New-Object System.Drawing.Size(135, 28)
    $label.TextAlign = 'MiddleLeft'
    $label.ForeColor = [System.Drawing.Color]::FromArgb(39, 52, 49)
    $settingsTab.Controls.Add($label)
    return $label
}

$exeBox = New-Object System.Windows.Forms.TextBox
$exeBox.Location = New-Object System.Drawing.Point(160, 22)
$exeBox.Size = New-Object System.Drawing.Size(420, 25)
$exeBox.BackColor = [System.Drawing.Color]::White
$exeBox.ForeColor = [System.Drawing.Color]::FromArgb(35, 48, 48)
$exeBox.Text = if ($saved -and $saved.GameExe -and (Test-Path -LiteralPath $saved.GameExe)) { $saved.GameExe } else { $defaultExe }
$settingsTab.Controls.Add($exeBox)

$browseButton = New-Object System.Windows.Forms.Button
$browseButton.Text = 'Browse...'
$browseButton.Location = New-Object System.Drawing.Point(588, 20)
$browseButton.Size = New-Object System.Drawing.Size(58, 28)
$browseButton.FlatStyle = 'Flat'
$browseButton.BackColor = [System.Drawing.Color]::FromArgb(0, 139, 105)
$browseButton.ForeColor = [System.Drawing.Color]::White
$settingsTab.Controls.Add($browseButton)
$browseButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = 'World Cup game (worldcup2010.exe)|worldcup2010.exe|Applications (*.exe)|*.exe'
    $dialog.Title = 'Select the game executable'
    if (Test-Path -LiteralPath $exeBox.Text -PathType Leaf) { $dialog.FileName = $exeBox.Text }
    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) { $exeBox.Text = $dialog.FileName }
})

Add-RowLabel 'Game executable' 22 | Out-Null
Add-RowLabel 'Display' 68 | Out-Null
Add-RowLabel 'Display mode' 114 | Out-Null
Add-RowLabel 'Resolution' 160 | Out-Null
Add-RowLabel 'Refresh rate' 206 | Out-Null

$displayCombo = New-Object System.Windows.Forms.ComboBox
$displayCombo.DropDownStyle = 'DropDownList'
$displayCombo.Location = New-Object System.Drawing.Point(160, 66)
$displayCombo.Size = New-Object System.Drawing.Size(486, 26)
foreach ($screen in $screens) {
    $current = $currentMap[$screen.DeviceName]
    $item = [pscustomobject]@{
        Device = $screen.DeviceName
        Label = '{0} — {1}x{2}{3}' -f $screen.DeviceName, $current.Width, $current.Height,
            $(if ($screen.Primary) { ' (Primary)' } else { '' })
    }
    [void]$displayCombo.Items.Add($item)
}
$displayCombo.DisplayMember = 'Label'
$settingsTab.Controls.Add($displayCombo)

$modeCombo = New-Object System.Windows.Forms.ComboBox
$modeCombo.DropDownStyle = 'DropDownList'
$modeCombo.Location = New-Object System.Drawing.Point(160, 112)
$modeCombo.Size = New-Object System.Drawing.Size(486, 26)
@(
    [pscustomobject]@{ Key = 'Exclusive'; Label = 'Exclusive fullscreen — apply selected refresh rate' },
    [pscustomobject]@{ Key = 'Borderless'; Label = 'Borderless fullscreen — use desktop refresh rate' },
    [pscustomobject]@{ Key = 'Windowed'; Label = 'Windowed — use desktop refresh rate' }
) | ForEach-Object { [void]$modeCombo.Items.Add($_) }
$modeCombo.DisplayMember = 'Label'
$settingsTab.Controls.Add($modeCombo)

$resolutionCombo = New-Object System.Windows.Forms.ComboBox
$resolutionCombo.DropDownStyle = 'DropDownList'
$resolutionCombo.Location = New-Object System.Drawing.Point(160, 158)
$resolutionCombo.Size = New-Object System.Drawing.Size(486, 26)
$resolutionCombo.DisplayMember = 'Label'
$settingsTab.Controls.Add($resolutionCombo)

$refreshCombo = New-Object System.Windows.Forms.ComboBox
$refreshCombo.DropDownStyle = 'DropDownList'
$refreshCombo.Location = New-Object System.Drawing.Point(160, 204)
$refreshCombo.Size = New-Object System.Drawing.Size(185, 26)
$settingsTab.Controls.Add($refreshCombo)
foreach ($combo in @($displayCombo, $modeCombo, $resolutionCombo, $refreshCombo)) {
    $combo.BackColor = [System.Drawing.Color]::White
    $combo.ForeColor = [System.Drawing.Color]::FromArgb(35, 48, 48)
}

$helpLabel = New-Object System.Windows.Forms.Label
$helpLabel.Location = New-Object System.Drawing.Point(160, 246)
$helpLabel.Size = New-Object System.Drawing.Size(486, 54)
$helpLabel.ForeColor = [System.Drawing.Color]::FromArgb(83, 99, 91)
$helpLabel.Text = '4K (3840x2160) is available when supported by the game/display mode. Exclusive refresh options come from Windows display modes; borderless and windowed modes keep the desktop refresh rate.'
$settingsTab.Controls.Add($helpLabel)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(22, 304)
$statusLabel.Size = New-Object System.Drawing.Size(620, 28)
$statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 111, 78)
$settingsTab.Controls.Add($statusLabel)

$launchButton = New-Object System.Windows.Forms.Button
$launchButton.Text = 'Start Game'
$launchButton.Location = New-Object System.Drawing.Point(510, 458)
$launchButton.Size = New-Object System.Drawing.Size(145, 42)
$launchButton.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$launchButton.FlatStyle = 'Flat'
$launchButton.FlatAppearance.BorderSize = 0
$launchButton.BackColor = [System.Drawing.Color]::FromArgb(0, 139, 105)
$launchButton.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($launchButton)
$form.AcceptButton = $launchButton

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = 'Cancel'
$cancelButton.Location = New-Object System.Drawing.Point(402, 458)
$cancelButton.Size = New-Object System.Drawing.Size(98, 42)
$cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$cancelButton.FlatStyle = 'Flat'
$cancelButton.BackColor = [System.Drawing.Color]::FromArgb(48, 58, 61)
$cancelButton.ForeColor = [System.Drawing.Color]::WhiteSmoke
$form.Controls.Add($cancelButton)
$form.CancelButton = $cancelButton

$resolutionHandler = {
    $oldKey = $null
    if ($resolutionCombo.SelectedItem) { $oldKey = $resolutionCombo.SelectedItem.Key }
    $resolutionCombo.Items.Clear()

    $dims = @{}
    foreach ($pair in @(@(1280,720), @(1600,900), @(1920,1080), @(2560,1440), @(3200,1800), @(3840,2160))) {
        $dims[('{0}x{1}' -f $pair[0], $pair[1])] = $true
    }
    if ($displayCombo.SelectedItem) {
        foreach ($m in $modeMap[$displayCombo.SelectedItem.Device]) {
            $dims[('{0}x{1}' -f $m.Width, $m.Height)] = $true
        }
    }
    $ordered = $dims.Keys | ForEach-Object {
        $p = $_.Split('x'); [pscustomobject]@{ Key = $_; Width = [int]$p[0]; Height = [int]$p[1] }
    } | Sort-Object { $_.Width * $_.Height }, Width, Height
    foreach ($d in $ordered) {
        $suffix = switch ($d.Key) {
            '1280x720' { ' (720p)' }
            '1600x900' { ' (900p)' }
            '1920x1080' { ' (1080p)' }
            '2560x1440' { ' (1440p)' }
            '3200x1800' { ' (1800p)' }
            '3840x2160' { ' (4K / 2160p)' }
            default { '' }
        }
        [void]$resolutionCombo.Items.Add([pscustomobject]@{
            Key = $d.Key; Width = $d.Width; Height = $d.Height
            Label = ('{0}x{1}{2}' -f $d.Width, $d.Height, $suffix)
        })
    }
    $desiredKey = if ($saved -and $saved.Resolution) { [string]$saved.Resolution } else { '1280x720' }
    $selectedIndex = -1
    for ($i = 0; $i -lt $resolutionCombo.Items.Count; $i++) {
        if ($resolutionCombo.Items[$i].Key -eq $desiredKey) { $selectedIndex = $i; break }
    }
    if ($selectedIndex -lt 0 -and $oldKey) {
        for ($i = 0; $i -lt $resolutionCombo.Items.Count; $i++) {
            if ($resolutionCombo.Items[$i].Key -eq $oldKey) { $selectedIndex = $i; break }
        }
    }
    if ($selectedIndex -lt 0 -and $resolutionCombo.Items.Count -gt 0) { $selectedIndex = 0 }
    if ($selectedIndex -ge 0) { $resolutionCombo.SelectedIndex = $selectedIndex }
}.GetNewClosure()

$refreshHandler = {
    $refreshCombo.Items.Clear()
    $refreshCombo.Enabled = $false
    $launchButton.Enabled = $true
    $statusLabel.ForeColor = [System.Drawing.Color]::DarkSlateGray

    if (-not $displayCombo.SelectedItem -or -not $resolutionCombo.SelectedItem -or -not $modeCombo.SelectedItem) { return }
    $device = $displayCombo.SelectedItem.Device
    $width = $resolutionCombo.SelectedItem.Width
    $height = $resolutionCombo.SelectedItem.Height
    $current = $currentMap[$device]

    if ($modeCombo.SelectedItem.Key -eq 'Exclusive') {
        $rates = @($modeMap[$device] | Where-Object { $_.Width -eq $width -and $_.Height -eq $height } |
            Select-Object -ExpandProperty Refresh -Unique | Sort-Object)
        if ($rates.Count -eq 0) {
            $refreshCombo.Items.Add('No supported exclusive mode') | Out-Null
            $refreshCombo.SelectedIndex = 0
            $statusLabel.Text = 'This display does not report the selected resolution as an exclusive mode. Choose another resolution or Borderless.'
            $statusLabel.ForeColor = [System.Drawing.Color]::DarkRed
            $launchButton.Enabled = $false
            return
        }
        $refreshCombo.Enabled = $true
        foreach ($rate in $rates) { [void]$refreshCombo.Items.Add([pscustomobject]@{ Rate = [int]$rate; Label = ('{0} Hz' -f $rate) }) }
        $refreshCombo.DisplayMember = 'Label'
        $wanted = if ($saved -and $saved.RefreshRate) { [int]$saved.RefreshRate } else { [int]$current.Refresh }
        $idx = -1
        for ($i = 0; $i -lt $refreshCombo.Items.Count; $i++) { if ($refreshCombo.Items[$i].Rate -eq $wanted) { $idx = $i; break } }
        if ($idx -lt 0) {
            for ($i = 0; $i -lt $refreshCombo.Items.Count; $i++) { if ($refreshCombo.Items[$i].Rate -eq [int]$current.Refresh) { $idx = $i; break } }
        }
        if ($idx -lt 0) { $idx = 0 }
        $refreshCombo.SelectedIndex = $idx
        $statusLabel.Text = 'Exclusive refresh will be requested from D3D12. If the driver rejects the mode, the game remains borderless.'
    } else {
        $desktopRate = if ($current) { [int]$current.Refresh } else { 60 }
        [void]$refreshCombo.Items.Add([pscustomobject]@{ Rate = $desktopRate; Label = ('Desktop refresh ({0} Hz)' -f $desktopRate) })
        $refreshCombo.DisplayMember = 'Label'
        $refreshCombo.SelectedIndex = 0
        $statusLabel.Text = 'Borderless and windowed modes use the desktop refresh rate. Choose Exclusive fullscreen to request a different rate.'
    }
}.GetNewClosure()

$displayCombo.Add_SelectedIndexChanged($resolutionHandler)
$displayCombo.Add_SelectedIndexChanged($refreshHandler)
$resolutionCombo.Add_SelectedIndexChanged($refreshHandler)
$modeCombo.Add_SelectedIndexChanged($refreshHandler)

if ($displayCombo.Items.Count -gt 0) {
    $wantedDevice = if ($saved -and $saved.DisplayDevice) { [string]$saved.DisplayDevice } else { ($screens | Where-Object Primary | Select-Object -First 1).DeviceName }
    $idx = -1
    for ($i = 0; $i -lt $displayCombo.Items.Count; $i++) { if ($displayCombo.Items[$i].Device -eq $wantedDevice) { $idx = $i; break } }
    if ($idx -lt 0) { $idx = 0 }
    $displayCombo.SelectedIndex = $idx
}
$resolutionHandler.Invoke()
$modeWanted = if ($saved -and $saved.DisplayMode) { [string]$saved.DisplayMode } else { 'Exclusive' }
$modeIndex = 0
for ($i = 0; $i -lt $modeCombo.Items.Count; $i++) { if ($modeCombo.Items[$i].Key -eq $modeWanted) { $modeIndex = $i; break } }
$modeCombo.SelectedIndex = $modeIndex
$refreshHandler.Invoke()

$launchButton.Add_Click({
    $exe = $exeBox.Text.Trim()
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show($form, 'Select a valid worldcup2010.exe first.', 'Game not found', 'OK', 'Warning') | Out-Null
        return
    }
    if ([IO.Path]::GetFileName($exe) -ine 'worldcup2010.exe') {
        $answer = [System.Windows.Forms.MessageBox]::Show($form, 'The selected file is not named worldcup2010.exe. Launch it anyway?', 'Confirm executable', 'YesNo', 'Question')
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    }
    $processName = [IO.Path]::GetFileNameWithoutExtension($exe)
    if (Get-Process -Name $processName -ErrorAction SilentlyContinue) {
        [System.Windows.Forms.MessageBox]::Show($form, 'The game is already running. Close it before applying new display settings.', 'Game already running', 'OK', 'Information') | Out-Null
        return
    }
    if (-not $displayCombo.SelectedItem -or -not $resolutionCombo.SelectedItem -or -not $modeCombo.SelectedItem -or -not $refreshCombo.SelectedItem) { return }

    $width = [int]$resolutionCombo.SelectedItem.Width
    $height = [int]$resolutionCombo.SelectedItem.Height
    $rate = [int]$refreshCombo.SelectedItem.Rate
    $modeKey = [string]$modeCombo.SelectedItem.Key
    $fullscreen = $modeKey -ne 'Windowed'
    $exclusive = $modeKey -eq 'Exclusive'
    $device = [string]$displayCombo.SelectedItem.Device

    try {
        $settingsDir = Split-Path -Parent $settingsPath
        [void][IO.Directory]::CreateDirectory($settingsDir)
        [pscustomobject]@{
            GameExe = $exe; DisplayDevice = $device; Resolution = ('{0}x{1}' -f $width, $height)
            RefreshRate = $rate; DisplayMode = $modeKey
        } | ConvertTo-Json | Set-Content -LiteralPath $settingsPath -Encoding UTF8

        $argList = @(
            ('--resolution={0}x{1}' -f $width, $height),
            ('--video_mode_width={0}' -f $width),
            ('--video_mode_height={0}' -f $height),
            ('--window_width={0}' -f $width),
            ('--window_height={0}' -f $height),
            ('--video_mode_refresh_rate={0}' -f $rate),
            ('--fullscreen={0}' -f $fullscreen.ToString().ToLowerInvariant()),
            ('--true_vsync={0}' -f $exclusive.ToString().ToLowerInvariant()),
            ('--launcher_monitor_device={0}' -f $device)
        )
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $exe
        $psi.WorkingDirectory = Split-Path -Parent $exe
        $psi.Arguments = $argList -join ' '
        $psi.UseShellExecute = $false
        $psi.EnvironmentVariables['REX_FULLSCREEN'] = $fullscreen.ToString().ToLowerInvariant()
        $psi.EnvironmentVariables['REX_TRUE_VSYNC_EXCLUSIVE'] = if ($exclusive) { '1' } else { '0' }
        $psi.EnvironmentVariables['REX_VIDEO_MODE_REFRESH_RATE'] = [string]$rate
        $psi.EnvironmentVariables['REX_TRUE_VSYNC'] = '0'
        $psi.EnvironmentVariables.Remove('REX_TRUE_VSYNC_FPS')
        $psi.EnvironmentVariables.Remove('REX_TRUE_VSYNC_MODE')
        $script:launchedGameProcess = [System.Diagnostics.Process]::Start($psi)
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    } catch {
        [System.Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, 'Could not start the game', 'OK', 'Error') | Out-Null
    }
}.GetNewClosure())

if ($screens.Count -eq 0) {
    [System.Windows.Forms.MessageBox]::Show('Windows did not report any displays.', 'Display enumeration failed', 'OK', 'Error') | Out-Null
    return
}
[void]$form.ShowDialog()
if ($script:launchedGameProcess) {
    $gameIcon = $null
    try {
        if (Test-Path -LiteralPath $logoIconPath -PathType Leaf) {
            $gameIcon = New-Object System.Drawing.Icon($logoIconPath)
            for ($attempt = 0; $attempt -lt 60 -and -not $script:launchedGameProcess.HasExited; $attempt++) {
                $script:launchedGameProcess.Refresh()
                $gameWindow = $script:launchedGameProcess.MainWindowHandle
                if ($gameWindow -ne [IntPtr]::Zero) {
                    [Fwc10WindowIcon]::Set($gameWindow, $gameIcon.Handle)
                    break
                }
                Start-Sleep -Milliseconds 250
            }
        }
        $script:launchedGameProcess.WaitForExit()
    } catch {
        # Applying a window icon is best-effort; never interfere with game startup or shutdown.
    } finally {
        if ($gameIcon) { $gameIcon.Dispose() }
        $script:launchedGameProcess.Dispose()
        $script:launchedGameProcess = $null
    }
}
