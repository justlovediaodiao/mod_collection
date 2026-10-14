param([string]$GameRoot,[switch]$Restore)
$ErrorActionPreference='Stop'
$files=Get-Content "$PSScriptRoot\resources\files.json" -Raw|ConvertFrom-Json
$backup=Join-Path $GameRoot 'FH2_SPIRE_CHS_Backup'
foreach($f in $files){
 $target=Join-Path $GameRoot $f.Path
 $hash=(Get-FileHash -LiteralPath $target).Hash
if($hash -notin @($f.OriginalSHA256,$f.PatchedSHA256)){throw "文件版本不匹配，未安装：$target"}
 if($f.Delta){
}elseif($Restore){$saved=Join-Path $backup $f.Path;if(!(Test-Path -LiteralPath $saved) -or (Get-FileHash -LiteralPath $saved).Hash -ne $f.OriginalSHA256){throw '原版备份不存在或校验失败。'}}
 elseif((Get-FileHash -LiteralPath (Join-Path "$PSScriptRoot\resources\payload" $f.Path)).Hash -ne $f.PatchedSHA256){throw '汉化文件校验失败。'}
}
foreach($f in $files){
 $target=Join-Path $GameRoot $f.Path;$saved=Join-Path $backup $f.Path
 if($f.Delta){
  $hash=(Get-FileHash -LiteralPath $target).Hash
  if($Restore -and $hash -eq $f.PatchedSHA256){$s=[IO.File]::Open($target,[IO.FileMode]::Open,[IO.FileAccess]::Write);try{$s.SetLength([long]$f.OriginalLength)}finally{$s.Dispose()}}
  elseif(!$Restore -and $hash -eq $f.OriginalSHA256){
   $s=[IO.File]::Open($target,[IO.FileMode]::Open,[IO.FileAccess]::Write)
   try{$s.Position=$s.Length;$d=[IO.File]::OpenRead((Join-Path "$PSScriptRoot\resources" $f.Delta));try{$d.CopyTo($s)}finally{$d.Dispose()}}catch{$s.SetLength([long]$f.OriginalLength);throw}finally{$s.Dispose()}
  }
  $expected=if($Restore){$f.OriginalSHA256}else{$f.PatchedSHA256};if((Get-FileHash -LiteralPath $target).Hash -ne $expected){throw "字幕安装校验失败 $target"};continue
 }
 if($Restore){if((Get-FileHash -LiteralPath $saved).Hash -ne $f.OriginalSHA256){throw '备份校验失败。'};Copy-Item -LiteralPath $saved -Destination $target -Force}
 else{
  if(!(Test-Path -LiteralPath $saved)){if((Get-FileHash -LiteralPath $target).Hash -ne $f.OriginalSHA256){throw '缺少原版备份。'};New-Item -ItemType Directory -Path (Split-Path $saved) -Force|Out-Null;Copy-Item -LiteralPath $target -Destination $saved}
  Copy-Item -LiteralPath (Join-Path "$PSScriptRoot\resources\payload" $f.Path) -Destination $target -Force
 }
 $expected=if($Restore){$f.OriginalSHA256}else{$f.PatchedSHA256}
 if((Get-FileHash -LiteralPath $target).Hash -ne $expected){throw "写入后校验失败 $target"}
}
if($Restore){'已恢复原版繁体文件。'}else{'已安装简体文字、字幕、字体与法律声明贴图。游戏语言请选择繁体中文（zh-HK）。'}
