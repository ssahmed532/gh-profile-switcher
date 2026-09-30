#requires -Version 7.2
param([string]$Source = (Join-Path (Split-Path $PSScriptRoot) 'ghprofile.ps1'))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ast = [Management.Automation.Language.Parser]::ParseFile($source,[ref]$null,[ref]$null)
$functions = ($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false) | ForEach-Object { $_.Extent.Text }) -join "`n"
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('ghprofile-native-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($scratch)
$checks = 0
function Assert([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:checks++; Write-Output "PASS: $Message"
}
$child = Join-Path $scratch 'child.ps1'
@'
param($Release, $PidFile, $Mode)
[IO.File]::WriteAllText($PidFile, [string]$PID)
if ($Mode -eq 'capture') { [Console]::Out.Write('ssh-ed25519 AAAA') }
else { [Console]::Out.Write('stdout prompt: ') }
[Console]::Error.Write('stderr prompt: ')
while (-not [IO.File]::Exists($Release)) { Start-Sleep -Milliseconds 20 }
if ($Mode -eq 'failure') { [Console]::Error.Write("error`e[2J ghp_fixturesecret"); exit 7 }
'@ | Set-Content -LiteralPath $child

# A real child waits for a filesystem handshake, so observing the prompt
# before releasing it proves visibility during execution, not after exit.
foreach ($mode in @('display','capture','failure')) {
    $release = Join-Path $scratch "$mode.release"
    $pidFile = Join-Path $scratch "$mode.pid"
    $resultFile = Join-Path $scratch "$mode.json"
    $driver = Join-Path $scratch "$mode.ps1"
    $body = @'
param($Child, $Release, $PidFile, $ResultFile, $Mode)
$ErrorActionPreference = 'Stop'
'@ + "`n" + $functions + @'

try {
    $result = Invoke-Native pwsh @('-NoProfile','-File',$Child,$Release,$PidFile,$Mode) -Interactive -CaptureOutput:($Mode -eq 'capture')
    $result | ConvertTo-Json | Set-Content -LiteralPath $ResultFile
} catch { [IO.File]::WriteAllText($ResultFile, $_.Exception.Message); exit 1 }
'@
    [IO.File]::WriteAllText($driver,$body)
    $pi = [Diagnostics.ProcessStartInfo]::new((Get-Command pwsh).Source)
    $pi.UseShellExecute=$false; $pi.RedirectStandardOutput=$true; $pi.RedirectStandardError=$true
    foreach ($arg in @('-NoProfile','-File',$driver,$child,$release,$pidFile,$resultFile,$mode)) { $pi.ArgumentList.Add($arg) }
    $p=[Diagnostics.Process]::new(); $p.StartInfo=$pi
    try {
        [void]$p.Start()
        $buffer=[char[]]::new(15)
        $prompt=$p.StandardError.ReadAsync($buffer,0,15)
        Assert ($prompt.Wait(10000) -and $prompt.Result -gt 0 -and -not $p.HasExited) "$mode stderr prompt visible before child completion"
        if ($mode -ne 'capture') {
            $outBuffer=[char[]]::new(15); $outPrompt=$p.StandardOutput.ReadAsync($outBuffer,0,15)
            Assert ($outPrompt.Wait(10000) -and $outPrompt.Result -gt 0 -and -not $p.HasExited) "$mode stdout prompt visible before child completion"
        }
        [IO.File]::WriteAllText($release,'go')
        $out=$p.StandardOutput.ReadToEndAsync(); $err=$p.StandardError.ReadToEndAsync()
        Assert ($p.WaitForExit(10000)) "$mode child returns control"
        if ($mode -eq 'failure') {
            $failure=[IO.File]::ReadAllText($resultFile)
            Assert ($p.ExitCode -eq 1 -and $failure -match 'exit 7' -and $failure -notmatch '\x1b|ghp_fixturesecret') 'Native failure propagates with safe redacted detail'
            Assert ($err.Result -notmatch '\x1b|ghp_fixturesecret') 'Live native error output is sanitized and redacted'
        } else {
            $result=Get-Content -LiteralPath $resultFile -Raw | ConvertFrom-Json
            Assert ($p.ExitCode -eq 0) "$mode native invocation succeeds"
            if ($mode -eq 'capture') { Assert ($result.Out -ceq 'ssh-ed25519 AAAA' -and $out.Result -eq '') 'Public-key stdout stays separate from displayed prompts' }
            else { Assert ($result.Out -eq '') 'Displayed output does not leak into returned data' }
        }
    } finally { if (-not $p.HasExited) { $p.Kill($true); $p.WaitForExit() }; $p.Dispose() }
}

# Stop the PowerShell pipeline, rather than killing its host: finally blocks
# must terminate the native child and release New-ProfileKey's owned lock.
$cancelPid = Join-Path $scratch 'cancel.pid'
$cancelRelease = Join-Path $scratch 'cancel.release'
$key = Join-Path $scratch 'cancel-key'
$shell=[PowerShell]::Create()
$cancelBody = @'
[CmdletBinding(SupportsShouldProcess)]
param($Child, $Release, $PidFile, $Key)
$ErrorActionPreference='Stop'
$NonInteractive=$false
'@ + "`n" + $functions.Replace('function Invoke-Native {','function Invoke-RealNative {') + @'

function Invoke-Native {
    param($Exe,$Arguments,[switch]$Interactive)
    Invoke-RealNative pwsh @('-NoProfile','-File',$Child,$Release,$PidFile,'capture') -Interactive -CaptureOutput
}
New-ProfileKey ([pscustomobject]@{Mode='file';Key="$Key.pub";Email='test@example.invalid'})
'@
try {
    [void]$shell.AddScript($cancelBody).AddArgument($child).AddArgument($cancelRelease).AddArgument($cancelPid).AddArgument($key)
    $running=$shell.BeginInvoke()
    $deadline=[DateTime]::UtcNow.AddSeconds(10)
    while (-not [IO.File]::Exists($cancelPid) -and [DateTime]::UtcNow -lt $deadline -and -not $running.IsCompleted) { Start-Sleep -Milliseconds 20 }
    if ($shell.Streams.Error.Count) { throw ($shell.Streams.Error | Out-String) }
    if ($running.IsCompleted) { [void]$shell.EndInvoke($running); throw 'Cancellation fixture completed before its handshake.' }
    Assert ([IO.File]::Exists($cancelPid) -and [IO.File]::Exists("$key.ghprofile-lock")) 'Cancellation fixture reaches native wait while owning key lock'
    $childId=[int][IO.File]::ReadAllText($cancelPid)
    $shell.Stop()
    Assert (-not [IO.File]::Exists("$key.ghprofile-lock")) 'Pipeline cancellation releases owned key lock'
    Assert ($null -eq (Get-Process -Id $childId -ErrorAction SilentlyContinue)) 'Pipeline cancellation terminates native child'
    Assert (-not [IO.File]::Exists($key) -and -not [IO.File]::Exists("$key.pub")) 'Cancellation does not invent a successful key pair'
} finally { $shell.Dispose() }

# Exercise every split point without exposing the injected controls to a terminal.
foreach ($fn in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)) { . ([scriptblock]::Create($fn.Extent.Text)) }
$rejected=$false
try { [void](Invoke-Native pwsh @("bad`e[2J") -Interactive) } catch { $rejected=$_.Exception.Message -match 'cannot contain terminal control' }
Assert $rejected 'Interactive arguments cannot inject controls through direct native console prompts'
$originalWriter=[Console]::Out
$oldToken=$env:GH_TOKEN
try {
    $env:GH_TOKEN='secret with spaces'
    $attack="prompt: https://user:password@example.invalid ghp_fixturesecret secret with spaces `e]8;;bad`a 日本語 👩‍💻`r`nnext literal \u000A"
    for ($split=1; $split -lt $attack.Length; $split++) {
        $writer=[IO.StringWriter]::new(); [Console]::SetOut($writer)
        $stream=@{Pending=$attack.Substring(0,$split);Error=$false}
        Write-NativePendingText $stream
        $stream.Pending += $attack.Substring($split)
        Write-NativePendingText $stream
        Write-NativePendingText $stream -Final
        $actual=$writer.ToString()
        [Console]::SetOut($originalWriter); $writer.Dispose()
        if ($actual -cne (Protect-Text $attack -PreserveNewlines)) { throw "Streaming redaction differs at split $split" }
    }
    Assert $true 'All stream split points preserve secret redaction, control escaping and Unicode'
} finally { [Console]::SetOut($originalWriter); $env:GH_TOKEN=$oldToken }
Write-Output "$checks native execution checks passed. Fixtures: $scratch"
