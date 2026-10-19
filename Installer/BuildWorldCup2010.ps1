param(
    [Parameter(Mandatory = $true)]
    [string]$GameData,

    [Parameter(Mandatory = $true)]
    [string]$Output,

    [string]$Workspace,

    [switch]$SourceBuild,

    [ValidateSet('D3D12', 'Vulkan')]
    [string]$GraphicsApi = 'D3D12',

    [ValidateRange(1, 64)]
    [int]$Jobs = 2
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

function Invoke-BuildTool {
    param([string]$Tool, [string[]]$Arguments)
    $ErrorActionPreference = 'Continue'
    $nativeLog = $logPath + '.native'
    $writer = [IO.StreamWriter]::new($nativeLog, $true, [Text.UTF8Encoding]::new($false))
    try {
        $writer.WriteLine("$Tool " + ($Arguments -join ' '))
        & $Tool @Arguments 2>&1 | ForEach-Object {
            $line = if ($_ -is [Management.Automation.ErrorRecord]) { $_.Exception.Message } else { [string]$_ }
            $writer.WriteLine($line)
            if ($line -match '^\[\d+|^\s*(start|phase|done)\s|FAILED:|fatal error:|error:|^Failed:|Codegen summary:|^Done in') {
                Write-Host $line
            }
        }
        $exitCode = $LASTEXITCODE
    }
    finally { $writer.Dispose() }
    if ($exitCode -ne 0) { throw "$Tool failed with code $exitCode. Full log: $nativeLog" }
}

$installerRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $installerRoot "BuildIntegrity.ps1")

$template = Join-Path $installerRoot "recomp-template"

$rexGlueSource = if ($env:REXSDK_DIR) { [IO.Path]::GetFullPath($env:REXSDK_DIR) } else {
    Join-Path (Split-Path $installerRoot -Parent) "ReXGlue"
}

$bundledSdk = Join-Path $installerRoot 'sdk'
$bundledTools = Join-Path $installerRoot 'compiler'
$useBundledSdk = !$SourceBuild -and (Test-Path -LiteralPath (Join-Path $bundledSdk 'bin\rexglue.exe'))
$llvmBin = if ($env:FWC10_LLVM_BIN) { [IO.Path]::GetFullPath($env:FWC10_LLVM_BIN) } elseif (Test-Path -LiteralPath $bundledTools) { Join-Path $bundledTools 'bin' } else { "C:\Program Files\LLVM\bin" }

$clang = Join-Path $llvmBin "clang.exe"
$clangxx = Join-Path $llvmBin "clang++.exe"

if (!(Test-Path $clang)) {
    throw "clang.exe not found at $clang"
}

if (!(Test-Path $clangxx)) {
    throw "clang++.exe not found at $clangxx"
}

$env:PATH = "$llvmBin;$env:PATH"
if ($useBundledSdk) { $env:PATH = "$(Join-Path $bundledSdk 'bin');$env:PATH" }

$shortTempRoot = if ($env:FWC10_BUILD_ROOT) { $env:FWC10_BUILD_ROOT } else { "C:\FWC10B" }

if (!(Test-Path $shortTempRoot)) {
    New-Item -ItemType Directory -Path $shortTempRoot -Force | Out-Null
}

$resume = ![string]::IsNullOrWhiteSpace($Workspace)
$workRoot = if ($resume) { [IO.Path]::GetFullPath($Workspace) } else {
    Join-Path $shortTempRoot ([guid]::NewGuid().ToString("N").Substring(0, 8))
}

$workProject = Join-Path $workRoot "WorldCup2010Rex"
if ($resume -and !(Test-Path -LiteralPath (Join-Path $workProject 'CMakeLists.txt'))) {
    throw "Invalid build workspace: $workRoot"
}
$GameData = [IO.Path]::GetFullPath($GameData)
$Output = [IO.Path]::GetFullPath($Output)

Write-Host ""
Write-Host "=============================================="
Write-Host " 2010 FIFA World Cup PC - Recomp Build"
Write-Host "=============================================="
Write-Host ""

