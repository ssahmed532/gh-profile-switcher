#requires -Version 7.2
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$scriptFile = Join-Path (Split-Path $PSScriptRoot) 'ghprofile.ps1'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('ghprofile-prereqs-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($scratch)
$passed = 0
$pwsh = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source

function Assert($Condition, $Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:passed++; Write-Output "PASS: $Message"
}
function Run($Arguments, $PathValue) {
    $pi = [Diagnostics.ProcessStartInfo]::new($pwsh)
    $pi.UseShellExecute = $false
    $pi.RedirectStandardOutput = $true
    $pi.RedirectStandardError = $true
    $pi.WorkingDirectory = $scratch
    foreach ($arg in (@('-NoProfile','-File',$scriptFile) + $Arguments + @('-ConfigPath',(Join-Path $scratch 'missing.json')))) { $pi.ArgumentList.Add($arg) }
    $pi.Environment['PATH'] = $PathValue
    $pi.Environment['GIT_CONFIG_GLOBAL'] = Join-Path $scratch 'global.config'
    $pi.Environment['GH_CONFIG_DIR'] = Join-Path $scratch 'gh-config'
    $p = [Diagnostics.Process]::new(); $p.StartInfo = $pi
    try {
        [void]$p.Start()
        $stdout = $p.StandardOutput.ReadToEndAsync(); $stderr = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit(15000)) { $p.Kill($true); throw 'Prerequisite check timed out.' }
        [pscustomobject]@{ Code=$p.ExitCode; Out=$stdout.GetAwaiter().GetResult().Trim(); Error=$stderr.GetAwaiter().GetResult().Trim() }
    } finally { $p.Dispose() }
}

try {
    foreach ($command in @('setup','status','doctor','switch','init-key')) {
        $r = Run @($command) ''
        Assert ($r.Code -eq 1 -and $r.Error -match 'GitHub CLI \(gh\), Git CLI \(git\)' -and $r.Error -match 'PATH' -and -not $r.Out) "$command fails before reading profiles when both tools are missing"
    }
    $r = Run @('setup','-WhatIf') ''
    Assert ($r.Code -eq 1 -and $r.Error -match 'Missing required command') 'Preview also checks prerequisites'
    foreach ($command in @('status','doctor')) {
        $r = Run @($command,'-Json','-Color','Always') ''
        $data = $r.Out | ConvertFrom-Json
        Assert ($r.Code -eq 1 -and $data.Error -match 'GitHub CLI \(gh\), Git CLI \(git\)' -and -not $r.Error -and $r.Out -notmatch '\x1b') "$command preserves JSON error output"
    }
    foreach ($flag in @('--version','-Version')) {
        $r = Run @($flag) ''
        Assert ($r.Code -eq 0 -and $r.Out -ceq 'v0.3.2' -and -not $r.Error) "$flag remains dependency-free"
    }
    # Discovery-only executables: configuration fails before these can execute.
    $extension = if ($IsWindows) { '.exe' } else { '' }
    foreach ($available in @('git','gh')) {
        $bin = Join-Path $scratch $available
        [void][IO.Directory]::CreateDirectory($bin)
        Copy-Item -LiteralPath $pwsh -Destination (Join-Path $bin "$available$extension")
        $r = Run @('status','-Json') $bin
        $message = ($r.Out | ConvertFrom-Json).Error
        $expected = if ($available -eq 'git') { 'GitHub CLI (gh)' } else { 'Git CLI (git)' }
        Assert ($r.Code -eq 1 -and $message.StartsWith("Missing required command(s): $expected.")) "Only the missing tool is reported when $available is available"
    }
    $both = (Join-Path $scratch 'git') + [IO.Path]::PathSeparator + (Join-Path $scratch 'gh')
    $r = Run @('status','-Json') $both
    Assert ($r.Code -eq 1 -and ($r.Out | ConvertFrom-Json).Error -notmatch 'Missing required command' -and $r.Out -match 'missing.json') 'Both tools present allows configuration loading'
    Assert (-not (Test-Path (Join-Path $scratch 'global.config')) -and -not (Test-Path (Join-Path $scratch 'gh-config'))) 'Prerequisite failures write no Git or gh configuration'
    Write-Output "$passed checks passed."
} catch { [Console]::Error.WriteLine($_.ToString()); exit 1 }
