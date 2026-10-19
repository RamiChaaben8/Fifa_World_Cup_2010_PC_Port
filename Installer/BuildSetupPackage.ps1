[CmdletBinding()]
param(
    [string]$Output
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Output)) {
    $Output = Join-Path $repoRoot 'FIFA-World-Cup-2010-Setup-v0.3.1.exe'
}
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw "C# compiler not found: $compiler" }

$required = @(
    'Installer\Setup.ps1',
    'Installer\SetupWorker.ps1',
    'Installer\BuildWorldCup2010.ps1',
    'Installer\BuildIntegrity.ps1',
    'Installer\InstallSourceBackend.ps1',
    'Installer\recomp-template\worldcup2010_manifest.toml',
    'Installer\recomp-template\CMakeLists.txt',
    'Installer\tools\extract-xiso.exe',
    'Installer\tools\vcruntime140.dll',
    'Installer\EXTRACT-XISO-NOTICE.txt',
    'Installer\SetupExe.cs',
    'Launcher.ps1',
    'Settings.exe',
    'icons\game_logo.png',
    'icons\game_logo.ico',
    'patches\rexglue-v0.3-local.patch',
    'patches\rexglue-libmspack-v0.3.patch'
)
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $relative) -PathType Leaf)) {
        throw "Setup package input is missing: $relative"
    }
}

$stage = Join-Path $env:TEMP ('fwc10-setup-v03-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($stage)
try {
    $copyPaths = @(
        'Installer', 'patches\rexglue-v0.3-local.patch', 'patches\rexglue-libmspack-v0.3.patch', 'Launcher.ps1',
        'Settings.exe', 'icons', 'README.md', 'LICENSE'
    )
    foreach ($relative in $copyPaths) {
        $source = Join-Path $repoRoot $relative
        $target = Join-Path $stage $relative
        if (Test-Path -LiteralPath $source -PathType Container) {
            Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
        } else {
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
            Copy-Item -LiteralPath $source -Destination $target -Force
        }
    }

    $payload = Join-Path $stage 'payload.zip'
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $payload -CompressionLevel Optimal
    $setupExe = Join-Path $stage 'FIFA-World-Cup-2010-Setup.exe'
    $compilerArguments = @(
        '/nologo', '/target:winexe', '/optimize+',
        ('/win32icon:' + (Join-Path $repoRoot 'icons\game_logo.ico')),
        ('/out:' + $setupExe),
        '/reference:System.dll', '/reference:System.Windows.Forms.dll',
        '/reference:System.IO.Compression.dll',
        ('/resource:' + $payload + ',FWC10.Payload.zip'),
        (Join-Path $PSScriptRoot 'SetupExe.cs')
    )
    & $compiler @compilerArguments
    if ($LASTEXITCODE -ne 0) { throw "Setup.exe compilation failed with code $LASTEXITCODE." }

    $Output = [IO.Path]::GetFullPath($Output)
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Output))
    if (Test-Path -LiteralPath $Output) { throw "Output already exists; move it or choose a new path: $Output" }
    Copy-Item -LiteralPath $setupExe -Destination $Output
    Get-Item -LiteralPath $Output | Select-Object FullName, Length
} finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}
