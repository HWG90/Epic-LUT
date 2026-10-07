param([Parameter(Mandatory=$true)][string]$RuntimeHash,[string]$BundleDirectory='',[string]$GameData='',[string]$Workspace=(Join-Path $env:LOCALAPPDATA 'Epic LUT\files'),[int]$Port=8765,[switch]$RestartOwn,[int]$OwnerPID=0,[string]$FlatManifestHash='')
$ErrorActionPreference='Stop'
$serviceRoot=Split-Path -Parent $PSScriptRoot
$logRoot=Join-Path $serviceRoot 'dist\companion'
New-Item -ItemType Directory -Force $logRoot | Out-Null
try {
    # A parent running PowerShell 7 can pass its module path to Windows PowerShell.
    Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
    Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Archive\Microsoft.PowerShell.Archive.psd1') -ErrorAction Stop
    if($RuntimeHash -notmatch '^[a-f0-9]{64}$') {throw 'Invalid bundled runtime identity'}
    $runtimeRoot=Join-Path $serviceRoot ('runtime-'+$RuntimeHash.Substring(0,16))
    $marker=Join-Path $runtimeRoot 'runtime-ready.txt'
    $python=Join-Path $runtimeRoot 'python.exe'
    if($FlatManifestHash -and -not (Test-Path -LiteralPath $marker)){
        $flatSources=@()
        if($BundleDirectory){$flatSources+=Join-Path $BundleDirectory 'runtime'}
        if($GameData){$flatSources+=Join-Path (Split-Path -Parent $GameData) 'EpicLUTRuntime'}
        foreach($flatSource in $flatSources){
            if(Test-Path -LiteralPath (Join-Path $flatSource 'FLAT-MANIFEST.json')){
                & (Join-Path $PSScriptRoot 'install_flat_runtime.ps1') -SourceRuntime $flatSource -DestinationRuntime $runtimeRoot -RuntimeHash $RuntimeHash -ManifestHash $FlatManifestHash
                break
            }
        }
    }
    if(-not ((Test-Path -LiteralPath $marker) -and (Get-Content -LiteralPath $marker -Raw).Trim() -eq $RuntimeHash -and (Test-Path -LiteralPath $python))) {
        $sources=@()
        if($BundleDirectory) {$sources+=Join-Path $BundleDirectory 'runtime.zip'}
        if($GameData -and (Test-Path -LiteralPath $GameData)) {
            $sources+=@(Get-ChildItem -LiteralPath $GameData -Filter '9ba626afa44a3aa3.patch_*.stream' -File | Select-Object -ExpandProperty FullName)
        }
        $source=$null
        foreach($candidate in $sources) {
            if((Test-Path -LiteralPath $candidate) -and (Get-Item -LiteralPath $candidate).Length -le 67108864 -and (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant() -eq $RuntimeHash) {$source=$candidate;break}
        }
        if(-not $source) {throw 'Bundled runtime is missing or damaged. For the flat package, extract it and run Install-Runtime.ps1 once; otherwise reinstall the complete package including its stream file.'}
        $archive=Join-Path $serviceRoot ('runtime-'+$RuntimeHash.Substring(0,16)+'.zip')
        Copy-Item -LiteralPath $source -Destination $archive -Force
        if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $RuntimeHash) {throw 'Bundled runtime changed during copy'}
        Expand-Archive -LiteralPath $archive -DestinationPath $runtimeRoot -Force
        & $python -c 'import numpy, OpenEXR, ctypes, http.server'
        if($LASTEXITCODE -ne 0) {throw 'Bundled runtime codec check failed'}
        Set-Content -LiteralPath $marker -Value $RuntimeHash -Encoding ASCII
    }
    & (Join-Path $serviceRoot 'start_editor.ps1') -Python $python -Workspace $Workspace -Port $Port -RestartOwn:$RestartOwn -OwnerPID $OwnerPID
} catch {
    $_ | Out-String | Set-Content -LiteralPath (Join-Path $logRoot 'startup-error.log')
    throw
}
