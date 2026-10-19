[CmdletBinding()]
param(
    [string]$Output
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Output)) {
    $Output = Join-Path $repoRoot 'FIFA-World-Cup-2010-Setup-v0.3.3.exe'
}
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw "C# compiler not found: $compiler" }
$sdkSource = Join-Path $repoRoot 'ReXGlue'
if (-not (Test-Path -LiteralPath (Join-Path $sdkSource 'CMakeLists.txt') -PathType Leaf)) {
    throw "Pinned ReXGlue source tree is missing: $sdkSource"
}
$sdkHead = (& git.exe -C $sdkSource rev-parse HEAD 2>$null | Select-Object -First 1).Trim()
if ($sdkHead -ne 'c94f5ebdcb3c9d1a460ca48e04f9758448f8d518') {
    throw "Expected ReXGlue base commit c94f5ebdcb3c9d1a460ca48e04f9758448f8d518, found '$sdkHead'."
}

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

    Write-Host 'Preparing bundled ReXGlue source and Windows dependencies...'
    $sdkBundle = Join-Path $stage 'Installer\sdk-source'
    $robocopyArgs = @(
        $sdkSource, $sdkBundle, '/E', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/NP',
        '/XD', (Join-Path $sdkSource '.git'), (Join-Path $sdkSource 'out'), (Join-Path $sdkSource 'build'),
        '/XF', '.git'
    )
    & robocopy.exe @robocopyArgs | Out-Null
    if ($LASTEXITCODE -gt 7) { throw "Copying the ReXGlue source failed with robocopy code $LASTEXITCODE." }

    # This installer builds the Windows D3D12 backend. Skip unrelated Vulkan-only
    # and test-only submodules instead of cloning/fetching them on every install.
    foreach ($module in @('catch2','glslang','moltenvk','vulkan-loader','vulkan-headers','vulkan-memory-allocator','spirv-headers','spirv-tools')) {
        $unused = Join-Path $sdkBundle "thirdparty\$module"
        if (Test-Path -LiteralPath $unused) { Remove-Item -LiteralPath $unused -Recurse -Force }
    }
    foreach ($module in @('cli11','libmspack','FFmpeg','tomlplusplus','simde','xxHash','spdlog','fmt','utfcpp','imgui','sdl3','tracy')) {
        $moduleRoot = Join-Path $sdkBundle "thirdparty\$module"
        if (-not (Test-Path -LiteralPath $moduleRoot -PathType Container)) { throw "Required ReXGlue dependency is missing: $moduleRoot" }
        # ReXGlue's CMake checks .git to ensure submodules are present. This marker
        # preserves that check for a source snapshot without distributing Git metadata.
        Set-Content -LiteralPath (Join-Path $moduleRoot '.git') -Value 'Bundled source snapshot; Git metadata intentionally omitted.' -Encoding ASCII
    }
    $sdkArchive = Join-Path $stage 'Installer\sdk-source.zip'
    Compress-Archive -Path (Join-Path $sdkBundle '*') -DestinationPath $sdkArchive -CompressionLevel Optimal
    Remove-Item -LiteralPath $sdkBundle -Recurse -Force

    $llvmInstaller = Join-Path $env:LOCALAPPDATA 'FWC10\downloads\LLVM-20.1.8-win64.exe'
    if (-not (Test-Path -LiteralPath $llvmInstaller -PathType Leaf)) {
        $llvmInstaller = Join-Path $stage 'LLVM-20.1.8-win64.exe.download'
        Write-Host 'Downloading the pinned LLVM 20.1.8 installer for inclusion in the standalone setup...'
        Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/llvm/llvm-project/releases/download/llvmorg-20.1.8/LLVM-20.1.8-win64.exe' -OutFile $llvmInstaller
    }
    $llvmHash = (Get-FileHash -LiteralPath $llvmInstaller -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($llvmHash -ne '3197846a2b19063687dd56e93e34cd941e3548d907f23a6131571321bdf9fe7b') {
        throw 'The LLVM installer failed its SHA-256 check; refusing to bundle it.'
    }
    $llvmTarget = Join-Path $stage 'Installer\tools\LLVM-20.1.8-win64.exe'
    Copy-Item -LiteralPath $llvmInstaller -Destination $llvmTarget -Force
    $llvmLicense = Join-Path $repoRoot 'Installer\LLVM-LICENSE.txt'
    if (Test-Path -LiteralPath $llvmLicense -PathType Leaf) {
        Copy-Item -LiteralPath $llvmLicense -Destination (Join-Path $stage 'Installer\tools\LLVM-LICENSE.txt') -Force
    }

    $payload = Join-Path $stage 'payload.zip'
    # Large LLVM and SDK archives are already compressed; avoid recompressing
    # hundreds of megabytes when creating the final self-extracting executable.
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $payload -CompressionLevel NoCompression
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
