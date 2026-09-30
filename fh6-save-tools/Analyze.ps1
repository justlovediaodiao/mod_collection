param(
    [Parameter(Mandatory)][string]$SessionPath,
    [Parameter(Mandatory)][string]$GameDirectory,
    [ValidatePattern('^[A-Z]{2,3}$')][string]$Language = 'EN'
)
. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'Strings.ps1')
$session = Read-Session $SessionPath
Initialize-ProfileTools
$work = $session.WorkDirectory
$original = Join-Path $work 'original.bin'
$inspection = Join-Path $work 'inspection'
$assets = Join-Path $inspection 'assets'
[ForzaCryptoTool.LocalJournalInspector]::Inspect($original,$inspection)
[ForzaCryptoTool.LocalJournalInspector]::InspectCollectionAssets((Resolve-Path -LiteralPath (Join-Path $GameDirectory 'media\ObjectModelGame.zip')).Path,$assets)
$script:StringTablesPath = (Resolve-Path -LiteralPath (Join-Path $GameDirectory ('media\Stripped\StringTables\' + $Language + '.zip'))).Path
$tables = @{}
function Translate([string]$key) {
    if (-not $key) { return '' }
    if ($key -notmatch '^([^\.]+)\.') { return $key }
    $table = $Matches[1]
    if (-not $tables.ContainsKey($table)) { $tables[$table] = Read-StringTable $table }
    if (-not $tables[$table].ContainsKey($key)) { return '[Unresolved text] ' + $key }
    return $tables[$table][$key]
}
$catalog = Get-Content (Join-Path $assets 'catalog.json') -Raw | ConvertFrom-Json
function Read-Asset([string]$type) {
    $file = @($catalog | Where-Object Type -eq $type)
    if ($file.Count -ne 1) { throw "The game asset type is not unique: $type" }
    return (Get-Content (Join-Path $assets $file[0].Output) -Raw | ConvertFrom-Json -Depth 150).Children[0]
}
$challengeMap = @{}
foreach ($entry in (Prop (Read-Asset 'ChallengeDataSet') 'Data').Children) { $challengeMap[(Attr $entry.Children[0] 'value')] = $entry.Children[1] }
$itemMap = @{}
foreach ($entry in (Prop (Read-Asset 'CollectionItemChallengeDataSet') 'Data').Children) { $itemMap[(Attr $entry.Children[0] 'value')] = $entry.Children[1] }
$campaigns = @{}
foreach ($file in ($catalog | Where-Object Type -eq CollectionCampaignData)) {
    $campaign = (Get-Content (Join-Path $assets $file.Output) -Raw | ConvertFrom-Json -Depth 100).Children[0]
    $kind = Attr (Prop $campaign 'ObjectiveType') 'value'
    $id = if ($kind -eq 'CollectionCampaignFestival') { 'e366b86a-fbce-3a49-a0a8-2895039655db' } elseif ($kind -eq 'CollectionCampaignDiscovery') { '6d6bd7ca-be43-5f46-bdba-093615786170' } else { throw "Unknown campaign type: $kind" }
    $campaigns[$id] = [pscustomobject]@{Name=Translate (Attr (Prop $campaign 'Name') 'value');Bucket=Attr (Prop $campaign 'ProgressBucket') 'value';CurrencyType=Attr (Prop $campaign 'ProgressCurrencyType') 'value'}
}
$tree = Get-Content (Join-Path $inspection 'state-tree.json') -Raw | ConvertFrom-Json -Depth 150
function Read-Currencies($node) {
    if ($node.Name -eq 'map_element') {
        $key = Attr ($node.Children | Where-Object Name -eq 'key') 'value'
        if ($key -like 'CurrencyBucket_*') {
            $value = $node.Children | Where-Object Name -eq 'value'
            [pscustomobject]@{Key=$key;Name=Attr (Prop $value 'Name') 'value';Type=Attr (Prop $value 'Type') 'value';Total=[int](Attr (Prop $value 'Total') 'value')}
        }
    }
    foreach ($child in $node.Children) { Read-Currencies $child }
}
$currencies = @(Read-Currencies $tree)
$record = @(Get-Content (Join-Path $inspection 'records.json') -Raw | ConvertFrom-Json | Where-Object Name -eq 'CollectionCampaignSaveState')
if ($record.Count -ne 1) { throw 'CollectionCampaignSaveState is not unique.' }
$bytes = [IO.File]::ReadAllBytes((Join-Path $inspection ('record-' + $record[0].Ordinal + '.bin')))
$index = [ForzaCryptoTool.JournalEditor]::Index($bytes)
$boundaries = @(foreach ($id in $itemMap.Keys) { $hash=[ForzaCryptoTool.JournalEditor]::Hash($id); if ($index.ContainsKey($hash)) { $index[$hash] } }) | Sort-Object
$endMap = @{}
for ($i=0; $i -lt $boundaries.Count; $i++) { $endMap[$boundaries[$i]] = if ($i+1 -lt $boundaries.Count) { $boundaries[$i+1] } else { $bytes.Length } }
$aliases = @{japan='brio';japan_races='brio_racing';japan_rivals='brio_rivals';upgrade_and_tuning='upgrades';tanakas_car_auto_story='tanaka_car_auto_story'}
$rows = [Collections.Generic.List[object]]::new()
$summaries = [Collections.Generic.List[object]]::new()
foreach ($file in ($catalog | Where-Object Type -eq CollectionCampaignCategoryData)) {
    $category = (Get-Content (Join-Path $assets $file.Output) -Raw | ConvertFrom-Json -Depth 100).Children[0]
    $categoryName = Translate (Attr (Prop $category 'DisplayName') 'value')
    $entity = Attr (Prop $category 'EntityName') 'value'
    $short = $entity -replace '_category$',''
    if ($aliases.ContainsKey($short)) { $short=$aliases[$short] }
    $currency = @($currencies | Where-Object { $_.Name -eq ('cc_'+$short) -and $_.Type -eq 'CollectionCategoryProgress' })
    if ($currency.Count -ne 1) { throw "The category currency mapping is not unique: $entity" }
    $campaignId = Attr (Prop $category 'CampaignId') 'value'
    $campaign = $campaigns[$campaignId]
    if (-not $campaign) { throw "Unknown campaign: $campaignId" }
    $total = [int](Attr (Prop $category 'Total') 'value')
    $categoryRows = foreach ($reference in (Prop $category 'Challenges').Children) {
        $id = Attr (Prop $reference 'Key') 'value'
        $item = $itemMap[$id]
        $challengeId = Attr (Prop (Prop $item 'Challenge') 'Key') 'value'
        $definition = $challengeMap[$challengeId]
        if (-not $item -or -not $definition) { throw "The item definition is missing: $id" }
        $goals = @((Prop $definition 'Objectives').Children)
        $hash = [ForzaCryptoTool.JournalEditor]::Hash($id)
        $offset=-1; $length=0; $rawDone=$false; $supported=$false; $progress=$null; $threshold=$null; $goalId=$null
        if ($index.ContainsKey($hash)) {
            if ($index[$hash].Count -ne 1) { throw "The item record is not unique: $id" }
            $offset=$index[$hash][0]; $end=$endMap[$offset]; $length=$end-$offset
            if ([BitConverter]::ToUInt64($bytes,$offset+16) -ne [ForzaCryptoTool.JournalEditor]::Hash($challengeId) -or [BitConverter]::ToUInt32($bytes,$offset+28) -ne $goals.Count) { throw "The item identity or objective count does not match: $id" }
            $rawDone=$goals.Count -gt 0
            foreach ($goal in $goals) {
                $gid = Attr (Prop $goal 'Id') 'value'
                $position = [ForzaCryptoTool.JournalEditor]::Find($bytes,[ForzaCryptoTool.JournalEditor]::Hash($gid),$offset+32,$end)
                if ($position -lt 0 -or $bytes[$position+8] -gt 1) { throw "The objective state format does not match: $id" }
                if ($bytes[$position+8] -eq 0) { $rawDone=$false }
            }
            if ($goals.Count -eq 1) {
                $goalId=Attr (Prop $goals[0] 'Id') 'value'
                $stats=Prop $goals[0] 'StatsBucket'
                $value=Attr (Prop $stats 'ThresholdValue') 'value'
                [uint32]$parsedThreshold=0
                if ([uint32]::TryParse($value,[ref]$parsedThreshold)) { $threshold=$parsedThreshold }
                if ($bytes[$offset+41] -eq 1) { $progress=[BitConverter]::ToUInt32($bytes,$offset+42) }
                $supported=(-not $rawDone) -and $length -eq 75 -and $bytes[$offset+41] -eq 1 -and $bytes[$offset+46] -eq 1 -and $null -ne $threshold -and $threshold -gt $progress -and (Attr (Prop $stats 'ThresholdComparison') 'value') -eq 'GreaterThanOrEqual' -and [BitConverter]::ToUInt64($bytes,$offset+47) -eq [BitConverter]::ToUInt64($bytes,$offset+32) -and [BitConverter]::ToUInt64($bytes,$offset+55) -eq 0 -and [BitConverter]::ToUInt64($bytes,$offset+63) -eq 0
            }
        }
        $name=Translate (Attr (Prop $definition 'Name') 'value')
        if (-not $name) { $name=Translate (Attr (Prop $item 'Subtitle') 'value') }
        $row=[pscustomobject]@{Campaign=$campaign.Name;CampaignId=$campaignId;CampaignBucketKey=('CurrencyBucket_'+$campaign.CurrencyType+'_'+$campaign.Bucket);Category=$categoryName;CategoryEntity=$entity;CategoryBucketKey=$currency[0].Key;Name=$name;Description=Translate (Attr (Prop $definition 'Description') 'value');Reward=[int](Attr (Prop $item 'CampaignProgressReward') 'value');Completed=($rawDone -or $currency[0].Total -eq $total);RawObjectiveCompleted=$rawDone;StatusReliable=$true;SupportedEditable=$supported;ExpectedProgress=$progress;TargetProgress=$threshold;ObjectiveCount=$goals.Count;GoalId=$goalId;EntryLength=$length;Offset=$offset;CollectionItemId=$id;ChallengeId=$challengeId}
        $rows.Add($row); $row
    }
    $calculated=($categoryRows | Where-Object Completed | Measure-Object Reward -Sum).Sum
    $reliable=$calculated -eq $currency[0].Total
    foreach ($row in $categoryRows) { $row.StatusReliable=$reliable }
    $summaries.Add([pscustomobject]@{Campaign=$campaign.Name;CampaignId=$campaignId;Category=$categoryName;CategoryEntity=$entity;BucketKey=$currency[0].Key;RecordedProgress=$currency[0].Total;CalculatedProgress=$calculated;Total=$total;Count=$categoryRows.Count;Incomplete=@($categoryRows | Where-Object { -not $_.Completed }).Count;StatusReliable=$reliable})
}
$sourceHash=(Get-FileHash -LiteralPath $original).Hash
[pscustomobject]@{SourceSHA256=$sourceHash;Items=$rows.ToArray();Categories=$summaries.ToArray();Currencies=$currencies} | ConvertTo-Json -Depth 15 | Set-Content (Join-Path $work 'collection.json') -Encoding utf8
$unfinished=@($rows | Where-Object { -not $_.Completed })
$unfinished | ConvertTo-Json -Depth 15 | Set-Content (Join-Path $work 'unfinished.json') -Encoding utf8
$lines=[Collections.Generic.List[string]]::new(); $lines.Add('# Unfinished Collection Journal Items');$lines.Add('');$lines.Add('Source SHA256: '+$sourceHash)
foreach ($group in ($unfinished | Group-Object Category)) { $lines.Add('');$lines.Add('## '+$group.Name);$lines.Add('');foreach ($row in $group.Group) { $mark=if($row.StatusReliable){''}else{'[Needs review] '};$lines.Add('- '+$mark+$row.Name+' ('+$row.Reward+' points): '+$row.Description+'; ID: `'+$row.CollectionItemId+'`') } }
$lines | Set-Content (Join-Path $work 'unfinished.md') -Encoding utf8
$summaries | Where-Object { $_.Incomplete -gt 0 -or -not $_.StatusReliable } | Format-Table -AutoSize
