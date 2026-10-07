function Resolve-PythonRuntime([string]$Configured) {
    if(-not $Configured) {$Configured=$env:EPIC_LUT_PYTHON}
    if(-not $Configured) {
        $selection=Join-Path $env:LOCALAPPDATA 'Epic LUT\settings\python-runtime.txt'
        if(Test-Path -LiteralPath $selection) {$Configured=(Get-Content -LiteralPath $selection -Raw).Trim()}
    }
    if($Configured) {
        $resolved=(Get-Command $Configured -ErrorAction Stop).Source
        Assert-UnvirtualizedPath $resolved
        return $resolved
    }
    foreach($command in @(Get-Command python.exe -All -ErrorAction SilentlyContinue)) {
        try {Assert-UnvirtualizedPath $command.Source;return $command.Source} catch {}
    }
    foreach($registryRoot in @('HKCU:\Software\Python\PythonCore','HKLM:\Software\Python\PythonCore','HKLM:\Software\WOW6432Node\Python\PythonCore')) {
        foreach($version in @(Get-ChildItem -LiteralPath $registryRoot -ErrorAction SilentlyContinue | Sort-Object PSChildName -Descending)) {
            $install=Get-Item -LiteralPath ($version.PSPath+'\InstallPath') -ErrorAction SilentlyContinue
            if($install) {
                $candidate=$install.GetValue('ExecutablePath')
                if(-not $candidate) {$candidate=Join-Path $install.GetValue('') 'python.exe'}
                if(Test-Path -LiteralPath $candidate) {try {Assert-UnvirtualizedPath $candidate;return $candidate} catch {}}
            }
        }
    }
    throw 'Python not found. Install a non-Store Python runtime or specify -Python / EPIC_LUT_PYTHON.'
}
