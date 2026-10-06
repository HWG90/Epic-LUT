$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\tools\deploy_guard.ps1"
function Reject([scriptblock]$Action) {try {& $Action}catch{return};throw 'Unsafe case was accepted'}
Reject {Assert-UnvirtualizedPath 'C:\Users\test\AppData\Local\Microsoft\WindowsApps\python.exe'}
Reject {Assert-UnvirtualizedPath 'C:\Users\test\AppData\Local\Packages\PythonSoftwareFoundation.Python\LocalCache\Local\LLL\mod.lua'}
Reject {Assert-IntendedTarget 'C:\outside\mod.lua' 'C:\intended\Mods'}
Reject {Assert-HashEquals ('A'*64) ('B'*64)}
Assert-UnvirtualizedPath 'C:\runtimes\python\python.exe'
Assert-HashEquals ('A'*64) ('A'*64)
Assert-PhysicalDestination (Get-PhysicalFilePath "$PSScriptRoot\..\src\editor.lua")
Write-Output 'PASS: Store/LocalCache rejection, intended-root containment, mismatch stop, physical file-handle verification'
