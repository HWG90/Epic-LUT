param([string]$Python='')
$ErrorActionPreference='Stop'
. "$PSScriptRoot\tools\deploy_guard.ps1"
. "$PSScriptRoot\tools\runtime_paths.ps1"
$Python=Resolve-PythonRuntime $Python
Assert-UnvirtualizedPath $Python
Assert-UnvirtualizedPath (Get-PhysicalFilePath $Python)
$serviceRoot=Join-Path $env:LOCALAPPDATA 'Epic LUT\cache\file-service'
$settingsRoot=Join-Path $env:LOCALAPPDATA 'Epic LUT\settings'
New-Item -ItemType Directory -Force $serviceRoot,$settingsRoot | Out-Null
& $Python -m pip install --target "$serviceRoot\.deps" -r "$PSScriptRoot\requirements-companion.txt"
if($LASTEXITCODE -ne 0) {throw 'File service dependency installation failed'}
Set-Content -LiteralPath (Join-Path $settingsRoot 'python-runtime.txt') -Value $Python
