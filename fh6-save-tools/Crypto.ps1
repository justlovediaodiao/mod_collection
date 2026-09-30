param(
    [Parameter(Mandatory)][ValidateSet('Decrypt','Encrypt')][string]$Mode,
    [Parameter(Mandatory)][string]$SessionPath,
    [Parameter(Mandatory)][string]$CryptoToolPath
)
. (Join-Path $PSScriptRoot 'Common.ps1')
$session = Read-Session $SessionPath
$exe = (Resolve-Path -LiteralPath $CryptoToolPath).Path
$work = $session.WorkDirectory
function Invoke-Crypto([string]$Operation,[string]$InputPath,[string]$OutputPath,[string]$LogName) {
    if (Test-Path -LiteralPath $OutputPath) { throw "Output already exists: $OutputPath" }
    # Start-Process joins arguments into a command line; quote every argument for spaces.
    $quoted = @($Operation,$InputPath,'-o',$OutputPath) | ForEach-Object {
        if ($_ -match '"') { throw 'Arguments must not contain double quotes.' }
        '"' + $_ + '"'
    }
    $stdout = Join-Path $work ($LogName + '.stdout.txt')
    $stderr = Join-Path $work ($LogName + '.stderr.txt')
    $process = Start-Process -FilePath $exe -ArgumentList $quoted -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    Get-Content -LiteralPath $stdout
    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $OutputPath)) { Get-Content -LiteralPath $stderr; throw "$Operation failed." }
}
if ($Mode -eq 'Decrypt') {
    Invoke-Crypto 'decrypt' (Join-Path $session.BackupDirectory 'C_ProfileData') (Join-Path $work 'original.bin') 'decrypt'
    Initialize-ProfileTools
    [ForzaCryptoTool.LocalJournalInspector]::Inspect((Join-Path $work 'original.bin'),(Join-Path $work 'inspection'))
} else {
    $edited = Join-Path $work 'edited.bin'
    $report = Get-Content (Join-Path $work 'edit-report.json') -Raw | ConvertFrom-Json
    if ((Get-FileHash -LiteralPath $edited).Hash -ne $report.EditedSHA256) { throw 'The edited file does not match the verification report.' }
    $encrypted = Join-Path $work 'C_ProfileData_modified'
    $roundtrip = Join-Path $work 'roundtrip.bin'
    Invoke-Crypto 'encrypt' $edited $encrypted 'encrypt'
    Invoke-Crypto 'decrypt' $encrypted $roundtrip 'roundtrip'
    if ((Get-FileHash -LiteralPath $roundtrip).Hash -ne $report.EditedSHA256) { throw 'The encryption roundtrip does not match the edited file.' }
    $bytes = [IO.File]::ReadAllBytes($encrypted)
    if ($bytes.Length -le 36 -or ($bytes.Length - 36) % 528 -ne 0) { throw 'Invalid encrypted save container framing.' }
    [pscustomobject]@{RoundtripExact=$true;EditedSHA256=$report.EditedSHA256;EncryptedSHA256=(Get-FileHash -LiteralPath $encrypted).Hash} |
        ConvertTo-Json | Set-Content (Join-Path $work 'verification.json') -Encoding utf8
}
