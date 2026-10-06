param([string]$Python=(Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'))
$ErrorActionPreference='Stop'
. "$PSScriptRoot\tools\deploy_guard.ps1"
Assert-UnvirtualizedPath $Python
Assert-UnvirtualizedPath (Get-PhysicalFilePath $Python)
& $Python -m pip install --target "$PSScriptRoot\.deps" -r "$PSScriptRoot\requirements-companion.txt"
if($LASTEXITCODE -ne 0) {throw 'Companion dependency installation failed'}
