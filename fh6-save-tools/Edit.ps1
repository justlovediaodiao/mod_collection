param([Parameter(Mandatory)][string]$SessionPath,[Parameter(Mandatory)][string]$PlanPath)
. (Join-Path $PSScriptRoot 'Common.ps1')
$session = Read-Session $SessionPath
Initialize-ProfileTools
[ForzaCryptoTool.JournalEditor]::Edit((Join-Path $session.WorkDirectory 'original.bin'),(Resolve-Path -LiteralPath $PlanPath).Path,(Join-Path $session.WorkDirectory 'edited.bin'),(Join-Path $session.WorkDirectory 'edit-report.json'))
Get-Content (Join-Path $session.WorkDirectory 'edit-report.json')
