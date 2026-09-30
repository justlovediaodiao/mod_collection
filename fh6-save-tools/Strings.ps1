function Attr($node, $key) { ($node.Attributes | Where-Object Key -eq $key).Value }
function Prop($node, $id) { $node.Children | Where-Object { $_.Name -eq 'property' -and (Attr $_ 'id') -eq $id } }
function Read-StringTable([string]$name) {
    $zip = [IO.Compression.ZipFile]::OpenRead($script:StringTablesPath)
    try {
        $stream = $zip.GetEntry($name + '.str').Open()
        try { $memory = [IO.MemoryStream]::new(); $stream.CopyTo($memory); $bytes = $memory.ToArray(); $memory.Dispose() } finally { $stream.Dispose() }
    } finally { $zip.Dispose() }
    function Read-Block([int]$start) {
        $size = [BitConverter]::ToUInt32($bytes, $start)
        $textSize = [BitConverter]::ToUInt32($bytes, $start + 4)
        $count = [BitConverter]::ToUInt32($bytes, $start + 8)
        if ($size -ne $count * 8 + $textSize -or $start + 12 + $size -gt $bytes.Length) { throw 'Invalid string table bounds' }
        $textStart = $start + 12 + $count * 8
        $result = @{}
        for ($i = 0; $i -lt $count; $i++) {
            $hash = [BitConverter]::ToUInt32($bytes, $start + 12 + $i * 8)
            $offset = [BitConverter]::ToUInt32($bytes, $start + 16 + $i * 8)
            $position = $textStart + $offset
            $end = $position
            while ($end -lt $textStart + $textSize -and $bytes[$end] -ne 0) { $end++ }
            if ($end -ge $textStart + $textSize) { throw 'Unterminated string' }
            $result[$hash] = [Text.Encoding]::UTF8.GetString($bytes, $position, $end - $position)
        }
        return $result
    }
    $values = Read-Block ([BitConverter]::ToUInt32($bytes, 132))
    $keys = Read-Block ([BitConverter]::ToUInt32($bytes, 136))
    $result = @{}
    foreach ($hash in $keys.Keys) { $result[$name + '.' + $keys[$hash]] = $values[$hash] }
    return $result
}
