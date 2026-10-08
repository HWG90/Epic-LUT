param([Parameter(Mandatory=$true)][string]$Review)
$ErrorActionPreference='Stop'
$count=0
foreach($file in Get-ChildItem -LiteralPath (Join-Path $Review 'exports') -Recurse -Filter '*.patch_0') {
 $main=[IO.File]::ReadAllBytes($file.FullName)
 $gpu=[IO.File]::ReadAllBytes($file.FullName+'.gpu_resources')
 $stream=[IO.File]::ReadAllBytes($file.FullName+'.stream')
 $id=[BitConverter]::ToUInt64($main,104).ToString('x16')
 if($id -ne $file.Directory.Name){throw 'Incorrect exact resource ID'}
 if([BitConverter]::ToUInt32($main,0) -ne [Convert]::ToUInt32('f0000011',16) -or [BitConverter]::ToUInt32($main,4) -ne 1 -or [BitConverter]::ToUInt32($main,8) -ne 1){throw 'Invalid archive header'}
 if([BitConverter]::ToUInt64($main,112) -ne [Convert]::ToUInt64('cd4238c6a0c69e32',16)){throw 'Not a texture resource'}
 $at=[int][BitConverter]::ToUInt64($main,120)
 $size=[BitConverter]::ToUInt32($main,160)
 if($at -ne 184 -or $size -ne 340 -or $main.Length -ne $at+$size -or [BitConverter]::ToUInt32($main,168) -ne $gpu.Length -or $stream.Length -ne 0){throw 'Invalid archive/sidecar bounds'}
 $dds=$at+192
 $width=[BitConverter]::ToUInt32($main,$dds+16)
 $height=[BitConverter]::ToUInt32($main,$dds+12)
 if([Text.Encoding]::ASCII.GetString($main,$dds,4) -ne 'DDS ' -or [BitConverter]::ToUInt32($main,$dds+128) -ne 2 -or $gpu.Length -ne $width*$height*16 -or [BitConverter]::ToSingle($gpu,0) -ne 1.25 -or [BitConverter]::ToSingle($gpu,4) -ne -0.125){throw 'Invalid DDS/pixels'}
 Write-Output "PASS independent binary check: $id ${width}x${height} ($($main.Length)/$($gpu.Length)/$($stream.Length) bytes)"
 $count++
}
if($count -ne 3){throw 'Expected all three real-game LUT fixtures'}
