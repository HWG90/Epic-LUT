param([string]$Package='',[switch]$Pick,[Parameter(Mandatory=$true)][string]$Output,[Parameter(Mandatory=$true)][string]$Result,[int]$OwnerPID=0,[string]$SevenZip='')
$ErrorActionPreference='Stop'
# Data only: ZIP members are never installed or executed. All work is outside the game.
function Check-Owner { if(Test-Path -LiteralPath ($Result+'.cancel')) {throw 'Import canceled'};if($OwnerPID -and -not (Get-Process -Id $OwnerPID -ErrorAction SilentlyContinue)) {throw 'Game exited'} }
$script:phase='starting';$script:lastPulse=0
function Initialize-RarJob {
    # The OS closes this handle on worker exit, including forced recovery, stopping only its 7-Zip children.
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class EpicImportJob {
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern IntPtr CreateJobObject(IntPtr a,string n);
  [DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr j,int c,IntPtr p,uint n);
  [DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr j,IntPtr p);
  static IntPtr job;
  public static void Initialize() {
    job=CreateJobObject(IntPtr.Zero,null);if(job==IntPtr.Zero)throw new Exception("Could not create RAR worker lifetime");
    int size=IntPtr.Size==8?144:112;IntPtr data=Marshal.AllocHGlobal(size);
    try {Marshal.Copy(new byte[size],0,data,size);Marshal.WriteInt32(data,16,0x2000);
      if(!SetInformationJobObject(job,9,data,(uint)size))throw new Exception("Could not configure RAR worker lifetime");
    } finally {Marshal.FreeHGlobal(data);}
  }
  public static void Attach(IntPtr process) {
    if(!AssignProcessToJobObject(job,process))throw new Exception("Could not own the RAR extraction process");
  }
}
'@
    [EpicImportJob]::Initialize()
}
function Pulse($Phase='') {
    Check-Owner
    if($Phase) {$script:phase=$Phase}
    $now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if($now -ne $script:lastPulse) {
        $script:lastPulse=$now
        $text="$PID`t$script:phase`t$now"
        try {
            [IO.File]::WriteAllText($Result+'.progress.tmp',$text,(New-Object Text.UTF8Encoding($false)))
            if([IO.File]::Exists($Result+'.progress')) {[IO.File]::Replace($Result+'.progress.tmp',$Result+'.progress',$null)}
            else {[IO.File]::Move($Result+'.progress.tmp',$Result+'.progress')}
        } catch {}
    }
}
function Finish-Process($Process) {
    if($Process) {if(-not $Process.HasExited) {$Process.Kill();$Process.WaitForExit(3000)|Out-Null};$Process.Dispose()}
}
function Open-Member($Entry) {
    if($Entry.Zip) {return @{Stream=$Entry.Zip.Open();Process=$null}}
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$SevenZip;$info.Arguments='x -so -y -spd -- "'+$Package+'" "'+$Entry.Name+'"'
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $process=[Diagnostics.Process]::Start($info)
    try {if(-not $process.HasExited) {[EpicImportJob]::Attach($process.Handle)}}catch {Finish-Process $process;throw}
    $errors=$process.StandardError.ReadToEndAsync()
    return @{Stream=$process.StandardOutput.BaseStream;Process=$process;Errors=$errors}
}
function Read-Header($Entry) {
    $opened=Open-Member $Entry;$bytes=New-Object byte[] 148;$done=0
    try {
        while($done -lt 148) {
            $task=$opened.Stream.ReadAsync($bytes,$done,148-$done)
            while(-not $task.Wait(200)) {Pulse 'reading'}
            $n=$task.GetAwaiter().GetResult();if($n -eq 0) {throw 'Truncated DDS'};$done+=$n
        }
        return ,$bytes
    } finally {Finish-Process $opened.Process;$opened.Stream.Dispose()}
}
function U32($Bytes,$At) { [BitConverter]::ToUInt32($Bytes,$At) }
function U64($Bytes,$At) { [BitConverter]::ToUInt64($Bytes,$At) }
function Slice($Bytes,$At,$Size) {
    if($At -gt $Bytes.Length -or $Size -gt $Bytes.Length-$At) {throw 'Resource range leaves archive'}
    $copy=New-Object byte[] $Size
    [Array]::Copy($Bytes,[long]$At,$copy,0,[long]$Size)
    return ,$copy
}
function Publish($Text) {
    [IO.File]::WriteAllText($Result+'.tmp',$Text,(New-Object Text.UTF8Encoding($false)))
    [IO.File]::Move($Result+'.tmp',$Result)
}
try {
    Pulse 'starting'
    if($Pick) {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog=New-Object Windows.Forms.OpenFileDialog
        $dialog.Filter='LUT palettes or mod archives (*.dds;*.zip;*.rar)|*.dds;*.zip;*.rar'
        $dialog.Title='Epic LUT - Choose a palette or mod archive'
        $timer=New-Object Windows.Forms.Timer
        $timer.Interval=500
        $timer.Add_Tick({try {Pulse 'picker'} catch {try {Publish 'cancel'} finally {[Environment]::Exit(0)}}})
        try {
            Pulse 'picker';$timer.Start()
            if($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) {Publish "cancel";return}
            $Package=$dialog.FileName
        } finally {$timer.Stop();$timer.Dispose();$dialog.Dispose()}
    }
    if([IO.Path]::GetExtension($Package) -ieq '.dds') {
        if((Get-Item -LiteralPath $Package).Length -gt 1MB) {throw 'DDS size budget exceeded'}
        New-Item -ItemType Directory -Path $Output -ErrorAction Stop | Out-Null
        [IO.File]::Copy($Package,(Join-Path $Output 'lut000.dds'))
        Publish "ok`nlut000.dds";return
    }
    Pulse 'reading'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $entries=@()
    if([IO.Path]::GetExtension($Package) -ieq '.rar') {
        if(-not $SevenZip) {
            $command=Get-Command 7z.exe -ErrorAction SilentlyContinue
            if($command) {$SevenZip=$command.Source}
            else {foreach($candidate in @("$env:ProgramFiles\7-Zip\7z.exe","${env:ProgramFiles(x86)}\7-Zip\7z.exe")) {if(Test-Path -LiteralPath $candidate) {$SevenZip=$candidate;break}}}
        }
        if(-not $SevenZip) {throw 'RAR import requires installed 7-Zip. Install 7-Zip or choose a ZIP.'}
        Initialize-RarJob
        $info=New-Object Diagnostics.ProcessStartInfo;$info.FileName=$SevenZip
        $info.Arguments='l -slt -ba -sccUTF-8 -- "'+$Package+'"';$info.UseShellExecute=$false;$info.CreateNoWindow=$true
        $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
        $listing=[Diagnostics.Process]::Start($info)
        try {
            if(-not $listing.HasExited) {[EpicImportJob]::Attach($listing.Handle)}
            $text=$listing.StandardOutput.ReadToEndAsync();$errorText=$listing.StandardError.ReadToEndAsync()
            while(-not $listing.WaitForExit(200)) {Pulse 'reading'}
            if($listing.ExitCode -ne 0) {throw '7-Zip could not read the RAR archive'}
            foreach($block in ($text.Result -split '(?:\r?\n){2,}')) {
                $fields=@{};foreach($line in ($block -split '\r?\n')) {if($line -match '^([^=]+) = (.*)$') {$fields[$matches[1]]=$matches[2]}}
                if(-not $fields.ContainsKey('Path') -or $fields['Folder'] -eq '+') {continue}
                if($fields['Symbolic Link'] -or $fields['Hard Link'] -or $fields['Encrypted'] -eq '+') {throw 'RAR links/encryption are unsupported'}
                $entries+=@{Name=$fields['Path'];Length=[long]$fields['Size'];Zip=$null}
            }
        } finally {Finish-Process $listing}
    } else {
        $zip=[IO.Compression.ZipFile]::OpenRead($Package)
        foreach($entry in $zip.Entries) {
            if((($entry.ExternalAttributes -shr 16) -band 61440) -eq 40960) {throw 'Unsafe ZIP member'}
            $entries+=@{Name=$entry.FullName;Length=$entry.Length;Zip=$entry}
        }
    }
    $members=@{};$staged=@{};$selectedBytes=0
    $staging=Join-Path ([IO.Path]::GetTempPath()) ('epic-lut-zip-'+[Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($staging) | Out-Null
    if($entries.Count -gt 16384) {throw 'ZIP has too many members'}
    foreach($entry in $entries) {
        Pulse
        $name=$entry.Name.Replace('\','/')
        if($name.StartsWith('/') -or $name.Contains(':') -or ($name.Split('/') -contains '..') -or $name.Contains('"') -or $name -match '[\x00-\x1f]') {throw 'Unsafe ZIP member'}
        if($name -notmatch '(?i)(\.dds$|[0-9a-f]{16}\.patch_\d+(\.(gpu_resources|stream))?$)') {continue}
        if($members.ContainsKey($name)) {throw 'Duplicate ZIP member'}
        $members[$name]=$entry
    }
    function Stage($Name) {
        Check-Owner
        if($staged.ContainsKey($Name)) {return $staged[$Name]}
        $entry=$members[$Name];if($null -eq $entry) {return $null}
        if($entry.Length -gt 1GB -or $selectedBytes+$entry.Length -gt 2GB) {throw ('Required patch data exceeds extraction budget: '+$Name)}
        $path=Join-Path $staging ($staged.Count.ToString('D5')+'.bin')
        $opened=Open-Member $entry;$source=$opened.Stream;$destination=[IO.File]::Create($path)
        try {
            $buffer=New-Object byte[] 65536;$written=0
            while($true) {
                $task=$source.ReadAsync($buffer,0,$buffer.Length)
                while(-not $task.Wait(200)) {Pulse 'extracting'}
                $n=$task.GetAwaiter().GetResult();if($n -eq 0) {break}
                Pulse 'extracting';$written+=$n
                if($written -gt $entry.Length) {throw 'Archive member size mismatch'}
                $destination.Write($buffer,0,$n)
            }
            if($opened.Process) {$opened.Process.WaitForExit();if($opened.Process.ExitCode -ne 0) {throw '7-Zip extraction failed'}}
            if($written -ne $entry.Length) {throw 'Archive member size mismatch'}
        } finally {Finish-Process $opened.Process;$source.Dispose();$destination.Dispose()}
        $script:selectedBytes+=$entry.Length;$staged[$Name]=$path;return $path
    }
    function Read-Range($Path,$At,$Size) {
        if($null -eq $Path) {if($Size -eq 0) {return ,[byte[]]@()}else {throw 'Required resource sidecar missing'}}
        $f=[IO.File]::OpenRead($Path)
        try {
            if($Size -gt 8MB -or $At -gt $f.Length -or $Size -gt $f.Length-$At) {throw 'Resource range leaves archive'}
            $f.Position=$At;$bytes=New-Object byte[] $Size;$done=0
            while($done -lt $Size) {$n=$f.Read($bytes,$done,$Size-$done);if($n -eq 0) {throw 'Truncated resource data'};$done+=$n}
            return ,$bytes
        } finally {$f.Dispose()}
    }
    New-Item -ItemType Directory -Path $Output -ErrorAction Stop | Out-Null
    $files=New-Object 'System.Collections.Generic.List[string]'
    function Save-Lut($Bytes) {
        Check-Owner
        if($files.Count -ge 256) {throw 'ZIP contains too many LUTs'}
        $name='lut'+$files.Count.ToString('D3')+'.dds'
        [IO.File]::WriteAllBytes((Join-Path $Output $name),$Bytes);$files.Add($name)
    }
    foreach($name in ($members.Keys | Sort-Object)) {
        if($name -match '(?i)\.dds$') {
            # Inspect only the header of ordinary large textures; copy actual LUTs only.
            $entry=$members[$name];if($entry.Length -lt 148) {continue}
            $header=Read-Header $entry
            if((U32 $header 0) -ne 542327876 -or (U32 $header 16) -ne 23 -or (U32 $header 12) -gt 32) {continue}
            if($entry.Length -gt 1MB) {throw 'LUT DDS payload exceeds 1 MB'}
            $path=Stage $name;Save-Lut (Read-Range $path 0 $entry.Length);continue
        }
        if($name -notmatch '(?i)[0-9a-f]{16}\.patch_\d+$') {continue}
        $path=Stage $name;$length=(Get-Item -LiteralPath $path).Length
        if($length -lt 72) {throw 'Unsupported patch archive'}
        $head=Read-Range $path 0 72
        if((U32 $head 0) -ne 4026531857) {throw 'Unsupported patch archive'}
        $types=U32 $head 4;$entries=U32 $head 8
        $tableStart=72+32*[long]$types;$tableEnd=$tableStart+80*[long]$entries
        if($types -gt 4096 -or ($types -eq 0 -and $entries -gt 0) -or $entries -gt 100000 -or $tableEnd -gt $length) {throw 'Invalid patch resource table'}
        $table=Read-Range $path $tableStart (80*$entries)
        for($i=0;$i -lt $entries;$i++) {
            if($i%256 -eq 0) {Pulse 'extracting'};$at=80*$i
            if((U64 $table ($at+8)) -ne [UInt64]::Parse('CD4238C6A0C69E32',[Globalization.NumberStyles]::HexNumber)) {continue}
            $mainAt=U64 $table ($at+16);$mainSize=U32 $table ($at+56)
            if($mainSize -lt 340) {continue} # No complete DDS header; not an importable LUT.
            if($mainAt -lt $tableEnd -or $mainAt -gt $length -or $mainSize -gt $length-$mainAt) {throw ('Invalid resource offset in '+$name+' record '+$i+' (offset '+$mainAt+', size '+$mainSize+', archive '+$length+')')}
            $main=Read-Range $path $mainAt ([Math]::Min(340,$mainSize))
            if($main.Length -lt 340 -or (U32 $main 192) -ne 542327876) {continue}
            $header=Slice $main 192 148;$w=U32 $header 16;$h=U32 $header 12;$format=U32 $header 128
            if($w -ne 23 -or $h -lt 1 -or $h -gt 32 -or $format -notin @(2,10)) {continue}
            if((U32 $header 84) -ne 808540228 -or (U32 $header 132) -ne 3 -or (U32 $header 136) -ne 0 -or (U32 $header 140) -ne 1) {throw 'Unsupported DDS texture kind'}
            $need=$w*$h*4*$(if($format -eq 2) {4} else {2})
            $gpuAt=U64 $table ($at+32);$gpuSize=U32 $table ($at+64)
            $tailAt=U64 $table ($at+24);$tailSize=U32 $table ($at+60)
            if($gpuSize -ge $need) {$pixels=Read-Range (Stage ($name+'.gpu_resources')) $gpuAt $need}
            elseif($tailSize -ge $need) {$pixels=Read-Range (Stage ($name+'.stream')) $tailAt $need}
            elseif($gpuSize+$tailSize -ge $need) {$take=[Math]::Min($tailSize,$need);$a=Read-Range (Stage ($name+'.stream')) $tailAt $take;$b=Read-Range (Stage ($name+'.gpu_resources')) $gpuAt ($need-$take);$pixels=[byte[]]($a+$b)}
            elseif($mainSize -ge 340+$need) {$pixels=Read-Range $path ($mainAt+340) $need}
            else {throw 'Incomplete LUT payload'}
            # Resource sidecars expose base-level pixels; normalize the DDS to one mip.
            [Array]::Copy([BitConverter]::GetBytes([uint32]1),0,$header,28,4)
            Save-Lut ([byte[]]($header+$pixels))
        }
    }
    if($files.Count -eq 0) {throw 'ZIP contains no supported 23-column DDS LUTs'}
    Publish ("ok`n"+($files -join "`n"))
} catch {if($_.Exception.Message -eq 'Import canceled') {Publish 'cancel';return};Publish ("error`n"+$_.Exception.Message.Replace("`n",' ').Replace("`r",' '));exit 1}
finally {
    if($zip) {$zip.Dispose()}
    if($staging -and [IO.Directory]::Exists($staging)) {
        # Only this worker's generated flat .bin files exist here; no archive paths are used.
        foreach($file in [IO.Directory]::GetFiles($staging)) {[IO.File]::Delete($file)}
        [IO.Directory]::Delete($staging)
    }
}
