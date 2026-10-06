param([string]$Candidate=(Join-Path $PSScriptRoot 'dist\armor_lut_editor\mod.lua'),[ValidateSet('LLL','MDL')][string]$Loader='LLL')
$ErrorActionPreference='Stop'
. "$PSScriptRoot\tools\deploy_guard.ps1"
$installedRoot=Join-Path $env:LOCALAPPDATA "$Loader\Helldivers2\Mods"
$target=Join-Path $installedRoot 'armor_lut_editor'
$log=Join-Path $env:LOCALAPPDATA 'LLL\Helldivers2\Logs\LiveLuaLoader.log'
if($Loader -ne 'LLL') {throw 'MDL reload verification is not implemented; use the reviewed LLL deployment path'}
Assert-PhysicalDestination (Join-Path $target 'mod.lua')
New-Item -ItemType Directory -Force (Join-Path $target 'files'),(Join-Path $target 'presets') | Out-Null
Invoke-GuardedModuleDeployment -Candidate $Candidate -TargetDirectory $target -InstalledRoot $installedRoot -BackupRoot "$PSScriptRoot\dist\deployment-backups" -ReloadLog $log -ReloadMarker 'live/armor_lut_editor: loaded'