if (!(Test-Path $GameData)) {
    throw "GameData does not exist: $GameData"
}

$defaultXex = Join-Path $GameData "default.xex"
$fifaDll = Join-Path $GameData "fifadllzf.xex"

if (!(Test-Path $defaultXex)) {
    throw "default.xex was not found in $GameData"
}

if (!(Test-Path $fifaDll)) {
    throw "fifadllzf.xex was not found in $GameData"
}

if (!(Test-Path $template)) {
    throw "recomp-template was not found: $template"
}

if (!$useBundledSdk -and !(Test-Path $rexGlueSource)) {
    throw "ReXGlue source was not found: $rexGlueSource"
}

Write-Host "[1/6] Preparing temporary workspace..."

New-Item -ItemType Directory -Path $workProject -Force | Out-Null

Get-ChildItem -LiteralPath $template | Where-Object { $_.Name -ne 'worldcup2010_manifest.toml' } |
    Copy-Item -Destination $workProject -Recurse -Force

$logPath = Join-Path $workRoot 'build.log'
Write-Host "Workspace: $workRoot"
Write-Host "Log: $logPath"
Write-Host "Full diagnostics: $logPath.native"
Start-Transcript -Path $logPath -Append | Out-Null
trap {
    Write-Host $_.ToString()
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    throw $_
}

Write-Host "[2/6] Preparing manifest..."

$manifestPath = Join-Path $workProject "worldcup2010_manifest.toml"

