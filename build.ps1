param([string]$Python=(Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'),[switch]$Verify)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\tools\deploy_guard.ps1"
Assert-UnvirtualizedPath $Python
Assert-UnvirtualizedPath (Get-PhysicalFilePath $Python)
Push-Location $PSScriptRoot
try {
    & $Python build.py
    if($LASTEXITCODE -ne 0) {throw 'Epic LUT build failed'}
    if($Verify) {& $Python verify.py;if($LASTEXITCODE -ne 0) {throw 'Epic LUT verification failed'}}
} finally {Pop-Location}
