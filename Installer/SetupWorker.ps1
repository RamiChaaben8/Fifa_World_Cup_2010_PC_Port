[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$IsoPath,
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][string]$PackageRoot,
    [Parameter(Mandatory = $true)][string]$LogPath
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-SetupLog([string]$Message) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

function Invoke-Tool([string]$File, [string[]]$Arguments, [string]$WorkingDirectory = $PackageRoot) {
    $quoted = foreach ($arg in $Arguments) { '"' + ([string]$arg).Replace('"', '\"') + '"' }
    Write-SetupLog ('Running: {0} {1}' -f $File, ($quoted -join ' '))
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $File
    $start.Arguments = $quoted -join ' '
    $start.WorkingDirectory = $WorkingDirectory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($stdout) { Add-Content -LiteralPath $LogPath -Value $stdout -Encoding UTF8 }
    if ($stderr) { Add-Content -LiteralPath $LogPath -Value $stderr -Encoding UTF8 }
    if ($process.ExitCode -ne 0) { throw "Tool failed with exit code $($process.ExitCode): $File" }
}

function Download-File([string]$Uri, [string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return }
    Write-SetupLog "Downloading $([IO.Path]::GetFileName($Path))"
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $Path
}

function Find-VSWhere {
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\Installer\vswhere.exe')
    )
    $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}

function Ensure-VisualStudioBuildTools {
    $vswhere = Find-VSWhere
    if ($vswhere) {
        $path = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1
        if ($path -and (Test-Path -LiteralPath (Join-Path $path 'Common7\Tools\VsDevCmd.bat'))) { return $path.Trim() }
    }

    Write-SetupLog 'Visual Studio C++ Build Tools are missing; downloading the Microsoft installer.'
    $bootstrapper = Join-Path $env:TEMP 'FWC10-vs_BuildTools.exe'
    Download-File 'https://aka.ms/vs/18/release/vs_BuildTools.exe' $bootstrapper
    Write-SetupLog 'Starting the Microsoft Build Tools installer. Approve the Windows elevation prompt if shown.'
    $args = '--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.CMake.Project --includeRecommended'
    $process = Start-Process -FilePath $bootstrapper -ArgumentList $args -Verb RunAs -Wait -PassThru
    if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) {
        throw "Visual Studio Build Tools installation failed with code $($process.ExitCode)."
    }
    $vswhere = Find-VSWhere
    if (-not $vswhere) { throw 'Visual Studio installer finished, but vswhere.exe was not found.' }
    $path = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1
    if (-not $path) { throw 'Visual Studio C++ build tools were not detected after installation.' }
    return $path.Trim()
}

function Import-VsEnvironment([string]$VsPath) {
    $devcmd = Join-Path $VsPath 'Common7\Tools\VsDevCmd.bat'
    $command = 'call "{0}" -arch=x64 -host_arch=x64 >nul && set' -f $devcmd
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $env:ComSpec
    $start.Arguments = '/d /s /c "' + $command + '"'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    [void]$process.Start()
    $output = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw 'Could not initialize the Visual Studio C++ environment.' }
    foreach ($line in ($output -split "`r?`n")) {
        $equals = $line.IndexOf('=')
        if ($equals -gt 0) { [Environment]::SetEnvironmentVariable($line.Substring(0, $equals), $line.Substring($equals + 1), 'Process') }
    }

    $cmake = Join-Path $VsPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin'
    $ninja = Join-Path $VsPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja'
    foreach ($bin in @($cmake, $ninja)) {
        if (-not (Test-Path -LiteralPath $bin -PathType Container)) { throw "Required Visual Studio build tool was not installed: $bin" }
        $env:PATH = "$bin;$env:PATH"
    }
    if (-not (Get-Command cmake.exe -ErrorAction SilentlyContinue)) { throw 'CMake is missing from the Visual Studio installation.' }
    if (-not (Get-Command ninja.exe -ErrorAction SilentlyContinue)) { throw 'Ninja is missing from the Visual Studio installation.' }
}

