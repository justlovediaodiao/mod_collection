param(
    [Parameter(Mandatory)][string]$SessionPath,
    [Parameter(Mandatory)][string[]]$ItemId,
    [switch]$IncludeCategoryCompletions
)
. (Join-Path $PSScriptRoot 'Common.ps1')
$session=Read-Session $SessionPath
$work=$session.WorkDirectory
$collection=Get-Content (Join-Path $work 'collection.json') -Raw | ConvertFrom-Json
if ((Get-FileHash -LiteralPath (Join-Path $work 'original.bin')).Hash -ne $collection.SourceSHA256) { throw 'The analysis does not match the current plaintext. Run analysis again.' }
$selected=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($id in $ItemId) {
    $match=@($collection.Items | Where-Object CollectionItemId -eq $id)
    if ($match.Count -ne 1) { throw "The item ID is missing or not unique: $id" }
    if ($match[0].Completed) { throw "The item is already complete: $($match[0].Name)" }
    $null=$selected.Add($id)
}
if ($IncludeCategoryCompletions) {
    do {
        $added=$false
        foreach ($category in $collection.Categories) {
            # The category's own final/self-referencing item is outside this automatic rule.
            if ($category.CategoryEntity -eq 'horizon_legend_category') { continue }
            $delta=($collection.Items | Where-Object { $_.CategoryEntity -eq $category.CategoryEntity -and $selected.Contains($_.CollectionItemId) } | Measure-Object Reward -Sum).Sum
            if ($category.RecordedProgress+$delta -ne $category.Total) { continue }
            $linked=@($collection.Items | Where-Object { $_.CategoryEntity -eq 'horizon_legend_category' -and $_.CampaignId -eq $category.CampaignId -and $_.Name -eq $category.Category -and -not $_.Completed })
            if ($linked.Count -gt 1) { throw 'The linked category completion item is not unique.' }
            if ($linked.Count -eq 1 -and $selected.Add($linked[0].CollectionItemId)) { $added=$true }
        }
    } while ($added)
}
$entries=foreach ($row in $collection.Items) {
    if (-not $selected.Contains($row.CollectionItemId)) { continue }
    if (-not $row.StatusReliable -or -not $row.SupportedEditable -or $row.ObjectiveCount -ne 1) { throw "The item failed format or point checks and cannot be edited: $($row.Category) / $($row.Name)" }
    [pscustomobject]@{Category=$row.Category;Name=$row.Name;CollectionItemId=$row.CollectionItemId;ChallengeId=$row.ChallengeId;GoalId=$row.GoalId;ExpectedProgress=[uint32]$row.ExpectedProgress;TargetProgress=[uint32]$row.TargetProgress;EntryLength=$row.EntryLength;Reward=$row.Reward}
}
$deltas=@{}
foreach ($row in $collection.Items) {
    if (-not $selected.Contains($row.CollectionItemId)) { continue }
    foreach ($key in @($row.CategoryBucketKey,$row.CampaignBucketKey)) {
        if (-not $deltas.ContainsKey($key)) { $deltas[$key]=0 }
        $deltas[$key]+=$row.Reward
    }
}
$changes=foreach ($key in ($deltas.Keys | Sort-Object)) {
    $bucket=@($collection.Currencies | Where-Object Key -eq $key)
    if ($bucket.Count -ne 1) { throw "The currency bucket is not unique: $key" }
    $next=[int]$bucket[0].Total+[int]$deltas[$key]
    $category=@($collection.Categories | Where-Object BucketKey -eq $key)
    if ($category.Count -eq 1 -and $next -gt $category[0].Total) { throw 'The planned category points exceed the maximum.' }
    [pscustomobject]@{Key=$key;Before=[int]$bucket[0].Total;After=$next}
}
$plan=Join-Path $work 'plan.json'
if (Test-Path -LiteralPath $plan) { throw 'plan.json already exists. Review the existing plan or start a new session.' }
[pscustomobject]@{SourceSHA256=$collection.SourceSHA256;IncludeCategoryCompletions=$IncludeCategoryCompletions.IsPresent;Entries=@($entries);CurrencyChanges=@($changes)} | ConvertTo-Json -Depth 15 | Set-Content $plan -Encoding utf8
$entries | Select-Object Category,Name,ExpectedProgress,TargetProgress,Reward | Format-Table
$changes | Format-Table
$plan
