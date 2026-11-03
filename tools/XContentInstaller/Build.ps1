[CmdletBinding()]
param(
    # Where to write the executable. Defaults to tools\XContentInstaller\bin\InstallDLC.exe.
    [string]$Output
)

# Builds InstallDLC.exe with the C# compiler that ships with Windows (.NET Framework 4.x).
# No Visual Studio, SDK or download is required.

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $here)
if ([string]::IsNullOrWhiteSpace($Output)) { $Output = Join-Path $here 'bin\InstallDLC.exe' }

$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
}
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw "C# compiler not found: $compiler" }

$icon = Join-Path $repoRoot 'icons\game_logo.ico'
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $Output))

$arguments = @(
    '/nologo', '/target:winexe', '/optimize+', '/platform:anycpu',
    '/reference:System.dll', '/reference:System.Drawing.dll', '/reference:System.Windows.Forms.dll',
    "/out:$Output"
)
if (Test-Path -LiteralPath $icon -PathType Leaf) { $arguments += "/win32icon:$icon" }
$arguments += (Join-Path $here 'XContentInstaller.cs')

& $compiler @arguments
if ($LASTEXITCODE -ne 0) { throw "csc.exe failed with exit code $LASTEXITCODE" }
Write-Host "Built $Output"
