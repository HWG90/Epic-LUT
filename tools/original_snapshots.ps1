param([string]$GameData='',[Parameter(Mandatory=$true)][string]$Output,[int]$OwnerPID=0,[switch]$IndexOnly,[string]$Wanted='')
$ErrorActionPreference='Stop'
try {
 New-Item -ItemType Directory -Path $Output -Force | Out-Null
 $errorFile=Join-Path $Output 'error.txt';if(Test-Path -LiteralPath $errorFile){Remove-Item -LiteralPath $errorFile}
 $cancelFile=Join-Path $Output 'progress.txt.cancel';if(Test-Path -LiteralPath $cancelFile){Remove-Item -LiteralPath $cancelFile}
 [IO.File]::WriteAllText((Join-Path $Output 'progress.txt'),'Locating game data...')
 if(!$GameData){throw 'GameData must be supplied by the editor'}
 $index=Join-Path $GameData 'bundles.nxa'
 [IO.File]::WriteAllText((Join-Path $Output 'progress.txt'),'Checking original LUT cache...')
 $stream=[IO.File]::OpenRead($index);$sha=[Security.Cryptography.SHA256]::Create()
 try {$stamp=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')} finally {$stream.Dispose();$sha.Dispose()}
 $marker=Join-Path $Output $(if($IndexOnly){'index-complete.txt'}else{'complete.txt'})
 $versionFolder=Join-Path $Output $stamp
 if($IndexOnly -and (Test-Path -LiteralPath $marker) -and ([IO.File]::ReadAllLines($marker)[0] -eq $stamp) -and (Test-Path -LiteralPath (Join-Path $versionFolder 'catalog.txt'))){exit 0}
 if(Test-Path -LiteralPath $marker){Remove-Item -LiteralPath $marker}
 New-Item -ItemType Directory -Path $versionFolder -Force | Out-Null
 New-Item -ItemType Directory -Path $Output -Force | Out-Null
 [IO.File]::WriteAllText((Join-Path $Output 'progress.txt'),'Preparing snapshot reader...')
 Add-Type -Path (Join-Path $PSScriptRoot 'original_snapshots.cs')
 [IO.File]::WriteAllText((Join-Path $Output 'progress.txt'),'Reader ready; checking editor heartbeat...')
 $wantedPath=if($IndexOnly){$null}else{$Wanted}
 if(!$IndexOnly -and !(Test-Path -LiteralPath $Wanted)){throw 'Equipped LUT request missing'}
 $count=[EpicOriginalReader]::Run($GameData,$versionFolder,$OwnerPID,(Join-Path $Output 'progress.txt'),$wantedPath)
 if($count -eq 0){throw 'No original material LUTs found'}
 [IO.File]::WriteAllText($marker,$stamp+"`n"+$count)
} catch { [IO.File]::WriteAllText((Join-Path $Output 'error.txt'),$_.Exception.Message);exit 1 }