$gameDataUnix = $GameData.Replace("\", "/").Replace('"', '\"')

$manifest = @"
[project]
name = "worldcup2010"
sdk_version = "0.10.0"
game_root = "$gameDataUnix"

[entrypoint]
file_path = "$gameDataUnix/default.xex"
out_directory_path = "generated/default"
includes = ["config/default_overrides.toml"]

[[modules]]
guest_path = "game:\\fifadllzf.xex"
file_path = "$gameDataUnix/fifadllzf.xex"
out_directory_path = "generated/fifadllzf_xex"
includes = ["config/fifadllzf_overrides.toml"]
"@

$manifest = $manifest.Replace("`r`n", "`n")
$manifestChanged = !$resume -or !(Test-Path -LiteralPath $manifestPath) -or [IO.File]::ReadAllText($manifestPath).Replace("`r`n", "`n").Trim() -ne $manifest.Trim()
if ($manifestChanged) {
    [System.IO.File]::WriteAllText($manifestPath, $manifest, [System.Text.UTF8Encoding]::new($false))
}

Write-Host ""
Write-Host "Manifest:"
Get-Content $manifestPath
Write-Host ""

Write-Host "[3/6] Cleaning previous generated code..."

$generatedDefault = Join-Path $workProject "generated\default"
$generatedDll = Join-Path $workProject "generated\fifadllzf_xex"

if (!$resume -and (Test-Path $generatedDefault)) {
    if (![IO.Path]::GetFullPath($generatedDefault).StartsWith($workProject + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe generated path' }
    Remove-Item $generatedDefault -Recurse -Force
}

if (!$resume -and (Test-Path $generatedDll)) {
    if (![IO.Path]::GetFullPath($generatedDll).StartsWith($workProject + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe generated path' }
    Remove-Item $generatedDll -Recurse -Force
}

Write-Host "[4/6] Configuring build..."

Push-Location $workProject

try {

    # Generate sources before configuration so CMake discovers both binaries.
    $codegen = if ($useBundledSdk) { Join-Path $bundledSdk 'bin\rexglue.exe' } else { Join-Path $rexGlueSource 'out\win-amd64\Release\rexglue.exe' }
    if (!$useBundledSdk -and !(Test-Path -LiteralPath $codegen)) { $codegen = Join-Path $rexGlueSource 'out\win-amd64\rexglue.exe' }
    if (!$useBundledSdk -and !(Test-Path -LiteralPath $codegen)) { $codegen = Join-Path $rexGlueSource 'out\build\win-amd64-release\bin\rexglue.exe' }
    if (!(Test-Path -LiteralPath $codegen)) { throw "ReXGlue code generator not found: $codegen" }
    $fingerprintPath = Join-Path $workProject 'codegen-inputs.sha256'
    $fingerprintInputs = @($manifestPath, $codegen)
    $fingerprintInputs += @(Get-ChildItem -LiteralPath $GameData -Filter '*.xex*' -File -Recurse | ForEach-Object { $_.FullName })
    $fingerprintInputs += @(Get-ChildItem -LiteralPath (Join-Path $workProject 'config') -File -Recurse | ForEach-Object { $_.FullName })
    $fingerprint = Get-CodegenFingerprint $fingerprintInputs
    $inputsChanged = !(Test-Path -LiteralPath $fingerprintPath) -or [IO.File]::ReadAllText($fingerprintPath).Trim() -ne $fingerprint
    if ($manifestChanged -or $inputsChanged -or !(Test-Path -LiteralPath (Join-Path $generatedDefault 'sources.cmake')) -or
        !(Test-Path -LiteralPath (Join-Path $generatedDll 'sources.cmake'))) {
        if (Test-Path -LiteralPath $fingerprintPath) { Remove-Item -LiteralPath $fingerprintPath -Force }
        Invoke-BuildTool $codegen @('--log-file', (Join-Path $workRoot 'codegen.log'), 'codegen', $manifestPath)
        [IO.File]::WriteAllText($fingerprintPath, $fingerprint, [Text.UTF8Encoding]::new($false))
    }

    $sdkArguments = if ($useBundledSdk) { @('-DREXSDK_DIR=', "-DCMAKE_PREFIX_PATH=$bundledSdk") } else {
        @("-DREXSDK_DIR=$rexGlueSource", "-DREXGLUE_USE_D3D12=$($GraphicsApi -eq 'D3D12')", "-DREXGLUE_USE_VULKAN=$($GraphicsApi -eq 'Vulkan')",
          "-DREXGLUE_OUTPUT_DIRECTORY=$workProject/out/build/win-amd64-release/runtime")
    }
    Invoke-BuildTool 'cmake' (@('--preset', 'win-amd64-release') + $sdkArguments + @(
        "-DCMAKE_C_COMPILER=$clang",
        "-DCMAKE_CXX_COMPILER=$clangxx", '-DCMAKE_C_FLAGS=-mssse3', '-DCMAKE_CXX_FLAGS=-mssse3')
    )

    Write-Host ""
    Write-Host "[5/6] Compiling 2010 FIFA World Cup..."
    Write-Host ""

    Invoke-BuildTool 'cmake' @('--build', '--preset', 'win-amd64-release', '--parallel', "$Jobs")

}
finally {
    Pop-Location
}

$buildFolder = Join-Path $workProject "out\build\win-amd64-release"

$exe = Join-Path $buildFolder "FIFA World Cup 2010.exe"
$dll = Join-Path $buildFolder "worldcup2010_fifadllzf.dll"

if (!(Test-Path $exe)) {
    throw "The build finished but FIFA World Cup 2010.exe was not found."
}

if (!(Test-Path $dll)) {
    throw "The build finished but worldcup2010_fifadllzf.dll was not found."
}

Write-Host ""
Write-Host "[6/6] Installing game binaries..."

New-Item `
    -ItemType Directory `
    -Path $Output `
    -Force | Out-Null

Copy-Item $exe $Output -Force

# Copy the recompiled game modules.
Get-ChildItem -LiteralPath $buildFolder -Filter '*.dll' -File |
    Where-Object { $_.Name -notin @('rexruntime.dll', 'rexgpu-xenos.dll') } |
    Copy-Item -Destination $Output -Force

# Source builds use the paired runtime/GPU DLLs compiled by this invocation.
if (!$useBundledSdk) {
    . (Join-Path $installerRoot 'InstallSourceBackend.ps1')
    Install-SourceBackend -RuntimeDirectory (Join-Path $buildFolder 'runtime') -Output $Output -GraphicsApi $GraphicsApi
    Stop-Transcript | Out-Null
    Write-Host "Source build complete: $Output ($GraphicsApi)"
    return
}

Stop-Transcript | Out-Null
