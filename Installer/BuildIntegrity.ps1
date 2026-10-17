function Get-InputSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [IO.File]::OpenRead($Path)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
    finally { $algorithm.Dispose(); $stream.Dispose() }
}

function Get-CodegenFingerprint {
    param([Parameter(Mandatory = $true)][string[]]$Paths)
    $records = foreach ($path in ($Paths | Sort-Object -Unique)) {
        $absolute = [IO.Path]::GetFullPath($path)
        $absolute + ':' + (Get-InputSha256 $absolute)
    }
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes(($records -join "`n")))).Replace('-', '').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
}
