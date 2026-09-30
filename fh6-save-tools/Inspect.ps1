param(
    [Parameter(Mandatory)][string]$ProfilePath,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$GameDirectory
)
. (Join-Path $PSScriptRoot 'Common.ps1')
Initialize-ProfileTools
$inputPath = (Resolve-Path -LiteralPath $ProfilePath).Path
$output = [IO.Path]::GetFullPath($OutputDirectory)
if ($inputPath.StartsWith($output + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'The input file must be outside the output directory.' }
[ForzaCryptoTool.LocalJournalInspector]::Inspect($inputPath,$output)
if ($GameDirectory) {
    $zip = (Resolve-Path -LiteralPath (Join-Path $GameDirectory 'media\ObjectModelGame.zip')).Path
    [ForzaCryptoTool.LocalJournalInspector]::InspectCollectionAssets($zip,(Join-Path $output 'assets'))
}
Get-Content (Join-Path $output 'summary.json')
