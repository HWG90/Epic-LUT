param([Parameter(Mandatory=$true)][string]$SourceRuntime,[Parameter(Mandatory=$true)][string]$DestinationRuntime,[Parameter(Mandatory=$true)][string]$RuntimeHash,[Parameter(Mandatory=$true)][string]$ManifestHash)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
if($RuntimeHash -notmatch '^[a-f0-9]{64}$' -or $ManifestHash -notmatch '^[a-f0-9]{64}$'){throw 'Invalid runtime identity'}
$manifestPath=Join-Path $SourceRuntime 'FLAT-MANIFEST.json'
if((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ManifestHash){throw 'Flat runtime manifest changed'}
$manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if($manifest.runtime_identity -ne $RuntimeHash){throw 'Flat runtime version mismatch'}
$sourceRoot=[IO.Path]::GetFullPath($SourceRuntime).TrimEnd('\')+'\'
$targetRoot=[IO.Path]::GetFullPath($DestinationRuntime).TrimEnd('\')+'\'
$entries=@($manifest.files.PSObject.Properties)
if($entries.Count -lt 100 -or $entries.Count -gt 10000){throw 'Invalid runtime file count'}
foreach($entry in $entries){
    $source=[IO.Path]::GetFullPath((Join-Path $sourceRoot $entry.Name))
    $target=[IO.Path]::GetFullPath((Join-Path $targetRoot $entry.Name))
    if(-not $source.StartsWith($sourceRoot,[StringComparison]::OrdinalIgnoreCase) -or -not $target.StartsWith($targetRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Runtime path leaves its folder'}
    if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.Value){throw ('Runtime file changed: '+$entry.Name)}
}
foreach($entry in $entries){
    $source=Join-Path $sourceRoot $entry.Name;$target=Join-Path $targetRoot $entry.Name
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Copy-Item -LiteralPath $source -Destination $target -Force
}
& (Join-Path $targetRoot 'python.exe') -c 'import numpy, OpenEXR, ctypes, http.server'
if($LASTEXITCODE -ne 0){throw 'Flat runtime codec check failed'}
Set-Content -LiteralPath (Join-Path $targetRoot 'runtime-ready.txt') -Value $RuntimeHash -Encoding ASCII
