function Install-SourceBackend {
    param(
        [Parameter(Mandatory = $true)][string]$RuntimeDirectory,
        [Parameter(Mandatory = $true)][string]$Output,
        [ValidateSet('D3D12', 'Vulkan')][string]$GraphicsApi = 'D3D12'
    )
    # Validate the pair before copying any backend files.
    foreach ($name in @('rexruntime.dll', 'rexgpu-xenos.dll')) {
        if (!(Test-Path -LiteralPath (Join-Path $RuntimeDirectory $name) -PathType Leaf)) {
            throw "Source backend is missing $name in $RuntimeDirectory"
        }
    }
    $backend = Join-Path $Output "Backends\$GraphicsApi"
    New-Item -ItemType Directory -Path $backend -Force | Out-Null
    # Include runtime dependencies such as TracyClient.dll from the same build.
    Get-ChildItem -LiteralPath $RuntimeDirectory -Filter '*.dll' -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $backend -Force
        Copy-Item -LiteralPath $_.FullName -Destination $Output -Force
    }
}
