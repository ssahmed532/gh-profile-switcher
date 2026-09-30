#requires -Version 7.2
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$source = Join-Path $PSScriptRoot 'Manual-Windows.ps1'
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($source,[ref]$null,[ref]$errors)
$passed = 0
function Assert([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:passed++; Write-Output "PASS: $Message"
}
Assert ($errors.Count -eq 0) 'Manual runner parses'
foreach ($fn in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)) {
    . ([scriptblock]::Create($fn.Extent.Text))
}
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('ghprofile-driver-test-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$reportPath = Join-Path $fixture 'report.json'
$sample = Join-Path $fixture 'sample'
[IO.File]::WriteAllText($sample,'synthetic-test-data-never-a-real-key')
$before = Get-FileSnapshot $fixture
Assert (Test-SameSnapshot $before (Get-FileSnapshot $fixture)) 'Identical fixture snapshots pass'
[IO.File]::WriteAllText($sample,'modified')
Assert (-not (Test-SameSnapshot $before (Get-FileSnapshot $fixture))) 'Modified key detected'
[IO.File]::WriteAllText($sample,'synthetic-test-data-never-a-real-key')
$extra = Join-Path $fixture 'global.config.lock'
[IO.File]::WriteAllText($extra,'')
Assert (-not (Test-SameSnapshot $before (Get-FileSnapshot $fixture))) 'Extra lock or generated file detected'
[IO.File]::Delete($extra)
[IO.File]::Delete($sample)
Assert (-not (Test-SameSnapshot $before (Get-FileSnapshot $fixture))) 'Deleted key detected'
[IO.File]::WriteAllText($sample,'synthetic-test-data-never-a-real-key')
$state = @{ Status='In progress'; Stage=3; Pending=$true; Checks=@(); Terminal='Synthetic'; PowerShell='test'; ToolVersion='test'; Git='test'; Gh='test'; OpenSSH='test'; SshKeygen='synthetic'; Baseline=$before }
Save-Report
Assert (Test-SameSnapshot $before (Get-FileSnapshot $fixture)) 'Report updates excluded from fixture snapshots'
$restored = Get-Content $reportPath -Raw | ConvertFrom-Json -AsHashtable
Assert ($restored.Stage -eq 3 -and $restored.Pending -and (Test-SameSnapshot $restored.Baseline $before)) 'Pending cancellation and snapshot survive JSON round trip'
Assert ((Get-Content $reportPath -Raw) -notmatch 'synthetic-test-data-never-a-real-key') 'Report never stores file contents'
$pwsh = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
$definition = Join-Path $fixture 'unused.json'
$tool = Join-Path $fixture 'fake-child.ps1'
[IO.File]::WriteAllText($tool, 'exit 1')
$r = Invoke-NonInteractiveStep
Assert ($r.Finished -and $r.Code -eq 1 -and -not $r.Prompt) 'Noninteractive failure is collected without a prompt'
[IO.File]::WriteAllText($tool, '[Console]::Error.Write("Enter passphrase: "); exit 1')
$r = Invoke-NonInteractiveStep
Assert ($r.Prompt) 'Unexpected stream-written passphrase prompt detected'
[IO.File]::WriteAllText($tool, 'exit 7')
$code = Invoke-InteractiveStep @()
Assert ($code -eq 7 -and $state.Pending) 'Interactive child exit and pre-launch checkpoint preserved'
$pidFile = Join-Path $fixture 'slow-child.pid'
$escapedPidFile = $pidFile.Replace("'", "''")
[IO.File]::WriteAllText($tool, "[IO.File]::WriteAllText('$escapedPidFile', [string]`$PID); Start-Sleep -Seconds 60")
$r = Invoke-NonInteractiveStep
Assert (-not $r.Finished) 'Noninteractive deadline rejects a hung child'
$childId = [int](Get-Content -LiteralPath $pidFile)
Assert (-not (Get-Process -Id $childId -ErrorAction SilentlyContinue)) 'Deadline terminates the owned child'
Write-Output "$passed manual-runner helper checks passed. Actual console verification remains manual."
