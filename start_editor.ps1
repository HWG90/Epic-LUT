param([string]$Python='',[string]$Workspace=(Join-Path $env:LOCALAPPDATA 'Epic LUT\files'),[int]$Port=8765,[switch]$RestartOwn,[int]$OwnerPID=0)
$ErrorActionPreference='Stop'
if(-not $Python -and (Test-Path -LiteralPath "$PSScriptRoot\armor_lut_editor\runtime-manifest.json")) {
    $runtime=Get-Content -LiteralPath "$PSScriptRoot\armor_lut_editor\runtime-manifest.json" -Raw | ConvertFrom-Json
    & "$PSScriptRoot\tools\start_bundled.ps1" -RuntimeHash $runtime.sha256 -BundleDirectory "$PSScriptRoot\armor_lut_editor" -Workspace $Workspace -Port $Port -OwnerPID $OwnerPID -FlatManifestHash $runtime.flat_manifest_sha256
    return
}
trap {
    New-Item -ItemType Directory -Force "$PSScriptRoot\dist\companion" | Out-Null
    $_ | Out-String | Set-Content -LiteralPath "$PSScriptRoot\dist\companion\startup-error.log"
    break
}
. "$PSScriptRoot\tools\deploy_guard.ps1"
. "$PSScriptRoot\tools\runtime_paths.ps1"
$Python=Resolve-PythonRuntime $Python
Assert-UnvirtualizedPath $Python
Assert-UnvirtualizedPath (Get-PhysicalFilePath $Python)
Assert-UnvirtualizedPath $Workspace
if($Workspace.Contains('"')) {throw 'Invalid workspace path'}
New-Item -ItemType Directory -Force "$PSScriptRoot\dist\companion" | Out-Null
$ready="$PSScriptRoot\dist\companion\ready.json"
if(Test-Path -LiteralPath $ready) {
    $prior=Get-Content -LiteralPath $ready -Raw | ConvertFrom-Json
    $running=Get-CimInstance Win32_Process -Filter "ProcessId=$($prior.pid)" -ErrorAction SilentlyContinue
    if($running) {
        if(-not $RestartOwn) {Get-Content -LiteralPath $ready;return}
        if(-not $running.CommandLine.Contains('tools\companion.py') -or $running.ExecutablePath -ne $Python) {throw 'Recorded process is not the owned file service; refused restart'}
        Stop-Process -Id $prior.pid
    }
    Remove-Item -LiteralPath $ready
}
$argsList=@('-u',('"'+$PSScriptRoot+'\tools\companion.py"'),'--workspace',('"'+$Workspace+'"'),'--port',$Port,'--ready',('"'+$ready+'"'),'--owner-pid',$OwnerPID)
$process=Start-Process -FilePath $Python -ArgumentList $argsList -WindowStyle Hidden -PassThru -RedirectStandardOutput "$PSScriptRoot\dist\companion\stdout.log" -RedirectStandardError "$PSScriptRoot\dist\companion\stderr.log"
for($i=0;$i -lt 30;$i++) {
    Start-Sleep -Milliseconds 200
    if(Test-Path -LiteralPath $ready) {Get-Content -LiteralPath $ready;return}
    if($process.HasExited) {throw 'File service failed; inspect dist/companion/stderr.log'}
}
throw 'File service did not become ready; inspect its logs before retrying'