function Ensure-Git {
    if (Get-Command git.exe -ErrorAction SilentlyContinue) { return }
    Write-SetupLog 'Downloading portable Git.'
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/git-for-windows/git/releases/latest' -Headers @{ 'User-Agent' = 'FWC10-Setup' }
    $asset = $release.assets | Where-Object { $_.name -like 'MinGit-*-64-bit.zip' } | Select-Object -First 1
    if (-not $asset) { throw 'Could not find a portable Git download.' }
    $tools = Join-Path $env:LOCALAPPDATA 'FWC10\tools'
    $archive = Join-Path $tools $asset.name
    $gitRoot = Join-Path $tools 'MinGit'
    Download-File $asset.browser_download_url $archive
    [void][IO.Directory]::CreateDirectory($gitRoot)
    Expand-Archive -LiteralPath $archive -DestinationPath $gitRoot -Force
    $env:PATH = "$(Join-Path $gitRoot 'cmd');$(Join-Path $gitRoot 'mingw64\bin');$env:PATH"
    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) { throw 'Portable Git was extracted but git.exe could not be found.' }
}

function Ensure-LLVM {
    $llvmRoot = Join-Path $env:LOCALAPPDATA 'FWC10\tools\LLVM-20.1.8'
    $clang = Join-Path $llvmRoot 'bin\clang.exe'
    if (-not (Test-Path -LiteralPath $clang -PathType Leaf)) {
        Write-SetupLog 'Downloading the pinned LLVM 20.1.8 compiler (about 386 MB).'
        $installer = Join-Path $env:LOCALAPPDATA 'FWC10\downloads\LLVM-20.1.8-win64.exe'
        Download-File 'https://github.com/llvm/llvm-project/releases/download/llvmorg-20.1.8/LLVM-20.1.8-win64.exe' $installer
        $hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -ne '3197846a2b19063687dd56e93e34cd941e3548d907f23a6131571321bdf9fe7b') {
            throw 'The LLVM download failed its SHA-256 check; refusing to run it.'
        }
        Write-SetupLog 'Installing LLVM for the current user.'
        $process = Start-Process -FilePath $installer -ArgumentList ('/S /D="{0}"' -f $llvmRoot) -Wait -PassThru
        if ($process.ExitCode -ne 0) { throw "LLVM installation failed with code $($process.ExitCode)." }
    }
    if (-not (Test-Path -LiteralPath $clang -PathType Leaf)) { throw 'LLVM installation did not create clang.exe.' }
    $env:FWC10_LLVM_BIN = Join-Path $llvmRoot 'bin'
    $env:PATH = "$env:FWC10_LLVM_BIN;$env:PATH"
}

function Ensure-Sdk([string]$VsPath) {
    $sdkRoot = Join-Path $env:LOCALAPPDATA 'FWC10\sdk\rexglue-c94f5eb-v0.3'
    $patch = Join-Path $PackageRoot 'patches\rexglue-v0.3-local.patch'
    $submodulePatch = Join-Path $PackageRoot 'patches\rexglue-libmspack-v0.3.patch'
    if (-not (Test-Path -LiteralPath $patch -PathType Leaf)) { throw 'The v0.3 ReXGlue source patch is missing from the setup package.' }
    if (-not (Test-Path -LiteralPath $submodulePatch -PathType Leaf)) { throw 'The v0.3 libmspack source patch is missing from the setup package.' }
    Ensure-Git
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $sdkRoot))
    if (-not (Test-Path -LiteralPath $sdkRoot)) {
        Write-SetupLog 'Downloading the pinned ReXGlue source and submodules.'
        Invoke-Tool 'git.exe' @('clone','--recurse-submodules','https://github.com/rexglue/rexglue-sdk.git',$sdkRoot) $PackageRoot
        Invoke-Tool 'git.exe' @('-C',$sdkRoot,'checkout','c94f5ebdcb3c9d1a460ca48e04f9758448f8d518') $PackageRoot
        Invoke-Tool 'git.exe' @('-C',$sdkRoot,'submodule','update','--init','--recursive') $PackageRoot
    } else {
        $head = (& git.exe -C $sdkRoot rev-parse HEAD 2>$null | Select-Object -First 1)
        if ($head -ne 'c94f5ebdcb3c9d1a460ca48e04f9758448f8d518') { throw "Existing SDK folder is not the expected pinned checkout: $sdkRoot" }
    }

    $reverseCheck = & git.exe -C $sdkRoot apply --reverse --check --ignore-space-change $patch 2>$null
    if ($LASTEXITCODE -ne 0) {
        Invoke-Tool 'git.exe' @('-C',$sdkRoot,'apply','--ignore-space-change',$patch) $PackageRoot
    } else {
        Write-SetupLog 'The local v0.3 ReXGlue patch is already applied.'
    }

    $lib = Join-Path $sdkRoot 'thirdparty\libmspack'
    $submoduleReverseCheck = & git.exe -C $lib apply --reverse --check --ignore-space-change $submodulePatch 2>$null
    if ($LASTEXITCODE -ne 0) {
        Invoke-Tool 'git.exe' @('-C',$lib,'apply','--ignore-space-change',$submodulePatch) $PackageRoot
    } else {
        Write-SetupLog 'The local v0.3 libmspack patch is already applied.'
    }

    Write-SetupLog 'Building the ReXGlue code generator from source.'
    Invoke-Tool 'cmake.exe' @('--preset','win-amd64-release') $sdkRoot
    Invoke-Tool 'cmake.exe' @('--build','--preset','win-amd64-release','--target','rexglue','--parallel','2') $sdkRoot
    $codegen = Join-Path $sdkRoot 'out\win-amd64\Release\rexglue.exe'
    if (-not (Test-Path -LiteralPath $codegen -PathType Leaf)) { throw "ReXGlue code generator build output not found: $codegen" }
    return $sdkRoot
}

