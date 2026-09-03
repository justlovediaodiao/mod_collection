param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateRange(0.0, 1000000.0)]
    [double] $XPPercent,

    [Parameter(Mandatory = $true, Position = 1)]
    [ValidateRange(0.0, 10000.0)]
    [double] $LootLuck,

    [Parameter(Mandatory = $true, Position = 2)]
    [ValidateNotNullOrEmpty()]
    [string] $SourceDirectory
)

$ErrorActionPreference = 'Stop'

# Use the MaxQuality variant as the base. Its unversioned-property zero mask
# already serializes LootLuck, while CombatExperience is the following double.
$sourceBaseName = '000_CombinedXP_Loot_P'
$outputBaseName = '000_CombinedXP_Loot_P'
$lootLuckOffset = 0xAF7
$combatExperienceOffset = 0xAFF
$xpValue = ($XPPercent / 100.0) - 1.0

$xpLabel = $XPPercent.ToString('0.################', [Globalization.CultureInfo]::InvariantCulture)
$luckLabel = $LootLuck.ToString('0.################', [Globalization.CultureInfo]::InvariantCulture)
$outputDirectory = [IO.Path]::GetFullPath(
    (Join-Path (Get-Location).Path ("BL4_XP_${xpLabel}_LootLuck_$luckLabel"))
)

if ([IO.Path]::IsPathFullyQualified($SourceDirectory)) {
    $resolvedSource = [IO.Path]::GetFullPath($SourceDirectory)
}
else {
    $resolvedSource = [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $SourceDirectory))
}

if (-not [IO.Directory]::Exists($resolvedSource)) {
    throw "Source directory does not exist: $resolvedSource"
}

foreach ($extension in '.pak', '.utoc', '.ucas') {
    $source = Join-Path $resolvedSource ($sourceBaseName + $extension)
    if (-not [IO.File]::Exists($source)) {
        throw "Missing source file: $source"
    }
}

$sourceUcas = Join-Path $resolvedSource ($sourceBaseName + '.ucas')
$bytes = [IO.File]::ReadAllBytes($sourceUcas)
if ($bytes.Length -lt ($combatExperienceOffset + 8)) {
    throw 'Source UCAS is too short for the merged value offsets.'
}

$text = [Text.Encoding]::ASCII.GetString($bytes)
if (-not $text.Contains('LootLuck_14_') -or -not $text.Contains('CombatExperience_46_')) {
    throw 'Source verification failed: expected LootLuck and CombatExperience markers were not found.'
}

# Verify the exact unversioned header/zero mask used by this source layout.
$expectedHeader = [byte[]](0x80, 0x2B, 0x78, 0x00, 0x00, 0x00)
for ($i = 0; $i -lt $expectedHeader.Length; $i++) {
    if ($bytes[0xAE1 + $i] -ne $expectedHeader[$i]) {
        throw "Source layout mismatch at 0x$((0xAE1 + $i).ToString('X')); refusing to patch fixed offsets."
    }
}

$oldLootLuck = [BitConverter]::ToDouble($bytes, $lootLuckOffset)
$oldXPBonus = [BitConverter]::ToDouble($bytes, $combatExperienceOffset)
if ([double]::IsNaN($oldLootLuck) -or [double]::IsInfinity($oldLootLuck) -or
    [double]::IsNaN($oldXPBonus) -or [double]::IsInfinity($oldXPBonus)) {
    throw 'Source verification failed: an existing value is not finite.'
}

[Buffer]::BlockCopy([BitConverter]::GetBytes($LootLuck), 0, $bytes, $lootLuckOffset, 8)
[Buffer]::BlockCopy([BitConverter]::GetBytes($xpValue), 0, $bytes, $combatExperienceOffset, 8)

[IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
foreach ($extension in '.pak', '.utoc') {
    [IO.File]::Copy(
        (Join-Path $resolvedSource ($sourceBaseName + $extension)),
        (Join-Path $outputDirectory ($outputBaseName + $extension)),
        $true
    )
}

$outputUcas = Join-Path $outputDirectory ($outputBaseName + '.ucas')
[IO.File]::WriteAllBytes($outputUcas, $bytes)

$verifiedBytes = [IO.File]::ReadAllBytes($outputUcas)
$verifiedLootLuck = [BitConverter]::ToDouble($verifiedBytes, $lootLuckOffset)
$verifiedXPBonus = [BitConverter]::ToDouble($verifiedBytes, $combatExperienceOffset)
if ($verifiedLootLuck -ne $LootLuck -or $verifiedXPBonus -ne $xpValue) {
    throw 'Output verification failed.'
}

Write-Host "Source LootLuck : $oldLootLuck"
Write-Host "Output LootLuck : $verifiedLootLuck"
Write-Host "Source XP bonus : $oldXPBonus ($((1.0 + $oldXPBonus) * 100)% total XP)"
Write-Host "Output XP bonus : $verifiedXPBonus ($xpLabel% total XP)"
Write-Host "Output directory: $outputDirectory"
Write-Host ''

Get-ChildItem -LiteralPath $outputDirectory -Filter ($outputBaseName + '.*') |
    Sort-Object Name |
    Select-Object Name, Length
