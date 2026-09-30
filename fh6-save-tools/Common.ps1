$ErrorActionPreference = 'Stop'
function Initialize-ProfileTools {
    if ('ForzaCryptoTool.JournalEditor' -as [type]) { return }
    $prefix = "#nullable enable`nusing System;`nusing System.IO;`nusing System.Linq;`nusing System.Collections.Generic;`nusing System.Text.Json;`n"
    $source = Get-Content (Join-Path $PSScriptRoot 'vendor\Fh6ProfileEditorDocument.cs') -Raw
    $inspector = Get-Content (Join-Path $PSScriptRoot 'Inspector.cs') -Raw
    $editor = Get-Content (Join-Path $PSScriptRoot 'JournalEditor.cs') -Raw
    Add-Type -TypeDefinition ($prefix + $source + $inspector + $editor) -IgnoreWarnings
}
function Assert-GameClosed {
    if (Get-Process -Name forzahorizon6 -ErrorAction SilentlyContinue) { throw 'Exit the game completely before working with save files.' }
}
function Read-Session([string]$Path) {
    $session = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    foreach ($file in $session.Files) {
        $backup = Join-Path $session.BackupDirectory $file.Name
        if ((Get-FileHash -LiteralPath $backup).Hash -ne $file.Hash) { throw "The backup has changed: $backup" }
    }
    return $session
}
