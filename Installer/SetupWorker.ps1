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
    $logLock = New-Object object
    $writer = [IO.StreamWriter]::new($LogPath, $true, [Text.UTF8Encoding]::new($false))
    $writer.AutoFlush = $true
    $outputHandler = [Diagnostics.DataReceivedEventHandler]{
        param($sender, $eventArgs)
        if ($null -ne $eventArgs.Data) {
            [Threading.Monitor]::Enter($logLock)
            try { $writer.WriteLine('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $eventArgs.Data) }
            finally { [Threading.Monitor]::Exit($logLock) }
        }
    }.GetNewClosure()
    $process.add_OutputDataReceived($outputHandler)
    $process.add_ErrorDataReceived($outputHandler)
    [void]$process.Start()
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()
    $process.WaitForExit()
    $process.WaitForExit()
    $writer.Dispose()
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

function Ensure-LLVM {
    $llvmRoot = Join-Path $env:LOCALAPPDATA 'FWC10\tools\LLVM-20.1.8'
    $llvmBin = Join-Path $llvmRoot 'bin'
    $clang = Join-Path $llvmBin 'clang.exe'
    $fallbackBins = @(
        (Join-Path $env:ProgramFiles 'LLVM\bin'),
        (Join-Path ${env:ProgramFiles(x86)} 'LLVM\bin'),
        (Join-Path $env:LOCALAPPDATA 'Programs\LLVM\bin')
    )
    if (-not (Test-Path -LiteralPath $clang -PathType Leaf)) {
        $fallback = $fallbackBins | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'clang.exe') -PathType Leaf } | Select-Object -First 1
        if ($fallback) {
            $llvmBin = $fallback
        } else {
            $installer = Join-Path $PackageRoot 'Installer\tools\LLVM-20.1.8-win64.exe'
            if (Test-Path -LiteralPath $installer -PathType Leaf) {
                Write-SetupLog 'Using the LLVM 20.1.8 installer embedded in setup.'
            } else {
                Write-SetupLog 'Downloading the pinned LLVM 20.1.8 compiler (about 386 MB).'
                $installer = Join-Path $env:LOCALAPPDATA 'FWC10\downloads\LLVM-20.1.8-win64.exe'
                Download-File 'https://github.com/llvm/llvm-project/releases/download/llvmorg-20.1.8/LLVM-20.1.8-win64.exe' $installer
            }
            $hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($hash -ne '3197846a2b19063687dd56e93e34cd941e3548d907f23a6131571321bdf9fe7b') {
                throw 'The LLVM download failed its SHA-256 check; refusing to run it.'
            }
            Write-SetupLog 'Installing LLVM for the current user.'
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $llvmRoot))
            # NSIS requires /D= to be the final, unquoted command-line argument.
            $process = Start-Process -FilePath $installer -ArgumentList @('/S',("/D={0}" -f $llvmRoot)) -Wait -PassThru
            if ($process.ExitCode -ne 0) { throw "LLVM installation failed with code $($process.ExitCode)." }
            if (-not (Test-Path -LiteralPath $clang -PathType Leaf)) {
                $fallback = $fallbackBins | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'clang.exe') -PathType Leaf } | Select-Object -First 1
                if ($fallback) { $llvmBin = $fallback }
            }
        }
        if ($llvmBin -ne (Join-Path $llvmRoot 'bin')) { Write-SetupLog "Using the LLVM compiler found at $llvmBin" }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $llvmBin 'clang.exe') -PathType Leaf)) {
        throw "LLVM setup finished but clang.exe was not found. Checked '$llvmBin' and the standard LLVM install locations. If this persists, install LLVM 20.1.8 and rerun setup."
    }
    $env:FWC10_LLVM_BIN = $llvmBin
    $env:PATH = "$env:FWC10_LLVM_BIN;$env:PATH"
}

function Ensure-Sdk([string]$VsPath) {
    $sdkRoot = Join-Path $env:LOCALAPPDATA 'FWC10\sdk\rexglue-bundled-v0.3.3'
    $sdkArchive = Join-Path $PackageRoot 'Installer\sdk-source.zip'
    if (-not (Test-Path -LiteralPath $sdkArchive -PathType Leaf)) { throw 'The bundled ReXGlue source archive is missing from this setup.' }
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $sdkRoot))
    if (-not (Test-Path -LiteralPath (Join-Path $sdkRoot 'CMakeLists.txt') -PathType Leaf)) {
        Write-SetupLog 'Extracting the ReXGlue source and required submodules bundled in setup.'
        [void][IO.Directory]::CreateDirectory($sdkRoot)
        Expand-Archive -LiteralPath $sdkArchive -DestinationPath $sdkRoot -Force
    } else {
        Write-SetupLog 'Reusing the bundled ReXGlue source already extracted on this PC.'
    }
    foreach ($module in @('cli11','libmspack','FFmpeg','tomlplusplus','simde','xxHash','spdlog','fmt','utfcpp','imgui','sdl3','tracy')) {
        $moduleRoot = Join-Path $sdkRoot "thirdparty\$module"
        if (-not (Test-Path -LiteralPath (Join-Path $moduleRoot '.git') -PathType Leaf)) {
            throw "A bundled ReXGlue dependency is incomplete: $moduleRoot"
        }
    }

    Write-SetupLog 'Building the bundled ReXGlue code generator from source.'
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
    $hasGameData = Test-Path -LiteralPath $gameData -PathType Container
    if ($hasGameData -and (-not (Test-Path -LiteralPath (Join-Path $gameData 'default.xex') -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $gameData 'fifadllzf.xex') -PathType Leaf))) {
        throw 'The existing GameData folder is incomplete; choose a clean install folder or reselect the ISO.'
    }

    Write-SetupLog 'Checking and preparing the Windows C++ build tools.'
    $vsPath = Ensure-VisualStudioBuildTools
    Import-VsEnvironment $vsPath
    Ensure-LLVM

    if ($hasGameData) {
        Write-SetupLog 'Reusing the game files extracted by the previous setup attempt.'
    } else {
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
    }

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
