param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateRange(0.0, 1000000.0)]
    [double] $XPPercent,

    [Parameter(Mandatory = $true, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [string] $SourceDirectory
)

$ErrorActionPreference = 'Stop'

$baseName = '000_250percentXP_P'
$valueOffset = 0xAE7
# CombatExperience stores the bonus above the game's base 100% XP rate.
# For example, 250% total XP is encoded as 1.5 (an additional 150%).
$xpValue = ($XPPercent / 100.0) - 1.0
$xpLabel = $XPPercent.ToString('0.################', [Globalization.CultureInfo]::InvariantCulture)
$outputDirectory = [IO.Path]::GetFullPath(
    (Join-Path (Get-Location).Path ("BL4_XP_$xpLabel"))
)

if ([IO.Path]::IsPathFullyQualified($SourceDirectory)) {
    $resolvedSource = [IO.Path]::GetFullPath($SourceDirectory)
}
else {
    $resolvedSource = [IO.Path]::GetFullPath(
        (Join-Path (Get-Location).Path $SourceDirectory)
    )
}
if (-not [IO.Directory]::Exists($resolvedSource)) {
    throw "Source directory does not exist: $resolvedSource"
}

if ($outputDirectory.TrimEnd('\') -eq $resolvedSource.TrimEnd('\')) {
    throw 'Output directory is the same as the source directory. Use a different XP percentage or run the script from another directory.'
}

$sourceUcas = Join-Path $resolvedSource ($baseName + '.ucas')
foreach ($extension in '.pak', '.utoc', '.ucas') {
    $source = Join-Path $resolvedSource ($baseName + $extension)
    if (-not [IO.File]::Exists($source)) {
        throw "Missing source file: $source"
    }
}

$bytes = [IO.File]::ReadAllBytes($sourceUcas)
if ($bytes.Length -lt ($valueOffset + 8)) {
    throw "Source UCAS is too short for value offset 0x$($valueOffset.ToString('X'))"
}

$text = [Text.Encoding]::ASCII.GetString($bytes)
if (-not $text.Contains('CombatExperience_46_')) {
    throw 'Source verification failed: CombatExperience field marker was not found.'
}

$oldValue = [BitConverter]::ToDouble($bytes, $valueOffset)
if ([double]::IsNaN($oldValue) -or [double]::IsInfinity($oldValue)) {
    throw "Source verification failed: value at 0x$($valueOffset.ToString('X')) is not a finite number."
}

[IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
foreach ($extension in '.pak', '.utoc') {
    $source = Join-Path $resolvedSource ($baseName + $extension)
    $destination = Join-Path $outputDirectory ($baseName + $extension)
    [IO.File]::Copy($source, $destination, $true)
}

$replacement = [BitConverter]::GetBytes($xpValue)
[Buffer]::BlockCopy($replacement, 0, $bytes, $valueOffset, 8)
$outputUcas = Join-Path $outputDirectory ($baseName + '.ucas')
[IO.File]::WriteAllBytes($outputUcas, $bytes)

$verified = [BitConverter]::ToDouble([IO.File]::ReadAllBytes($outputUcas), $valueOffset)
if ($verified -ne $xpValue) {
    throw "Output verification failed: wrote $xpValue, read back $verified"
}

Write-Host "Source XP bonus    : $oldValue ($((1.0 + $oldValue) * 100)% total XP)"
Write-Host "Output XP bonus    : $verified ($xpLabel% total XP)"
Write-Host "Output directory   : $outputDirectory"
Write-Host ''

Get-ChildItem -LiteralPath $outputDirectory -Filter ($baseName + '.*') |
    Sort-Object Name |
    Select-Object Name, Length
