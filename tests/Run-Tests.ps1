#requires -Version 7.2
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$scriptFile = Join-Path (Split-Path $PSScriptRoot) 'ghprofile.ps1'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('ghprofile-tests-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($scratch)
$testGlobal = Join-Path $scratch 'global.config'
$testConfig = Join-Path $scratch 'profiles.json'
$testGh = Join-Path $scratch 'gh'
[void][IO.Directory]::CreateDirectory($testGh)
$passed = 0

function Run([string]$Exe, [string[]]$Arguments, [string]$Directory = $scratch, [hashtable]$Environment = @{}) {
    $pi = [Diagnostics.ProcessStartInfo]::new((Get-Command $Exe -CommandType Application | Select-Object -First 1).Source)
    $pi.UseShellExecute = $false
    $pi.RedirectStandardOutput = $true
    $pi.RedirectStandardError = $true
    $pi.RedirectStandardInput = $true
    $pi.WorkingDirectory = $Directory
    foreach ($arg in $Arguments) { $pi.ArgumentList.Add($arg) }
    foreach ($key in @($pi.Environment.Keys)) {
        if ($key -like 'GIT_*' -or $key -in @('GH_TOKEN','GITHUB_TOKEN','GH_ENTERPRISE_TOKEN','GITHUB_ENTERPRISE_TOKEN','GH_HOST','GH_REPO','EMAIL')) { [void]$pi.Environment.Remove($key) }
    }
    $pi.Environment['GIT_CONFIG_GLOBAL'] = $testGlobal
    $pi.Environment['GIT_CONFIG_NOSYSTEM'] = '1'
    $pi.Environment['GH_CONFIG_DIR'] = $testGh
    $pi.Environment['GH_PROMPT_DISABLED'] = '1'
    $pi.Environment['GIT_TERMINAL_PROMPT'] = '0'
    foreach ($key in $Environment.Keys) { $pi.Environment[$key] = $Environment[$key] }
    $p = [Diagnostics.Process]::new()
    $p.StartInfo = $pi
    try {
        [void]$p.Start(); $p.StandardInput.Close()
        $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit(45000)) { $p.Kill($true); throw "Timeout: $Exe" }
        return [pscustomobject]@{ Code=$p.ExitCode; Out=$o.GetAwaiter().GetResult().Trim(); Error=$e.GetAwaiter().GetResult().Trim() }
    } finally { $p.Dispose() }
}
function Script([string[]]$Arguments, [string]$Directory=$scratch, [hashtable]$Environment=@{}) {
    Run pwsh (@('-NoProfile','-File',$scriptFile) + $Arguments) $Directory $Environment
}
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw "FAIL: $Message" }; $script:passed++; Write-Output "PASS: $Message" }
function Good($Result, [string]$Message) { Assert ($Result.Code -eq 0) "$Message [$($Result.Code)] $($Result.Error)" }
function SaveConfig { $script:config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $testConfig -Encoding utf8NoBOM }
function Setup { Script @('setup','-ConfigPath',$testConfig,'-NonInteractive') }
function GitValue([string]$Directory,[string]$Key) { (Run git @('config','--get',$Key) $Directory).Out }

