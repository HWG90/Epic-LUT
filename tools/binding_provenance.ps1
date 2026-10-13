param([string]$GameData='', [Parameter(Mandatory=$true)][string]$Output,
      [Parameter(Mandatory=$true)][string]$Request, [int]$OwnerPID=0,
      [ValidateSet('stock','weapon_effective')][string]$Mode='stock')
$ErrorActionPreference='Stop'
$cacheValidated=$false
function Assert-CachePath([string]$Path) {
 for($at=[IO.Path]::GetFullPath($Path);$at;$at=[IO.Path]::GetDirectoryName($at)) {
  if(Test-Path -LiteralPath $at) {
   $item=Get-Item -LiteralPath $at -Force
   if($item.LinkType -eq 'SymbolicLink' -or $item.LinkType -eq 'Junction'){throw 'Binding provenance cache/request path is redirected'}
  }
 }
}
function Write-AtomicText([string]$Path,[string]$Text) {
 Assert-CachePath $Path
 $temporary=$Path+'.'+[Guid]::NewGuid().ToString('N')+'.pending'
 try {
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes($Text)
  $stream=[IO.FileStream]::new($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try {$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)} finally {$stream.Dispose()}
  if([IO.File]::Exists($Path)){[IO.File]::Replace($temporary,$Path,[System.Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temporary,$Path)}
 } finally {if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}
function Get-Stamp([string]$Path) {
 $stream=[IO.File]::OpenRead($Path);$sha=[Security.Cryptography.SHA256]::Create()
 try {return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')} finally {$stream.Dispose();$sha.Dispose()}
}
try {
 if(!$GameData){throw 'GameData must be supplied by the editor'}
 $gameRoot=[IO.Path]::GetFullPath($GameData).TrimEnd('\')+'\'
 $outputRoot=[IO.Path]::GetFullPath($Output).TrimEnd('\')
 $requestFile=[IO.Path]::GetFullPath($Request)
 if(($outputRoot+'\').StartsWith($gameRoot,[StringComparison]::OrdinalIgnoreCase) -or
    $requestFile.StartsWith($gameRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Binding provenance cache/request cannot be inside game data'}
 if($OwnerPID -lt 0){throw 'Binding provenance owner PID is invalid'}
 Assert-CachePath $outputRoot
 Assert-CachePath $requestFile
 if(![IO.File]::Exists($requestFile) -or ([IO.FileInfo]::new($requestFile)).Length -gt 4096){throw 'Binding provenance request byte bounds'}
 New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
 foreach($name in @('error.txt','progress.txt.cancel','progress.txt','complete.txt','owner-heartbeat.txt')){Assert-CachePath (Join-Path $outputRoot $name)}
 $cacheValidated=$true
 $errorFile=Join-Path $outputRoot 'error.txt';if(Test-Path -LiteralPath $errorFile){Remove-Item -LiteralPath $errorFile}
 $cancelFile=Join-Path $outputRoot 'progress.txt.cancel';if(Test-Path -LiteralPath $cancelFile){Remove-Item -LiteralPath $cancelFile}
 $marker=Join-Path $outputRoot 'complete.txt';if(Test-Path -LiteralPath $marker){Remove-Item -LiteralPath $marker}
 $status=Join-Path $outputRoot 'progress.txt'
 Write-AtomicText $status 'Checking binding provenance game index...'
 $index=Join-Path $gameRoot 'bundles.nxa';$stamp=Get-Stamp $index;$requestFileStamp=Get-Stamp $requestFile;$requestStamp=$requestFileStamp
 if($Mode -eq 'weapon_effective') {
  $sha=[Security.Cryptography.SHA256]::Create()
  try {$requestStamp=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Mode+"`n"+$requestStamp))).Replace('-','')} finally {$sha.Dispose()}
 }
 $versionFolder=Join-Path (Join-Path $outputRoot $stamp) $requestStamp
 Assert-CachePath $versionFolder
 New-Item -ItemType Directory -Path $versionFolder -Force | Out-Null
 # Deterministic raw names are chosen by the reader. Validate existing cache
 # children before replacing them; reject links, including metadata files.
 foreach($child in Get-ChildItem -LiteralPath $versionFolder -Force){Assert-CachePath $child.FullName}
 Write-AtomicText $status 'Preparing binding provenance archive reader...'
 $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'original_snapshots.cs'))+"`n"+[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'binding_provenance_reader.cs'))
 $imports=[regex]::Matches($source,'(?m)^using [^;]+;') | ForEach-Object {$_.Value} | Select-Object -Unique
 $body=[regex]::Replace($source,'(?m)^using [^;]+;\r?\n?','')
 Add-Type -TypeDefinition (($imports -join "`n")+"`n"+$body)
 $count=[EpicBindingProvenanceReader]::Run($gameRoot,$versionFolder,$requestFile,$OwnerPID,$status,$Mode)
 if($count -lt 2){throw 'Binding provenance resource set is incomplete'}
 if((Get-Stamp $index) -ne $stamp){throw 'Game index changed during binding provenance extraction'}
 if((Get-Stamp $requestFile) -ne $requestFileStamp){throw 'Binding provenance request changed during extraction'}
 if(Test-Path -LiteralPath $cancelFile){throw 'Binding provenance extraction canceled'}
 $schema=if($Mode -eq 'weapon_effective'){'2'}else{'1'}
 Write-AtomicText $marker ($versionFolder+"`n"+$schema+"`n"+$stamp+"`n")
 Write-Output $versionFolder
} catch {
 if($cacheValidated -and [IO.Directory]::Exists($outputRoot)) {
  try {Write-AtomicText (Join-Path $outputRoot 'error.txt') $_.Exception.Message} catch {}
 }
 Write-Error $_.Exception.Message -ErrorAction Continue
 exit 1
}
