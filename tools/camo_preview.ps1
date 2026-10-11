param([string]$GameData='', [Parameter(Mandatory=$true)][string]$Output, [int]$OwnerPID=0)
$ErrorActionPreference='Stop'
$cacheValidated=$false
function Assert-CachePath([string]$Path) {
 for($at=[IO.Path]::GetFullPath($Path);$at;$at=[IO.Path]::GetDirectoryName($at)) {
  if(Test-Path -LiteralPath $at){
   $item=Get-Item -LiteralPath $at -Force
   if($item.LinkType -eq 'SymbolicLink' -or $item.LinkType -eq 'Junction'){throw 'Camo cache path is redirected'}
  }
 }
}
function Write-AtomicText([string]$Path,[string]$Text) {
 $temporary=$Path+'.'+[Guid]::NewGuid().ToString('N')+'.pending'
 try {
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes($Text)
  $stream=[IO.FileStream]::new($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try {$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)} finally {$stream.Dispose()}
  if([IO.File]::Exists($Path)){[IO.File]::Replace($temporary,$Path,$null)}else{[IO.File]::Move($temporary,$Path)}
 } finally {if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}
function Get-IndexStamp([string]$Path) {
 $stream=[IO.File]::OpenRead($Path);$sha=[Security.Cryptography.SHA256]::Create()
 try {return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')} finally {$stream.Dispose();$sha.Dispose()}
}
try {
 if(!$GameData){throw 'GameData must be supplied by the editor'}
 $gameRoot=[IO.Path]::GetFullPath($GameData).TrimEnd('\')+'\'
 $outputRoot=[IO.Path]::GetFullPath($Output)
 if(($outputRoot+'\').StartsWith($gameRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Camo cache cannot be inside game data'}
 Assert-CachePath $outputRoot
 New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
 foreach($name in @('error.txt','progress.txt.cancel','progress.txt','complete.txt')){Assert-CachePath (Join-Path $outputRoot $name)}
 $cacheValidated=$true
 $errorFile=Join-Path $outputRoot 'error.txt';if(Test-Path -LiteralPath $errorFile){Remove-Item -LiteralPath $errorFile}
 $cancelFile=Join-Path $outputRoot 'progress.txt.cancel';if(Test-Path -LiteralPath $cancelFile){Remove-Item -LiteralPath $cancelFile}
 $marker=Join-Path $outputRoot 'complete.txt';if(Test-Path -LiteralPath $marker){Remove-Item -LiteralPath $marker}
 $status=Join-Path $outputRoot 'progress.txt'
 [IO.File]::WriteAllText($status,'Checking camo preview game index...')
 $index=Join-Path $gameRoot 'bundles.nxa';$stamp=Get-IndexStamp $index
 $versionFolder=Join-Path $outputRoot $stamp
 Assert-CachePath $versionFolder
 New-Item -ItemType Directory -Path $versionFolder -Force | Out-Null
 foreach($name in @('mask-0.rgba','mask-1.rgba','mask-2.rgba','mask-3.rgba','mask-4.rgba','mask-5.rgba')){Assert-CachePath (Join-Path $versionFolder $name)}
 [IO.File]::WriteAllText($status,'Preparing camo preview reader...')
 $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'original_snapshots.cs'))+"`n"+[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'camo_preview_reader.cs'))
 $imports=[regex]::Matches($source,'(?m)^using [^;]+;') | ForEach-Object {$_.Value} | Select-Object -Unique
 $body=[regex]::Replace($source,'(?m)^using [^;]+;\r?\n?','')
 Add-Type -TypeDefinition (($imports -join "`n")+"`n"+$body)
 $count=[EpicCamoPreviewReader]::Run($gameRoot,$versionFolder,$OwnerPID,$status)
 if($count -ne 6){throw 'Camo preview mask set is incomplete'}
 if((Get-IndexStamp $index) -ne $stamp){throw 'Game index changed during camo extraction'}
 if(Test-Path -LiteralPath $cancelFile){throw 'Camo extraction canceled'}
 Write-AtomicText $marker ($versionFolder+"`n1`n")
 Write-Output $versionFolder
} catch {
 if($cacheValidated -and [IO.Directory]::Exists($outputRoot)){[IO.File]::WriteAllText((Join-Path $outputRoot 'error.txt'),$_.Exception.Message)}
 Write-Error $_.Exception.Message -ErrorAction Continue
 exit 1
}