function Build-Game([string]$SdkRoot, [string]$GameData, [string]$Output) {
    $buildScript = Join-Path $PackageRoot 'Installer\BuildWorldCup2010.ps1'
    if (-not (Test-Path -LiteralPath $buildScript -PathType Leaf)) { throw 'BuildWorldCup2010.ps1 is missing from the setup package.' }
    $env:REXSDK_DIR = $SdkRoot
    $env:FWC10_BUILD_ROOT = Join-Path $env:LOCALAPPDATA 'FWC10\build'
    $jobs = [Math]::Min(4, [Math]::Max(1, [Environment]::ProcessorCount - 1))
    Write-SetupLog 'Compiling the game from the selected ISO data. This can take 10-30 minutes.'
    & (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $buildScript -GameData $GameData -Output $Output -SourceBuild -Jobs $jobs *>> $LogPath
    if ($LASTEXITCODE -ne 0) { throw "Game compilation failed with exit code $LASTEXITCODE. See $LogPath" }
    $exe = Join-Path $Output 'FIFA World Cup 2010.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'The build did not produce FIFA World Cup 2010.exe.' }
}

try {
    if (-not (Test-Path -LiteralPath $IsoPath -PathType Leaf)) { throw 'The selected ISO file is no longer available.' }
    if (-not (Test-Path -LiteralPath (Join-Path $PackageRoot 'Installer\tools\extract-xiso.exe') -PathType Leaf)) {
        throw 'extract-xiso.exe is missing from the setup package.'
    }
    [void][IO.Directory]::CreateDirectory($Destination)
    $gameData = Join-Path $Destination 'GameData'
    if (Test-Path -LiteralPath $gameData) { throw 'GameData already exists in the selected install folder; choose an empty folder.' }

    Write-SetupLog 'Checking and preparing the Windows C++ build tools.'
    $vsPath = Ensure-VisualStudioBuildTools
    Import-VsEnvironment $vsPath
    Ensure-LLVM

    $temporaryGameData = Join-Path $Destination '.GameData-extracting'
    if (Test-Path -LiteralPath $temporaryGameData) { throw "Temporary extraction folder already exists: $temporaryGameData" }
    [void][IO.Directory]::CreateDirectory($temporaryGameData)
    Write-SetupLog 'Extracting the selected ISO locally. The ISO is not uploaded or copied into the release.'
    Invoke-Tool (Join-Path $PackageRoot 'Installer\tools\extract-xiso.exe') @('-x','-d',$temporaryGameData,$IsoPath) $PackageRoot
    if (-not (Test-Path -LiteralPath (Join-Path $temporaryGameData 'default.xex')) -or
        -not (Test-Path -LiteralPath (Join-Path $temporaryGameData 'fifadllzf.xex'))) {
        throw 'The selected ISO did not extract the expected default.xex and fifadllzf.xex files at its root.'
    }
    Move-Item -LiteralPath $temporaryGameData -Destination $gameData

    $sdkRoot = Ensure-Sdk $vsPath
    Build-Game $sdkRoot $gameData $Destination

    foreach ($file in @('Settings.exe','Launcher.ps1')) {
        $source = Join-Path $PackageRoot $file
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Launcher file is missing from setup package: $file" }
        Copy-Item -LiteralPath $source -Destination $Destination -Force
    }
    Copy-Item -LiteralPath (Join-Path $PackageRoot 'icons') -Destination $Destination -Recurse -Force
    Write-SetupLog "Installation complete: $Destination"
    exit 0
} catch {
    Write-SetupLog ('ERROR: ' + $_.Exception.Message)
    exit 1
}