try {
    $r = Script @('--version','-ConfigPath',(Join-Path $scratch 'missing.json'))
    Assert ($r.Code -eq 0 -and $r.Out -ceq 'v0.1.1' -and -not $r.Error) '--version prints only v0.1.1 without config'
    $r = Script @('-Version')
    Assert ($r.Code -eq 0 -and $r.Out -ceq 'v0.1.1') 'PowerShell -Version alias'
    $r = Script @('--version') $scratch @{ PATH='' }
    Assert ($r.Code -eq 0 -and $r.Out -ceq 'v0.1.1' -and -not $r.Error) 'Version works without Git, gh or OpenSSH on PATH'
    Assert (([System.Management.Automation.SemanticVersion]::Parse($r.Out.Substring(1))).ToString() -ceq '0.1.1') 'Release version is valid SemVer'
    $errors = $null; $tokens = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($scriptFile,[ref]$tokens,[ref]$errors)
    Assert ($errors.Count -eq 0) 'Script parses'

    $work = Join-Path $scratch 'work'
    $personal = Join-Path $scratch 'personal # space'
    $outside = Join-Path $scratch 'outside'
    foreach ($dir in @($work,$personal,$outside)) { Good (Run git @('init','--quiet',$dir)) "Initialize fixture $([IO.Path]::GetFileName($dir))" }
    $script:config = [ordered]@{ schemaVersion=1; policy='default'; default='work'; profiles=[ordered]@{
        work=[ordered]@{name='Work Example';email='work@example.invalid';ghUser='work-user';signingMode='none';root=$work}
        personal=[ordered]@{name='Personal "Quoted" # Name';email='personal@example.invalid';ghUser='personal-user';signingMode='none';root=$personal}
    } }
    SaveConfig
    $r = Script @('setup','-ConfigPath',$testConfig,'-WhatIf','-NonInteractive')
    Good $r 'WhatIf succeeds'
    Assert (-not [IO.File]::Exists($testGlobal) -and -not [IO.Directory]::Exists("$testGlobal.ghprofile")) 'WhatIf writes nothing'
    Good (Setup) 'Fresh-machine setup without an existing global config'
    [IO.File]::WriteAllText($testGlobal,'')
    Good (Setup) 'Setup accepts an existing empty global config'
    Assert ((GitValue $work user.email) -eq 'work@example.invalid') 'Work folder identity'
    Assert ((GitValue $personal user.email) -eq 'personal@example.invalid') 'Personal folder identity'
    Assert ((GitValue $personal user.name) -ceq 'Personal "Quoted" # Name') 'Quotes and comment characters round-trip'
    Assert ((GitValue $outside user.email) -eq 'work@example.invalid') 'Default fallback identity'
    Good (Setup) 'Repeated setup'
    $includes = Run git @('config','--file',$testGlobal,'--get-all','include.path')
    Assert (($includes.Out -split '\r?\n').Count -eq 1) 'Repeated setup retains exactly one managed include'

    $legacy = Join-Path $scratch '.gitconfig-legacy'
    [IO.File]::WriteAllText($legacy,"# Generated by ghprofile.ps1 from profiles.json - edit that file and re-run setup.`n[user]`n email = stale@example.invalid`n")
    Good (Run git @('config','--file',$testGlobal,"includeIf.gitdir/i:$($personal.Replace('\','/'))/.path",$legacy)) 'Install legacy generated include'
    $unrelated = Join-Path $scratch 'unrelated.config'
    [IO.File]::WriteAllText($unrelated,"[alias]`n example = status`n")
    Good (Run git @('config','--file',$testGlobal,'--add','include.path',$unrelated)) 'Install unrelated include'
    Good (Setup) 'Migrate legacy configuration'
    $raw=[IO.File]::ReadAllText($testGlobal)
    Assert ($raw -notmatch 'gitconfig-legacy' -and (GitValue $personal alias.example) -eq 'status') 'Migration removes only owned includes and preserves unrelated settings'

    # A global default AFTER an existing include must not defeat the new dispatcher.
    Add-Content -LiteralPath $testGlobal -Value "`n[user]`n email = wrong@example.invalid`n[credential `"https://github.com`"]`n username = wrong-user"
    Good (Setup) 'Setup repairs late inherited defaults'
    Assert ((GitValue $personal user.email) -eq 'personal@example.invalid') 'Managed identity wins over late global values'
    $r = Run git @('config','--get-urlmatch','credential.username','https://github.com') $personal
    Assert ($r.Out -eq 'personal-user') 'Managed credential username wins over late global values'

    $moved = Join-Path $scratch 'moved'
    Good (Run git @('init','--quiet',$moved)) 'Initialize moved root fixture'
    $config.profiles.personal.root = $moved; SaveConfig
    Good (Setup) 'Root change reconciles rules'
    Assert ((GitValue $personal user.email) -eq 'work@example.invalid' -and (GitValue $moved user.email) -eq 'personal@example.invalid') 'Old root stops matching; new root matches'
    $config.default='personal'; SaveConfig
    Good (Setup) 'Change default profile'
    Assert ((GitValue $outside user.email) -eq 'personal@example.invalid') 'New default takes effect'
    $config.profiles.Remove('work'); SaveConfig
    Good (Setup) 'Remove profile'
    Assert ((GitValue $work user.email) -eq 'personal@example.invalid') 'Removed profile no longer selects old identity'

    $config.policy='strict'; SaveConfig
    Good (Setup) 'Enable strict policy'
    $r = Run git @('var','GIT_AUTHOR_IDENT') $outside
    Assert ($r.Code -ne 0) 'Strict policy prevents inferred identity outside roots'
    Assert ((GitValue $moved user.email) -eq 'personal@example.invalid') 'Strict policy retains explicit root identity'
    $before = [IO.File]::ReadAllText($testGlobal)
    $config.profiles.personal.roots=@($moved,(Join-Path $moved 'nested')); $config.profiles.personal.Remove('root'); SaveConfig
    $r = Setup
    Assert ($r.Code -eq 1 -and $r.Error -match 'Overlapping') 'Overlapping roots are rejected'
    Assert ([IO.File]::ReadAllText($testGlobal) -ceq $before) 'Validation failure leaves active config unchanged'
    $config.profiles.personal.roots=@($moved); SaveConfig
    [IO.File]::WriteAllText("$testGlobal.lock",'occupied')
    $r = Setup
    Assert ($r.Code -eq 1 -and [IO.File]::ReadAllText($testGlobal) -ceq $before) 'Concurrent Git config lock prevents mutation'
    Assert ([IO.File]::ReadAllText("$testGlobal.lock") -ceq 'occupied') 'Existing lock is never removed'
    [IO.File]::Delete("$testGlobal.lock")

    # Signing integration uses disposable, unencrypted test keys only.
    $key = Join-Path $scratch 'signing key'
    Good (Run ssh-keygen @('-q','-t','ed25519','-N','','-f',$key)) 'Create disposable signing key'
    $config.profiles.personal.signingMode='file'; $config.profiles.personal.signingKey="$key.pub"; SaveConfig
    Good (Setup) 'Validate and configure SSH signing'
    Assert ((GitValue $moved gpg.format) -eq 'ssh' -and (GitValue $moved commit.gpgsign) -eq 'true') 'Setup explicitly enables SSH signing'
    Assert ((GitValue $moved user.signingkey) -eq $key.Replace('\','/')) 'File signing uses the private key path only'
    Good (Run git @('commit','--allow-empty','-m','Signing regression test') $moved) 'Create a real signed commit'
    Good (Run git @('verify-commit','HEAD') $moved) 'Verify real signature with managed allowed signers'
    Good (Run git @('config','ghprofile.profile','') $moved) 'Simulate absent legacy profile marker'
    Good (Run git @('config','user.signingkey',"$key.pub") $moved) 'Simulate legacy public-key signing setting'
    $r=Script @('status','-ConfigPath',$testConfig,'-Json') $moved
    Good $r 'Legacy status JSON'
    $legacyStatus=$r.Out | ConvertFrom-Json
    $legacyIssues=$legacyStatus.Issues -join ' '
    Assert ($legacyIssues -match 'legacy or unapplied' -and $legacyIssues -notmatch 'Effective Git identity differs|Effective signing key differs') 'Matching legacy settings receive a migration warning, not false mismatch warnings'
    Good (Run git @('config','--unset','ghprofile.profile') $moved) 'Remove fixture marker override'
    Good (Run git @('config','--unset','user.signingkey') $moved) 'Remove fixture signing override'
    $linked = Join-Path $scratch 'linked-outside-root'
    Good (Run git @('worktree','add','--detach',$linked,'HEAD') $moved) 'Create linked worktree outside profile root'
    $r = Script @('status','-ConfigPath',$testConfig,'-Json') $linked
    Good $r 'Linked worktree status'
    $linkedStatus = $r.Out | ConvertFrom-Json
    Assert ($linkedStatus.ExpectedProfile -eq 'personal' -and ($linkedStatus.Issues -join ' ') -match 'Linked worktree') 'Worktree diagnostics explain metadata-based selection'
    $before = [IO.File]::ReadAllText($testGlobal)
    $savedPublic = [IO.File]::ReadAllText("$key.pub")
    [IO.File]::Delete("$key.pub")
    $privateHash = (Get-FileHash -LiteralPath $key).Hash
    $r = Setup
    Assert ($r.Code -eq 1 -and (Get-FileHash -LiteralPath $key).Hash -eq $privateHash) 'Missing public key cannot overwrite existing private key'
    Assert ([IO.File]::ReadAllText($testGlobal) -ceq $before) 'Signing validation failure leaves config unchanged'
    $r = Script @('init-key','personal','-ConfigPath',$testConfig,'-NonInteractive')
    Assert ($r.Code -eq 1 -and $r.Error -match 'Refusing') 'init-key refuses a partial existing pair'
    [IO.File]::WriteAllText("$key.pub",$savedPublic)

    $encrypted=Join-Path $scratch 'encrypted-key'
    Good (Run ssh-keygen @('-q','-t','ed25519','-N','disposable-test-passphrase','-f',$encrypted)) 'Create encrypted disposable fixture'
    $config.profiles.personal.signingKey="$encrypted.pub"; SaveConfig
    $r=Setup
    Assert ($r.Code -eq 1 -and [IO.File]::ReadAllText($testGlobal) -ceq $before) 'Noninteractive encrypted key fails without hanging or activating changes'
    $config.profiles.personal.signingKey="$key.pub"; SaveConfig

    # Inject failure at a real mutation seam, after staging has begun.
    $originalScriptFile=$scriptFile
    $faultScript=Join-Path $scratch 'fault-ghprofile.ps1'
    $source=[IO.File]::ReadAllText($scriptFile).Replace('function Invoke-Native {','function Invoke-OriginalNative {')
    $wrapper=@'
function Invoke-Native {
    param([string]$Exe,[string[]]$Arguments,[int[]]$Allowed=@(0),[switch]$Interactive)
    if ($Exe -eq 'git' -and ($Arguments -join ' ') -match 'personal.gitconfig user.email') { throw 'Injected native write failure' }
    Invoke-OriginalNative @PSBoundParameters
}

function Protect-Text
'@
    $source=$source.Replace('function Protect-Text',$wrapper)
    [IO.File]::WriteAllText($faultScript,$source)
    $scriptFile=$faultScript
    $r=Setup
    $scriptFile=$originalScriptFile
    Assert ($r.Code -eq 1 -and $r.Error -match 'Injected native write failure') 'Native failure is propagated during staged generation'
    Assert ([IO.File]::ReadAllText($testGlobal) -ceq $before -and -not [IO.File]::Exists("$testGlobal.lock")) 'Mid-generation failure preserves active config and releases lock'
    $key2=Join-Path $scratch 'different-key'
    Good (Run ssh-keygen @('-q','-t','ed25519','-N','','-f',$key2)) 'Create mismatching test key'
    [IO.File]::WriteAllText("$key.pub",[IO.File]::ReadAllText("$key2.pub"))
    $r=Setup
    Assert ($r.Code -eq 1 -and $r.Error -match 'do not match') 'Mismatched key pair rejected'
    [IO.File]::WriteAllText("$key.pub",$savedPublic)

    Good (Run git @('remote','add','origin','https://github.com/example/repo.git') $moved) 'Add HTTPS fixture remote'
    Good (Run git @('config','user.email','override@example.invalid') $moved) 'Add local override'
    $r=Script @('status','-ConfigPath',$testConfig,'-Json') $moved @{ GIT_AUTHOR_EMAIL='environment@example.invalid' }
    Good $r 'Status JSON with local and environment overrides'
    $status=$r.Out | ConvertFrom-Json
    Assert ($status.ExpectedProfile -eq 'personal' -and ($status.Issues -join ' ') -match 'Effective Git identity differs' -and ($status.Issues -join ' ') -match 'AUTHOR differs') 'Status detects expected/effective and author overrides'
    Assert ($status.PushDestinations[0].Authentication -eq 'unverified' -and $status.PushDestinations[0].ConfiguredHttpsUsername -eq 'personal-user') 'Status does not claim a verified push account'
    $r=Script @('doctor','-ConfigPath',$testConfig,'-Json','-NonInteractive') $moved
    Assert ($r.Code -eq 2 -and ($r.Out | ConvertFrom-Json).Healthy -eq $false) 'Doctor returns exit 2 for diagnostic findings'
    Good (Run git @('remote','set-url','origin','git@github.com:example/repo.git') $moved) 'Use SSH remote'
    $r=Script @('status','-ConfigPath',$testConfig,'-Json') $moved
    $status=$r.Out | ConvertFrom-Json
    Assert ($status.PushDestinations[0].Transport -eq 'ssh' -and ($status.Issues -join ' ') -match 'uses SSH') 'SSH credentials are explicitly unverified'
    $r=Script @('switch','personal','-ConfigPath',$testConfig) $moved @{ GH_TOKEN='test-token-never-use' }
    Assert ($r.Code -eq 1 -and $r.Error -match 'environment token' -and $r.Error -notmatch 'test-token-never-use') 'Environment token blocks switching without exposing token'
    $r=Script @('status','-ConfigPath',$testConfig,'-Json') $scratch
    Good $r 'Status outside a repository'
    Assert (-not ($r.Out | ConvertFrom-Json).InRepository) 'Outside-repository status does not invent an identity'
    $r=Script @('switch','personal','-ConfigPath',$testConfig,'-WhatIf')
    Good $r 'Switch WhatIf performs no authentication change'

    $config.profiles.personal.roots=@($moved,$personal); $config.Remove('default'); SaveConfig
    Good (Setup) 'Strict policy supports multiple roots without a default'
    Assert ((GitValue $personal user.email) -eq 'personal@example.invalid') 'Additional root takes effect'
    # Rotate the signing key from outside all roots; old signatures remain verifiable.
    $config.profiles.personal.signingKey="$key2.pub"; SaveConfig
    Good (Setup) 'Rotate signing key from outside configured roots'
    Good (Run git @('verify-commit','HEAD') $moved) 'Historical signature trust survives rotation outside roots'
    $config.profiles.personal.host='github.example.com'; SaveConfig
    Good (Setup) 'Enterprise host setup'
    $r=Run git @('config','--get-urlmatch','credential.username','https://github.example.com/team/repo') $personal
    Assert ($r.Out -eq 'personal-user') 'Host-specific credential username'

    # Unit seam: invoke real functions while mocking ONLY external gh/agent responses.
    foreach ($fn in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)) { . ([scriptblock]::Create($fn.Extent.Text)) }
    $text=@(Format-Status $legacyStatus -Width 60)
    Assert (@($text | Where-Object { $_.Length -gt 60 }).Count -eq 0) 'Console output wraps to narrow terminal width'
    Assert (($text -join "`n") -notmatch '"Value"|"Origin"|"Remote"|\t|global\s+file:') 'Default output contains no serialized objects or config origins'
    Assert (($text -join "`n") -match 'Author\s+:' -and ($text -join "`n") -notmatch 'Committer\s+:') 'Console summary omits duplicate committer identity'
    Assert (($text -join "`n") -match 'unmanaged / legacy' -and ($text -join "`n") -match 'Warning\s+:') 'Legacy summary preserves the actionable warning'
    function Invoke-Native { param($Exe,$Arguments,$Allowed,$Interactive)
        [pscustomobject]@{ Code=0; Out='{"hosts":{"github.com":[{"active":true,"login":"personal-user","state":"error"}]}}'; Error='' }
    }
    $state=Get-GhState github.com
    Assert (-not $state.Healthy -and $state.Login -eq 'personal-user') 'JSON auth errors are detected even with exit zero'
    Assert ((Protect-Text 'https://user:secret@github.com/repo') -notmatch 'secret') 'URL credentials are redacted'
    $agentPublic=Join-Path $scratch 'agent-only.pub'
    [IO.File]::WriteAllText($agentPublic,$savedPublic)
    $script:agentOutput=$savedPublic
    function Invoke-Native { param($Exe,$Arguments,$Allowed,$Interactive)
        [pscustomobject]@{ Code=0; Out=$(if ($Exe -eq 'ssh-add') { $script:agentOutput } else { 'fingerprint' }); Error='' }
    }
    $agentProfile=[pscustomobject]@{Id='agent';Mode='agent';Key=$agentPublic}
    $result=@(Test-SigningKey $agentProfile)
    Assert ($result.Count -eq 1 -and $result[0] -eq (Get-PublicIdentity $savedPublic)) 'Agent signing returns one value and does not require a private key file'
    $script:agentOutput=[IO.File]::ReadAllText("$key2.pub")
    $rejected=$false
    try { [void](Test-SigningKey $agentProfile) } catch { $rejected=$_.Exception.Message -match 'not loaded' }
    Assert $rejected 'Agent mode rejects an unloaded public key'
    Write-Output "`n$passed checks passed. Fixtures: $scratch"
} catch { [Console]::Error.WriteLine($_.ToString()); [Console]::Error.WriteLine($_.ScriptStackTrace); exit 1 }
