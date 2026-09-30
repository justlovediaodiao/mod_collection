param(
    [Parameter(Mandatory)][string]$SaveDirectory,
    [Parameter(Mandatory)][string]$OutputDirectory
)
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-GameClosed
$save = (Resolve-Path -LiteralPath $SaveDirectory).Path
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) { throw 'Choose a new output directory that does not exist yet.' }
if ($output.StartsWith($save + '\', [StringComparison]::OrdinalIgnoreCase) -or $output -eq $save) { throw 'The backup directory must be outside the game save directory.' }
foreach ($name in @('C_ProfileData','C_ProfileData_SCopy')) {
    if (-not (Test-Path -LiteralPath (Join-Path $save $name))) { throw "Cannot find $name. Check that this is the current user save directory." }
}
New-Item -ItemType Directory -Path $output | Out-Null
$backup = Join-Path $output 'backup'
New-Item -ItemType Directory -Path $backup | Out-Null
$files = foreach ($name in @('C_ProfileData','C_ProfileData_SCopy','C_ProfileBackup')) {
    $path = Join-Path $save $name
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $hash = (Get-FileHash -LiteralPath $path).Hash
    Copy-Item -LiteralPath $path -Destination (Join-Path $backup $name)
    if ((Get-FileHash -LiteralPath (Join-Path $backup $name)).Hash -ne $hash) { throw 'Backup verification failed.' }
    [pscustomobject]@{Name=$name;Hash=$hash;Size=(Get-Item -LiteralPath $path).Length}
}
[pscustomobject]@{Version=1;SaveDirectory=$save;WorkDirectory=$output;BackupDirectory=$backup;Created=(Get-Date).ToString('o');Files=@($files)} |
    ConvertTo-Json -Depth 10 | Set-Content (Join-Path $output 'session.json') -Encoding utf8
Join-Path $output 'session.json'
