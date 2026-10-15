param([string]$GameData='',[Parameter(Mandatory=$true)][string]$Output,[int]$OwnerPID=0,[switch]$IndexOnly,[string]$Wanted='')
$ErrorActionPreference='Stop'
try {
 New-Item -ItemType Directory -Path $Output -Force | Out-Null
 $marker=Join-Path $Output $(if($IndexOnly){'index-complete.txt'}else{'complete.txt'})
 $errorFile=Join-Path $Output 'error.txt';if(Test-Path -LiteralPath $errorFile){Remove-Item -LiteralPath $errorFile}
 $cancelFile=Join-Path $Output 'progress.txt.cancel';if(Test-Path -LiteralPath $cancelFile){Remove-Item -LiteralPath $cancelFile}
 [IO.File]::WriteAllText((Join-Path $Output 'progress.txt'),'Locating game data...')
 if(!$GameData){throw 'GameData must be supplied by the editor'}
 [IO.File]::WriteAllText((Join-Path $Output 'progress.txt'),'Preparing snapshot reader...')
 Add-Type -Path (Join-Path $PSScriptRoot 'original_snapshots.cs')
 [IO.File]::WriteAllText((Join-Path $Output 'progress.txt'),'Checking patched original LUT sources...')
 $stamp=[EpicOriginalReader]::SourceStamp($GameData,$OwnerPID,(Join-Path $Output 'progress.txt'))
 $versionFolder=Join-Path $Output $stamp
 $schema=Join-Path $versionFolder 'patch-source-v7.txt'
 if($IndexOnly -and (Test-Path -LiteralPath $schema) -and (Test-Path -LiteralPath $marker) -and ([IO.File]::ReadAllLines($marker)[0] -eq $stamp) -and (Test-Path -LiteralPath (Join-Path $versionFolder 'catalog.txt'))){exit 0}
 if(Test-Path -LiteralPath $marker){Remove-Item -LiteralPath $marker}
 New-Item -ItemType Directory -Path $versionFolder -Force | Out-Null
 New-Item -ItemType Directory -Path $Output -Force | Out-Null
 [IO.File]::WriteAllText((Join-Path $Output 'progress.txt'),'Reader ready; checking editor heartbeat...')
 $wantedPath=if($IndexOnly){$null}else{$Wanted}
 if(!$IndexOnly -and !(Test-Path -LiteralPath $Wanted)){throw 'Equipped LUT request missing'}
 $count=[EpicOriginalReader]::RunChecked($GameData,$versionFolder,$OwnerPID,(Join-Path $Output 'progress.txt'),$wantedPath,$stamp)
 if($count -eq 0){throw 'No original material LUTs found'}
 if(!$IndexOnly){
  $arrowheadFolder=Join-Path $versionFolder 'arrowhead'
  try {[EpicOriginalReader]::RunArrowhead($GameData,$arrowheadFolder,$OwnerPID,(Join-Path $Output 'progress.txt'),$wantedPath,$stamp) | Out-Null}
  catch {[IO.File]::WriteAllText((Join-Path $versionFolder 'arrowhead-error.txt'),$_.Exception.Message)}
 }
 [IO.File]::WriteAllText($marker,$stamp+"`n"+$count)
 if($IndexOnly){[IO.File]::WriteAllText($schema,'3x1 and 23x1-64; numeric layers and byte-identical archive aliases')}
} catch { if($marker -and (Test-Path -LiteralPath $marker)){Remove-Item -LiteralPath $marker};[IO.File]::WriteAllText((Join-Path $Output 'error.txt'),$_.Exception.Message);exit 1 }

