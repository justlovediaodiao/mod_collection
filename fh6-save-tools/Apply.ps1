param([Parameter(Mandatory)][string]$SessionPath,[switch]$Restore)
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-GameClosed
$session = Read-Session $SessionPath
$work = $session.WorkDirectory
$verification = Get-Content (Join-Path $work 'verification.json') -Raw | ConvertFrom-Json
$report = Get-Content (Join-Path $work 'edit-report.json') -Raw | ConvertFrom-Json
if ($verification.EditedSHA256 -ne $report.EditedSHA256 -or (Get-FileHash -LiteralPath (Join-Path $work 'edited.bin')).Hash -ne $report.EditedSHA256 -or (Get-FileHash -LiteralPath (Join-Path $work 'original.bin')).Hash -ne $report.SourceSHA256) { throw 'The plaintext, edit report, and roundtrip report do not belong to the same edit.' }
$source = Join-Path $work 'C_ProfileData_modified'
if (-not $verification.RoundtripExact -or (Get-FileHash -LiteralPath $source).Hash -ne $verification.EncryptedSHA256) { throw 'Modified save verification failed.' }
$targets = @($session.Files | Where-Object Name -in @('C_ProfileData','C_ProfileData_SCopy'))
if ($targets.Count -ne 2) { throw 'A backup of the main save or synchronized copy is missing.' }
foreach ($file in $targets) {
    $destination = Join-Path $session.SaveDirectory $file.Name
    $expected = if ($Restore) { $verification.EncryptedSHA256 } else { $file.Hash }
    if ((Get-FileHash -LiteralPath $destination).Hash -ne $expected) { throw 'The game save has changed. Read the latest save before continuing; newer progress must not be overwritten.' }
}
if ($Restore) {
    foreach ($file in $targets) { Copy-Item -LiteralPath (Join-Path $session.BackupDirectory $file.Name) -Destination (Join-Path $session.SaveDirectory $file.Name) -Force }
    foreach ($file in $targets) { if ((Get-FileHash -LiteralPath (Join-Path $session.SaveDirectory $file.Name)).Hash -ne $file.Hash) { throw 'Verification failed after restoring the backup.' } }
    'Both original files have been restored.'
    return
}
try {
    foreach ($file in $targets) {
        $destination = Join-Path $session.SaveDirectory $file.Name
        Copy-Item -LiteralPath $source -Destination $destination -Force
        if ((Get-FileHash -LiteralPath $destination).Hash -ne $verification.EncryptedSHA256) { throw 'Verification failed after writing the save.' }
    }
} catch {
    foreach ($file in $targets) { Copy-Item -LiteralPath (Join-Path $session.BackupDirectory $file.Name) -Destination (Join-Path $session.SaveDirectory $file.Name) -Force }
    throw
}
[pscustomobject]@{Applied=(Get-Date).ToString('o');SaveDirectory=$session.SaveDirectory;Files=@($targets.Name);EncryptedSHA256=$verification.EncryptedSHA256;BackupDirectory=$session.BackupDirectory;GameLoadVerified=$false} |
    ConvertTo-Json | Set-Content (Join-Path $work 'apply-result.json') -Encoding utf8
Get-Content (Join-Path $work 'apply-result.json')
