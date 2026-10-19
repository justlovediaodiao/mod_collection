param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $GamePath,

    [switch] $Restore
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$PatchDir = $PSScriptRoot
$ManifestPath = Join-Path $PatchDir 'manifest.json'
$DataPath = Join-Path $PatchDir 'data.bin'
$BackupName = '_CHT2CHS_backup'

function Get-Sha256Hex([byte[]] $bytes) {
    $h = [System.Security.Cryptography.SHA256]::Create()
    try { return [System.Convert]::ToHexString($h.ComputeHash($bytes)) }
    finally { $h.Dispose() }
}

function Get-FileSha256Hex([string] $path) {
    $h = [System.Security.Cryptography.SHA256]::Create()
    try {
        $fs = [System.IO.File]::OpenRead($path)
        try { return [System.Convert]::ToHexString($h.ComputeHash($fs)) }
        finally { $fs.Dispose() }
    }
    finally { $h.Dispose() }
}

function Read-Range([System.IO.FileStream] $fs, [long] $offset, [int] $length) {
    $fs.Seek($offset, [System.IO.SeekOrigin]::Begin) | Out-Null
    $buf = New-Object byte[] $length
    $read = 0
    while ($read -lt $length) {
        $n = $fs.Read($buf, $read, $length - $read)
        if ($n -le 0) { throw "Unexpected end of file while reading $length bytes at offset $offset" }
        $read += $n
    }
    return $buf
}

function Write-Range([System.IO.FileStream] $fs, [long] $offset, [byte[]] $bytes) {
    $fs.Seek($offset, [System.IO.SeekOrigin]::Begin) | Out-Null
    $fs.Write($bytes, 0, $bytes.Length)
}

function Get-TextBlobPath([string] $root, [string] $module, [long] $offset) {
    Join-Path (Join-Path $root ($module | Split-Path -Parent)) ('{0}@{1}.blk' -f (Split-Path $module -Leaf), $offset)
}

if (-not (Test-Path -LiteralPath $ManifestPath)) { throw "manifest.json not found next to this script ($PatchDir)." }
if (-not (Test-Path -LiteralPath (Join-Path $GamePath 'Mount\deploy'))) {
    throw "Game root must contain a Mount\deploy folder: $GamePath"
}

$mount = Join-Path $GamePath 'Mount'
$backupDir = Join-Path $GamePath $BackupName
$textBackupRoot = Join-Path $backupDir 'text'
$fontBackupDir = Join-Path $backupDir 'fonts'
$fontsDir = Join-Path $mount 'maps\fonts'
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$fontNames = @($manifest.font_files.PSObject.Properties.Name)

$byModule = @{}
foreach ($e in $manifest.entries) {
    if (-not $byModule.ContainsKey($e.module)) { $byModule[$e.module] = @() }
    $byModule[$e.module] += $e
}

if ($Restore -and -not (Test-Path -LiteralPath $backupDir)) {
    throw "Backup not found: $backupDir"
}

# ---------------------------------------------------------------- VERIFY ----
foreach ($module in $byModule.Keys) {
    $file = Join-Path $mount $module
    if (-not (Test-Path -LiteralPath $file)) { throw "Missing module: $module" }

    $fs = [System.IO.File]::Open($file, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        foreach ($e in $byModule[$module]) {
            $hash = Get-Sha256Hex (Read-Range $fs ([long]$e.offset) ([int]$e.length))
            if ($hash -notin @($e.orig_sha256, $e.new_sha256)) {
                throw "Text hash mismatch: $module @ $($e.offset)"
            }
            if ($Restore) {
                $blob = Get-TextBlobPath $textBackupRoot $e.module $e.offset
                if (-not (Test-Path -LiteralPath $blob)) { throw "Missing backup: $blob" }
                if ((Get-FileSha256Hex $blob) -ne $e.orig_sha256) { throw "Backup hash mismatch: $blob" }
            }
        }
    }
    finally { $fs.Dispose() }
}

