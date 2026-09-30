#requires -Version 7.2
<#
.SYNOPSIS
Guided, resumable Windows console verification with disposable configuration.
.DESCRIPTION
Run in an interactive PowerShell 7 terminal without transcription or redirection.
Enter passphrases only at OpenSSH prompts. Ctrl+C may stop this driver as well as
the child: rerun the printed -Resume command to validate that interrupted step.
#>
[CmdletBinding()]
param([string]$Resume)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Confirm-Observation([string]$Question) {
    do { $answer = Read-Host "$Question [y/n/u=unsure]" } while ($answer -notin @('y','n','u'))
    return $(if ($answer -eq 'y') { 'Pass' } elseif ($answer -eq 'n') { 'Fail' } else { 'Unknown' })
}

function Get-FileSnapshot([string]$Root) {
    # Hash metadata only. Never read private-key contents into the report.
    $snapshot = @{}
    foreach ($file in Get-ChildItem -LiteralPath $Root -File -Recurse) {
        $relative = [IO.Path]::GetRelativePath($Root, $file.FullName)
        if ($relative -in @('report.json','report.txt')) { continue }
        $snapshot[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
    return $snapshot
}

function Test-SameSnapshot($Before, $After) {
    if ($Before.Count -ne $After.Count) { return $false }
    foreach ($key in $Before.Keys) {
        if (-not $After.ContainsKey($key) -or $Before[$key] -ne $After[$key]) { return $false }
    }
    return $true
}

function Save-Report {
    $state | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM
    $summary = @(
        'GH profile switcher manual Windows verification'
        "Status: $($state.Status) | Next stage: $($state.Stage) | Pending: $($state.Pending)"
        "Terminal: $($state.Terminal)"
        "PowerShell: $($state.PowerShell) | Tool: $($state.ToolVersion)"
        "Git: $($state.Git) | gh: $($state.Gh)"
        "OpenSSH: $($state.OpenSSH) | Executable: $($state.SshKeygen)"
        if ($state.ContainsKey('CancelFiles')) { "Partial cancelled key files: private=$($state.CancelFiles.Private), public=$($state.CancelFiles.Public)" }
        if ($state.ContainsKey('NonInteractiveSeconds')) { "Noninteractive elapsed seconds: $($state.NonInteractiveSeconds)" }
        'Checks:'
        foreach ($check in $state.Checks) { "[$($check.Result)] $($check.Name)" }
        'Only Pass results with Status Complete establish a successful manual run.'
        'No passphrases, native output or private-key contents are recorded.'
    )
    $summary | Set-Content -LiteralPath (Join-Path $fixture 'report.txt') -Encoding utf8NoBOM
}

function Add-Check([string]$Name, [string]$Result) {
    $state.Checks += @{ Name=$Name; Result=$Result }
    Save-Report
    Write-Host "[$Result] $Name"
}

function Require-Check([string]$Name, [bool]$Condition) {
    Add-Check $Name $(if ($Condition) { 'Pass' } else { 'Fail' })
    if (-not $Condition) { throw "Verification failed: $Name. See report.txt; retain fixtures for inspection." }
}

function Observe([string]$Name, [string]$Question) {
    Add-Check $Name (Confirm-Observation $Question)
}

function Invoke-InteractiveStep([string[]]$Arguments) {
    # Persist before starting: terminal Ctrl+C can stop this whole pipeline.
    $state.Pending = $true
    Save-Report
    # Inherit the actual console handles; do not capture native prompt/output.
    $pi = [Diagnostics.ProcessStartInfo]::new($pwsh)
    $pi.UseShellExecute = $false
    foreach ($arg in (@('-NoProfile','-File',$tool) + $Arguments + @('-ConfigPath',$definition))) { $pi.ArgumentList.Add($arg) }
    $p = [Diagnostics.Process]::new(); $p.StartInfo = $pi
    $started = $false
    try {
        [void]$p.Start(); $started = $true
        while (-not $p.WaitForExit(100)) { Start-Sleep -Milliseconds 20 }
        return $p.ExitCode
    } finally {
        # Give the child its own Ctrl+C cleanup opportunity before fallback termination.
        try {
            if ($started -and -not $p.HasExited -and -not $p.WaitForExit(2000)) {
                [IO.File]::WriteAllText((Join-Path $fixture 'forced-termination.txt'), 'Driver had to terminate the child. Cancellation did not finish within the cleanup grace period.')
                $p.Kill($true); $p.WaitForExit()
            }
        }
        finally { $p.Dispose() }
    }
}

function Invoke-NonInteractiveStep {
    $pi = [Diagnostics.ProcessStartInfo]::new($pwsh)
    $pi.UseShellExecute = $false
    $pi.RedirectStandardInput = $true
    $pi.RedirectStandardOutput = $true
    $pi.RedirectStandardError = $true
    foreach ($arg in @('-NoProfile','-File',$tool,'setup','-ConfigPath',$definition,'-NonInteractive')) { $pi.ArgumentList.Add($arg) }
    $p = [Diagnostics.Process]::new(); $p.StartInfo = $pi
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $started = $false
    try {
        [void]$p.Start(); $started = $true; $p.StandardInput.Close()
        $stdout = $p.StandardOutput.ReadToEndAsync(); $stderr = $p.StandardError.ReadToEndAsync()
        $finished = $p.WaitForExit(15000)
        if (-not $finished) { $p.Kill($true); $p.WaitForExit() }
        $watch.Stop()
        # Inspect transient output but never store it (or a passphrase) in a report.
        $output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        return @{ Finished=$finished; Code=$p.ExitCode; Seconds=[Math]::Round($watch.Elapsed.TotalSeconds,2);
            Prompt=($output -match '(?im)enter[^\r\n]*passphrase[^\r\n]*:') }
    } finally {
        try { if ($started -and -not $p.HasExited) { $p.Kill($true); $p.WaitForExit() } } finally { $p.Dispose() }
    }
}

if (-not $IsWindows) { throw 'This checklist verifies Windows console behavior.' }
if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { throw 'Run directly in an interactive terminal, without piping or redirection.' }
$tool = (Resolve-Path (Join-Path (Split-Path $PSScriptRoot) 'ghprofile.ps1')).Path
$pwsh = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
foreach ($name in @('git','gh','ssh-keygen')) { [void](Get-Command $name -CommandType Application -ErrorAction Stop) }
$sshKeygen = (Get-Command ssh-keygen -CommandType Application | Select-Object -First 1).Source
$toolHash = (Get-FileHash -LiteralPath $tool).Hash

if ($Resume) {
    $fixture = [IO.Path]::GetFullPath($Resume)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
    if ([IO.Path]::GetDirectoryName($fixture) -ne $tempRoot -or
        [IO.Path]::GetFileName($fixture) -notmatch '^ghprofile-manual-[a-f0-9]{32}$') {
        throw 'Resume must name a ghprofile-manual fixture directly inside your temporary directory.'
    }
    if ((Get-Item -LiteralPath $fixture).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Cannot resume a linked fixture directory.' }
    $reportPath = Join-Path $fixture 'report.json'
    $state = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json -AsHashtable
    if ($state.ToolHash -ne $toolHash -or $state.SshKeygen -ne $sshKeygen) { throw 'Tool or OpenSSH selection changed. Start a new run.' }
    if ($state.Status -in @('Complete','Failed','Needs review')) { throw 'This run has ended. Read report.txt or start a fresh run.' }
} else {
    Write-Host 'Use a terminal with transcription disabled. Never type a passphrase into this driver.'
    $terminal = Read-Host 'Terminal application and version (for example Windows Terminal 1.x)'
    if ([string]::IsNullOrWhiteSpace($terminal)) { throw 'Record the terminal application/version before testing.' }
    $fixture = Join-Path ([IO.Path]::GetTempPath()) ('ghprofile-manual-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($fixture)
    $reportPath = Join-Path $fixture 'report.json'
    $state = @{ Status='In progress'; Stage=0; Pending=$false; Checks=@(); Terminal=$terminal;
        PowerShell=$PSVersionTable.PSVersion.ToString(); ToolVersion=(& $pwsh -NoProfile -File $tool --version);
        ToolHash=$toolHash; Git=(& git --version); Gh=(@(& gh --version)[0]);
        SshKeygen=$sshKeygen; OpenSSH=(Get-Item -LiteralPath $sshKeygen).VersionInfo.FileVersion; Baseline=@{} }
}

$definition = Join-Path $fixture 'profiles.json'
$private = Join-Path $fixture 'sample'
$globalConfig = Join-Path $fixture 'global.config'
$savedEnvironment = @{}
foreach ($entry in Get-ChildItem Env:) {
    if ($entry.Name -like 'GIT_*' -or $entry.Name -like 'GH_*' -or $entry.Name -like 'GITHUB_*') { $savedEnvironment[$entry.Name] = $entry.Value }
}
$originalLocation = Get-Location
$resumeCommand = "pwsh -NoProfile -File `"$PSCommandPath`" -Resume `"$fixture`""
Write-Host "Reports: $fixture"
Write-Host "If Ctrl+C stops the driver, run this exact command in the same terminal:"
Write-Host $resumeCommand

try {
    Get-ChildItem Env: | Where-Object { $_.Name -like 'GIT_*' -or $_.Name -like 'GH_*' -or $_.Name -like 'GITHUB_*' } | Remove-Item
    $env:GIT_CONFIG_GLOBAL = $globalConfig
    $env:GIT_CONFIG_NOSYSTEM = '1'
    $env:GH_CONFIG_DIR = Join-Path $fixture 'gh'
    Set-Location -LiteralPath $fixture
    # Write definitions only on a fresh run so resume does not change the snapshot.
    $profiles = @{ sample=@{name='Terminal Example';email='terminal@example.invalid';ghUser='terminal-example';root=(Join-Path $fixture 'repo');signingMode='file';signingKey="$private.pub"} }
    if ($state.Stage -le 1) { $profiles.cancel=@{name='Cancel Example';email='cancel@example.invalid';ghUser='cancel-example';root=(Join-Path $fixture 'cancel-repo');signingMode='file';signingKey=(Join-Path $fixture 'cancel.pub')} }
    if (-not $Resume) { @{schemaVersion=1;policy='strict';profiles=$profiles} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $definition }
    Save-Report

    while ($state.Stage -lt 5) {
        switch ($state.Stage) {
            0 {
                if ($state.Pending) { throw 'Key creation was interrupted. Start a fresh run; existing key files are preserved.' }
                Write-Host "`n1/5: Create the sample key. Enter and confirm a NONEMPTY disposable passphrase at OpenSSH prompts only."
                $code = Invoke-InteractiveStep @('init-key','sample')
                Require-Check 'Key creation exit 0' ($code -eq 0)
                Require-Check 'Private and public key files exist' ((Test-Path -LiteralPath $private) -and (Test-Path -LiteralPath "$private.pub"))
                Require-Check 'Sample key lock released' (-not (Test-Path -LiteralPath "$private.ghprofile-lock"))
                Observe 'Both creation prompts visible before input' 'Were both passphrase prompts visible BEFORE you typed?'
                Observe 'Creation passphrase input hidden' 'Were both passphrase entries hidden (no echoed characters)?'
                $state.Baseline = Get-FileSnapshot $fixture
            }
            1 {
                if (-not $state.Pending) {
                    Write-Host "`n2/5: Press Ctrl+C ONCE at the FIRST passphrase prompt. Do not type a passphrase."
                    [void](Invoke-InteractiveStep @('init-key','cancel'))
                } else { Write-Host 'Resuming verification after key-creation cancellation.' }
                Observe 'Key creation cancellation returned control' 'Did one Ctrl+C at the visible prompt return control promptly?'
                Require-Check 'Cancellation needed no forced termination' (-not (Test-Path -LiteralPath (Join-Path $fixture 'forced-termination.txt')))
                Require-Check 'Cancelled key lock released' (-not (Test-Path -LiteralPath (Join-Path $fixture 'cancel.ghprofile-lock')))
                Require-Check 'Cancellation did not create global config' (-not (Test-Path -LiteralPath $globalConfig))
                Require-Check 'Existing sample key pair preserved' (((Get-FileHash $private).Hash -eq $state.Baseline['sample']) -and ((Get-FileHash "$private.pub").Hash -eq $state.Baseline['sample.pub']))
                $state.CancelFiles = @{ Private=(Test-Path -LiteralPath (Join-Path $fixture 'cancel')); Public=(Test-Path -LiteralPath (Join-Path $fixture 'cancel.pub')) }
                Write-Host "Partial cancellation files (retained): private=$($state.CancelFiles.Private), public=$($state.CancelFiles.Public)"
                $data = Get-Content -LiteralPath $definition -Raw | ConvertFrom-Json -AsHashtable
                [void]$data.profiles.Remove('cancel')
                $data | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $definition
            }
            2 {
                Write-Host "`n3/5: Enter the sample passphrase at the encrypted-key validation prompt."
                $code = Invoke-InteractiveStep @('setup')
                Require-Check 'Setup exit 0' ($code -eq 0)
                Observe 'Validation prompt visible before input' 'Was the validation passphrase prompt visible BEFORE you typed?'
                Observe 'Validation passphrase input hidden' 'Was your passphrase input hidden?'
                Require-Check 'Isolated global config created' (Test-Path -LiteralPath $globalConfig)
                Require-Check 'Setup lock released' (-not (Test-Path -LiteralPath "$globalConfig.lock"))
                $state.Baseline = Get-FileSnapshot $fixture
            }
            3 {
                if (-not $state.Pending) {
                    Write-Host "`n4/5: Press Ctrl+C ONCE at the validation prompt; do not enter the passphrase."
                    [void](Invoke-InteractiveStep @('setup'))
                } else { Write-Host 'Resuming verification after validation cancellation.' }
                Observe 'Validation cancellation returned control' 'Did one Ctrl+C at the visible validation prompt return control promptly?'
                Require-Check 'All fixture files unchanged after cancellation' (Test-SameSnapshot $state.Baseline (Get-FileSnapshot $fixture))
                Require-Check 'Cancellation left no global lock' (-not (Test-Path -LiteralPath "$globalConfig.lock"))
            }
            4 {
                Write-Host "`n5/5: Checking noninteractive encrypted-key failure (15-second deadline). Do not enter anything."
                $result = Invoke-NonInteractiveStep
                $state.NonInteractiveSeconds = $result.Seconds
                Require-Check 'Noninteractive completion within 15 seconds' $result.Finished
                Require-Check 'Noninteractive encrypted-key failure exit 1' ($result.Code -eq 1)
                Require-Check 'No passphrase prompt in captured output' (-not $result.Prompt)
                Observe 'No direct-console noninteractive prompt' 'Did this step finish WITHOUT showing any passphrase prompt?'
                Require-Check 'All fixture files unchanged after noninteractive failure' (Test-SameSnapshot $state.Baseline (Get-FileSnapshot $fixture))
                Require-Check 'Noninteractive failure left no global lock' (-not (Test-Path -LiteralPath "$globalConfig.lock"))
            }
        }
        $state.Stage++
        $state.Pending = $false
        Save-Report
    }
    $state.Status = if (@($state.Checks | Where-Object Result -ne 'Pass').Count) { 'Needs review' } else { 'Complete' }
    Save-Report
    Write-Host "`n$($state.Status). Share report.txt only: $(Join-Path $fixture 'report.txt')"
    Write-Host 'Fixtures and disposable keys are retained. No real account/configuration was changed.'
} catch {
    $state.Status = if ($_.Exception -is [Management.Automation.PipelineStoppedException]) { 'In progress' } else { 'Failed' }
    Save-Report
    throw
} finally {
    Set-Location -LiteralPath $originalLocation.Path
    Get-ChildItem Env: | Where-Object { $_.Name -like 'GIT_*' -or $_.Name -like 'GH_*' -or $_.Name -like 'GITHUB_*' } | Remove-Item
    foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name,$savedEnvironment[$name],'Process') }
}
if ($state.Status -ne 'Complete') { exit 1 }
