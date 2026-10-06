param([string]$Python=(Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'),[string]$Workspace=(Join-Path $env:LOCALAPPDATA 'LLL\Helldivers2\Mods\armor_lut_editor\files'),[int]$Port=8765,[switch]$RestartOwn)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\tools\deploy_guard.ps1"
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
        if(-not $running.CommandLine.Contains('tools\companion.py') -or $running.ExecutablePath -ne $Python) {throw 'Recorded process is not the owned companion; refused restart'}
        Stop-Process -Id $prior.pid
    }
    Remove-Item -LiteralPath $ready
}
$argsList=@('-u',('"'+$PSScriptRoot+'\tools\companion.py"'),'--workspace',('"'+$Workspace+'"'),'--port',$Port,'--ready',('"'+$ready+'"'))
$process=Start-Process -FilePath $Python -ArgumentList $argsList -WindowStyle Hidden -PassThru -RedirectStandardOutput "$PSScriptRoot\dist\companion\stdout.log" -RedirectStandardError "$PSScriptRoot\dist\companion\stderr.log"
for($i=0;$i -lt 30;$i++) {
    Start-Sleep -Milliseconds 200
    if(Test-Path -LiteralPath $ready) {Get-Content -LiteralPath $ready;return}
    if($process.HasExited) {throw 'Companion failed; inspect dist/companion/stderr.log'}
}
throw 'Companion did not become ready; inspect its logs before retrying'