foreach ($name in $fontNames) {
    $info = $manifest.font_files.$name
    $target = Join-Path $fontsDir $name
    if (-not (Test-Path -LiteralPath $target)) { throw "Missing font file: $name" }

    $hash = Get-FileSha256Hex $target
    if ($hash -notin @($info.original_sha256, $info.new_sha256)) {
        throw "Font hash mismatch: $name"
    }
    if ($Restore) {
        $saved = Join-Path $fontBackupDir $name
        if (-not (Test-Path -LiteralPath $saved)) { throw "Missing font backup: $name" }
        if ((Get-FileSha256Hex $saved) -ne $info.original_sha256) { throw "Font backup hash mismatch: $name" }
    }
    else {
        $src = Join-Path $PatchDir $name
        if ((Get-FileSha256Hex $src) -ne $info.new_sha256) { throw "Patch font corrupt: $name" }
    }
}

$data = $null
$uniq = @{}
if (-not $Restore) {
    if (-not (Test-Path -LiteralPath $DataPath)) { throw "data.bin not found next to this script ($PatchDir)." }
    $data = [System.IO.File]::ReadAllBytes($DataPath)
    foreach ($u in $manifest.unique) {
        $bytes = New-Object byte[] ([int]$u.length)
        [Array]::Copy($data, [int]$u.offset, $bytes, 0, [int]$u.length)
        if ((Get-Sha256Hex $bytes) -ne $u.sha256) { throw "data.bin corrupt at offset $($u.offset)" }
        $uniq[$u.sha256] = $u
    }
}

# ----------------------------------------------------------------- APPLY ----
foreach ($module in $byModule.Keys) {
    $file = Join-Path $mount $module
    $fs = [System.IO.File]::Open($file, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::Read)
    try {
        foreach ($e in $byModule[$module]) {
            [byte[]] $cur = Read-Range $fs ([long]$e.offset) ([int]$e.length)
            $hash = Get-Sha256Hex $cur

            if ($Restore) {
                if ($hash -eq $e.new_sha256) {
                    $blob = Get-TextBlobPath $textBackupRoot $e.module $e.offset
                    Write-Range $fs ([long]$e.offset) ([System.IO.File]::ReadAllBytes($blob))
                }
                $expected = $e.orig_sha256
            }
            else {
                if ($hash -eq $e.orig_sha256) {
                    $blob = Get-TextBlobPath $textBackupRoot $e.module $e.offset
                    if (-not (Test-Path -LiteralPath $blob)) {
                        New-Item -ItemType Directory -Force -Path (Split-Path $blob -Parent) | Out-Null
                        [System.IO.File]::WriteAllBytes($blob, $cur)
                    }
                    $u = $uniq[$e.new_sha256]
                    $new = New-Object byte[] ([int]$u.length)
                    [Array]::Copy($data, [int]$u.offset, $new, 0, [int]$u.length)
                    Write-Range $fs ([long]$e.offset) $new
                }
                $expected = $e.new_sha256
            }

            $fs.Flush()
            $after = Get-Sha256Hex (Read-Range $fs ([long]$e.offset) ([int]$e.length))
            if ($after -ne $expected) { throw "Text write verify failed: $module @ $($e.offset)" }
        }
    }
    finally { $fs.Dispose() }
}

foreach ($name in $fontNames) {
    $info = $manifest.font_files.$name
    $target = Join-Path $fontsDir $name
    $hash = Get-FileSha256Hex $target

    if ($Restore) {
        if ($hash -eq $info.new_sha256) {
            Copy-Item -LiteralPath (Join-Path $fontBackupDir $name) -Destination $target -Force
        }
        $expected = $info.original_sha256
    }
    else {
        if ($hash -eq $info.original_sha256) {
            $saved = Join-Path $fontBackupDir $name
            if (-not (Test-Path -LiteralPath $saved)) {
                New-Item -ItemType Directory -Force -Path $fontBackupDir | Out-Null
                Copy-Item -LiteralPath $target -Destination $saved
            }
            Copy-Item -LiteralPath (Join-Path $PatchDir $name) -Destination $target -Force
        }
        $expected = $info.new_sha256
    }

    if ((Get-FileSha256Hex $target) -ne $expected) { throw "Font write verify failed: $name" }
}

if ($Restore) {
    Write-Host "Restored original text and fonts." -ForegroundColor Green
}
else {
    Write-Host "Installed Simplified Chinese text and fonts." -ForegroundColor Green
}
Write-Host "Backup: $backupDir"
Write-Host "To undo: pwsh -File `"$PSCommandPath`" -GamePath `"$GamePath`" -Restore"
