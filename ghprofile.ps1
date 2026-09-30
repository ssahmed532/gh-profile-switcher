#requires -Version 7.2
<#
.SYNOPSIS
Manage folder-based Git identities and explicitly switch GitHub CLI accounts.
.DESCRIPTION
Commands: setup, status, doctor, switch <profile>, init-key <profile>.
--version prints only the semantic version, without reading configuration.
See docs/HOWTO.html for policy, migration, recovery and exit codes.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)][string]$Command,
    [Parameter(Position = 1)][string]$Name,
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'profiles.json'),
    [Alias('-version')][switch]$Version,
    [switch]$Json,
    [switch]$Plain,
    [ValidateSet('Auto','Always','Never')][string]$Color = 'Auto',
    [switch]$NonInteractive
)

$ScriptVersion = '0.3.2'
if ($Version -or $Command -eq '--version') { Write-Output "v$ScriptVersion"; exit 0 }
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Prerequisites {
    $missing = @(
        foreach ($tool in @('gh', 'git')) {
            if (-not (Get-Command $tool -CommandType Application -ErrorAction SilentlyContinue)) {
                if ($tool -eq 'gh') { 'GitHub CLI (gh)' } else { 'Git CLI (git)' }
            }
        }
    )
    if ($missing.Count) {
        throw "Missing required command(s): $($missing -join ', '). Install the missing tools and add them to PATH, then retry."
    }
}

function Invoke-Native {
    param([string]$Exe, [string[]]$Arguments, [int[]]$Allowed = @(0), [switch]$Interactive, [switch]$CaptureOutput)
    # OpenSSH may write prompts straight to the console, bypassing its streams.
    # Prevent untrusted argument text from reaching that unsanitizable channel.
    if ($Interactive -and @($Arguments | Where-Object { $_ -match '[\p{Cc}\u061c\u200e\u200f\u2028-\u202e\u2066-\u2069]' }).Count) {
        throw 'Interactive native arguments cannot contain terminal control characters.'
    }
    $app = Get-Command $Exe -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $info = [Diagnostics.ProcessStartInfo]::new($app.Source)
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.RedirectStandardInput = -not $Interactive
    $info.WorkingDirectory = (Get-Location).ProviderPath
    foreach ($arg in $Arguments) { $info.ArgumentList.Add($arg) }
    if (-not $Interactive) { $info.Environment['SSH_ASKPASS_REQUIRE'] = 'never' }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    $started = $false
    try {
        [void]$process.Start()
        $started = $true
        if (-not $Interactive) { $process.StandardInput.Close() }
        if ($Interactive) {
            # Drain both streams while the child is waiting, including prompts
            # without a newline. Only key derivation captures stdout as data.
            $streams = @(
                @{ Reader=$process.StandardOutput; Chars=[char[]]::new(512); Text=[Text.StringBuilder]::new(); Pending=''; Error=$false; Display=(-not $CaptureOutput) },
                @{ Reader=$process.StandardError; Chars=[char[]]::new(512); Text=[Text.StringBuilder]::new(); Pending=''; Error=$true; Display=$true }
            )
            foreach ($stream in $streams) { $stream.Task = $stream.Reader.ReadAsync($stream.Chars, 0, $stream.Chars.Length) }
            while (@($streams | Where-Object { $null -ne $_.Task }).Count) {
                foreach ($stream in $streams) {
                    if ($null -eq $stream.Task -or -not $stream.Task.IsCompleted) { continue }
                    $count = $stream.Task.GetAwaiter().GetResult()
                    if ($count) {
                        $chunk = [string]::new($stream.Chars, 0, $count)
                        [void]$stream.Text.Append($chunk)
                        if ($stream.Display) { $stream.Pending += $chunk; Write-NativePendingText $stream }
                        $stream.Task = $stream.Reader.ReadAsync($stream.Chars, 0, $stream.Chars.Length)
                    } else {
                        if ($stream.Display) { Write-NativePendingText $stream -Final }
                        $stream.Task = $null
                    }
                }
                # A short managed wait lets PowerShell service pipeline cancellation.
                Start-Sleep -Milliseconds 20
            }
            while (-not $process.WaitForExit(50)) { }
            $output = if ($CaptureOutput) { $streams[0].Text.ToString() } else { '' }
            $errorText = $streams[1].Text.ToString()
        } else {
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(30000)) { throw "$Exe timed out after 30 seconds." }
            $output = $stdout.GetAwaiter().GetResult()
            $errorText = $stderr.GetAwaiter().GetResult()
        }
        $result = [pscustomobject]@{ Code = $process.ExitCode; Out = $output.TrimEnd("`r", "`n"); Error = $errorText.Trim() }
        if ($result.Code -notin $Allowed) {
            $detail = Protect-Text $result.Error
            throw "$Exe failed (exit $($result.Code)): $detail"
        }
        return $result
    } finally {
        # Dispose alone does not terminate a child. Release it before callers
        # release their owned locks, including when the pipeline is stopped.
        try { if ($started -and -not $process.HasExited) { $process.Kill($true); $process.WaitForExit() } }
        finally { $process.Dispose() }
    }
}

function Write-NativePendingText {
    param([hashtable]$Stream, [switch]$Final)
    $text = $Stream.Pending
    $cut = $text.Length
    if (-not $Final) {
        # Retain incomplete credentials across read boundaries. Ordinary prompt
        # text can be displayed immediately without waiting for a newline.
        foreach ($pattern in @('(?i)https?://[^\s]*$', '(?i)(?:gh[pousr]_|github_pat_)[A-Za-z0-9_]*$')) {
            $match = [regex]::Match($text, $pattern)
            if ($match.Success) { $cut = [Math]::Min($cut, $match.Index) }
        }
        $markers = @('http://','https://','ghp_','gho_','ghu_','ghs_','ghr_','github_pat_')
        foreach ($key in @('GH_TOKEN','GITHUB_TOKEN','GH_ENTERPRISE_TOKEN','GITHUB_ENTERPRISE_TOKEN')) {
            $secret = [Environment]::GetEnvironmentVariable($key)
            if ($secret) { $markers += $secret }
        }
        foreach ($marker in $markers) {
            for ($length = 1; $length -lt $marker.Length -and $length -le $text.Length; $length++) {
                if ($text.EndsWith($marker.Substring(0,$length), [StringComparison]::OrdinalIgnoreCase)) { $cut = [Math]::Min($cut, $text.Length - $length) }
            }
        }
        if ($text.Length -and [char]::IsHighSurrogate($text[$text.Length - 1])) { $cut = [Math]::Min($cut, $text.Length - 1) }
        if ($text.EndsWith("`r")) { $cut = [Math]::Min($cut, $text.Length - 1) }
        # Do not split a complete secret because its tail happens to also be
        # the prefix of another marker (or of the same secret).
        $patterns = @('(?i)https?://[^/\s@]+@', '(?i)\b(?:gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+)\b')
        foreach ($key in @('GH_TOKEN','GITHUB_TOKEN','GH_ENTERPRISE_TOKEN','GITHUB_ENTERPRISE_TOKEN')) {
            $secret = [Environment]::GetEnvironmentVariable($key)
            if ($secret) { $patterns += [regex]::Escape($secret) }
        }
        do {
            $previousCut = $cut
            foreach ($pattern in $patterns) {
                foreach ($match in [regex]::Matches($text, $pattern)) {
                    if ($match.Index -lt $cut -and $match.Index + $match.Length -gt $cut) { $cut = $match.Index }
                }
            }
        } while ($cut -ne $previousCut)
    }
    if ($cut) {
        $safe = Protect-Text $text.Substring(0,$cut) -PreserveNewlines
        if ($Stream.Error) { [Console]::Error.Write($safe) } else { [Console]::Write($safe) }
    }
    $Stream.Pending = $text.Substring($cut)
}

function Protect-Text([string]$Text, [switch]$PreserveNewlines) {
    $Text = $Text -replace '(?i)(https?://)[^/\s@]+@', '$1<redacted>@'
    $Text = $Text -replace '(?i)\b(?:gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+)\b', '<redacted>'
    foreach ($key in @('GH_TOKEN','GITHUB_TOKEN','GH_ENTERPRISE_TOKEN','GITHUB_ENTERPRISE_TOKEN')) {
        $secret = [Environment]::GetEnvironmentVariable($key)
        if ($secret) { $Text = $Text.Replace($secret, '<redacted>') }
    }
    if ($PreserveNewlines) { $Text = $Text.Replace("`r`n", "`n") }
    # Escape every C0/C1 control (including ESC, BEL, CR and backspace),
    # directional overrides/isolates and Unicode line separators. Escaping the
    # introducers also neutralizes CSI/OSC/DCS, even incomplete sequences.
    # Keep ordinary Unicode, combining accents and emoji joiners intact.
    return [regex]::Replace($Text, '[\p{Cc}\u061c\u200e\u200f\u2028-\u202e\u2066-\u2069]', {
        param($match)
        if ($PreserveNewlines -and $match.Value -eq "`n") { return "`n" }
        '\u{0:X4}' -f [int][char]$match.Value
    })
}

function Resolve-ProfilePath([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -match '[\r\n\x00]') { throw 'A nonempty single-line path is required.' }
    $Value = $Value.Replace('\', '/')
    if ($Value.StartsWith('~/')) { $Value = Join-Path $HOME $Value.Substring(2) }
    if (-not [IO.Path]::IsPathFullyQualified($Value)) { throw "Use an absolute path or ~/ path: $Value" }
    return [IO.Path]::GetFullPath($Value).Replace('\', '/')
}

function Read-Profiles {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "Configuration not found: $ConfigPath. Copy profiles.example.json and fill it in." }
    $c = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -AsHashtable
    if ($c -isnot [System.Collections.IDictionary]) { throw 'Configuration must be a JSON object.' }
    foreach ($field in $c.Keys) { if ($field -notin @('schemaVersion','policy','default','profiles')) { throw "Unknown configuration field: $field" } }
    if ($c.Contains('schemaVersion') -and $c.schemaVersion -ne 1) { throw 'Unsupported schemaVersion; expected 1.' }
    if ($c.profiles -isnot [System.Collections.IDictionary] -or $c.profiles.Count -eq 0) { throw 'profiles must be a nonempty object.' }
    $policy = if ($c.Contains('policy')) { $c.policy } else { 'default' }
    if ($policy -notin @('default','strict')) { throw 'policy must be default or strict.' }
    if ($policy -eq 'default' -and (-not $c.default -or -not $c.profiles.Contains($c.default))) { throw 'default must name an existing profile.' }
    $profiles = [ordered]@{}
    $roots = [Collections.Generic.List[string]]::new()
    foreach ($id in $c.profiles.Keys) {
        if ($id -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$') { throw "Invalid profile identifier: $id" }
        if ($profiles.Contains($id)) { throw "Profile identifiers must be unique ignoring case: $id" }
        $p = $c.profiles[$id]
        if ($p -isnot [System.Collections.IDictionary]) { throw "Profile '$id' must be an object." }
        foreach ($field in $p.Keys) { if ($field -notin @('name','email','ghUser','host','signingMode','signingKey','root','roots')) { throw "Unknown field '$field' in profile '$id'." } }
        foreach ($field in @('name','email','ghUser')) {
            if ($p[$field] -isnot [string] -or [string]::IsNullOrWhiteSpace($p[$field]) -or $p[$field] -match '[\r\n\x00]' -or $p[$field] -like '*REPLACE-ME*') { throw "Profile '$id' needs a valid $field." }
        }
        if ($p.email -notmatch '^[^\s,"<>\\]+@[^\s,"<>\\]+$') { throw "Profile '$id' has an invalid email." }
        if ($p.ghUser -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]*$') { throw "Profile '$id' has an invalid ghUser." }
        $hostName = if ($p.Contains('host')) { $p.host } else { 'github.com' }
        if ($hostName -isnot [string] -or $hostName -notmatch '^(?=.{1,253}$)[a-zA-Z0-9]+(?:[.-][a-zA-Z0-9]+)*$') { throw "Profile '$id' has an invalid host." }
        $mode = if ($p.Contains('signingMode')) { $p.signingMode } else { 'file' }
        if ($mode -notin @('file','agent','none')) { throw "Profile '$id': signingMode must be file, agent or none." }
        $key = if ($mode -ne 'none') { Resolve-ProfilePath $p.signingKey } else { '' }
        if ($key -and -not $key.EndsWith('.pub', [StringComparison]::Ordinal)) { throw "Profile '$id': signingKey must name a .pub file." }
        $profileRoots = @()
        if ($p.Contains('root') -and $p.Contains('roots')) { throw "Profile '$id': use root or roots, not both." }
        if ($p.Contains('roots') -and $p.roots -isnot [array]) { throw "Profile '$id': roots must be an array." }
        $rawRoots = if ($p.Contains('roots')) { @($p.roots) } elseif ($p.Contains('root')) { @($p.root) } else { @() }
        foreach ($raw in $rawRoots) {
            $root = (Resolve-ProfilePath $raw).TrimEnd('/') + '/'
            if ($root -match '[*?\[\]]') { throw "Root paths cannot contain glob characters: $root" }
            foreach ($other in $roots) {
                $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
                if ($root.StartsWith($other, $comparison) -or $other.StartsWith($root, $comparison)) { throw "Overlapping roots are not supported: $root and $other" }
            }
            $roots.Add($root)
            $profileRoots += $root
        }
        if (($policy -eq 'strict' -or $id -ne $c['default']) -and $profileRoots.Count -eq 0) { throw "Profile '$id' needs at least one root." }
        $profiles[$id] = [pscustomobject]@{ Id=$id; Name=$p.name; Email=$p.email; User=$p.ghUser; Host=$hostName.ToLowerInvariant(); Mode=$mode; Key=$key; Roots=$profileRoots }
    }
    return [pscustomobject]@{ Policy=$policy; Default=$c['default']; Profiles=$profiles }
}

function Get-GlobalPath {
    if ($env:GIT_CONFIG_GLOBAL) { return Resolve-ProfilePath $env:GIT_CONFIG_GLOBAL }
    $gitHome = if ($env:HOME) { Resolve-ProfilePath $env:HOME } else { $HOME }
    $usual = Join-Path $gitHome '.gitconfig'
    $xdg = if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME 'git/config' } else { Join-Path $gitHome '.config/git/config' }
    if (-not (Test-Path -LiteralPath $usual) -and (Test-Path -LiteralPath $xdg)) { return Resolve-ProfilePath $xdg }
    return Resolve-ProfilePath $usual
}

function Set-GitValue([string]$File, [string]$Key, [string]$Value, [switch]$Add) {
    $arguments = @('config','--file',$File)
    if ($Add) { $arguments += '--add' }
    [void](Invoke-Native git ($arguments + @($Key,$Value)))
}

function Get-GitValue([string]$Key) {
    return (Invoke-Native git @('config','--get',$Key) -Allowed @(0,1)).Out
}

function Get-PublicIdentity([string]$Text) {
    $parts = $Text.Trim() -split '\s+'
    if ($parts.Count -lt 2 -or $parts[0] -notmatch '^(ssh-|ecdsa-|sk-)' -or $parts[1] -notmatch '^[A-Za-z0-9+/]+=*$' -or $Text.Trim() -match '[\r\n]') { throw 'Invalid SSH public key.' }
    return "$($parts[0]) $($parts[1])"
}

function Test-SigningKey($Profile) {
    if ($Profile.Mode -eq 'none') { return '' }
    if (-not (Test-Path -LiteralPath $Profile.Key -PathType Leaf)) { throw "Profile '$($Profile.Id)': public key missing. Restore it from the existing private key, or use init-key for a new pair." }
    [void](Invoke-Native ssh-keygen @('-l','-f',$Profile.Key))
    $public = Get-PublicIdentity (Get-Content -LiteralPath $Profile.Key -Raw)
    if ($Profile.Mode -eq 'agent') {
        $available = (Invoke-Native ssh-add @('-L')).Out -split '\r?\n'
        $matches = @($available | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Where-Object { (Get-PublicIdentity $_) -ceq $public })
        if ($matches.Count -eq 0) { throw "Profile '$($Profile.Id)': signing key is not loaded in ssh-agent." }
    } else {
        $private = $Profile.Key.Substring(0, $Profile.Key.Length - 4)
        if (-not (Test-Path -LiteralPath $private -PathType Leaf)) { throw "Profile '$($Profile.Id)': adjacent private key is missing; use agent mode if appropriate." }
        $arguments = @('-y','-f',$private)
        if ($NonInteractive) { $arguments += @('-P','') }
        $derived = (Invoke-Native ssh-keygen $arguments -Interactive:(-not $NonInteractive) -CaptureOutput).Out
        if ((Get-PublicIdentity $derived) -cne $public) { throw "Profile '$($Profile.Id)': public and private keys do not match." }
    }
    return $public
}

function New-ProfileKey($Profile) {
    if ($Profile.Mode -eq 'none') { throw 'This profile has signing disabled.' }
    $private = $Profile.Key.Substring(0, $Profile.Key.Length - 4)
    if ((Test-Path -LiteralPath $private) -or (Test-Path -LiteralPath $Profile.Key)) { throw 'Refusing to replace either member of an existing key pair.' }
    if ($PSCmdlet.ShouldProcess((Protect-Text $private), 'Create an Ed25519 signing key pair (passphrase prompted)')) {
        if ($NonInteractive) { throw 'init-key requires an interactive passphrase prompt. Provision keys externally for automation.' }
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($private))
        $keyLock = [IO.File]::Open("$private.ghprofile-lock", 'CreateNew', 'Write', 'None')
        try {
            if ((Test-Path -LiteralPath $private) -or (Test-Path -LiteralPath $Profile.Key)) { throw 'A key pair appeared while acquiring the lock.' }
            [void](Invoke-Native ssh-keygen @('-t','ed25519','-C',$Profile.Email,'-f',$private) -Interactive)
        } finally { $keyLock.Dispose(); [IO.File]::Delete("$private.ghprofile-lock") }
        Write-Output (Protect-Text "Created signing key: $($Profile.Key)")
    }
}

function Install-Profiles($Configuration) {
    $global = Get-GlobalPath
    Write-SetupEvent 'PLAN' 'Config' $global
    Write-SetupEvent '' 'Policy' $Configuration.Policy
    foreach ($p in $Configuration.Profiles.Values) {
        $roots = if ($p.Roots.Count) { $p.Roots -join '; ' } else { 'unmatched repositories (default)' }
        Write-SetupEvent '' 'Profile' "$($p.Id) -> $roots; signing: $($p.Mode)"
    }
    if ($WhatIfPreference) { Write-SetupEvent 'PREVIEW' 'No changes' 'Profile data validated. Key validation and configuration activation will run when applying setup.' 'warning' }
    if (-not $PSCmdlet.ShouldProcess((Protect-Text $global), 'Validate keys and atomically activate managed Git profiles')) { return }
    Write-SetupEvent 'VALIDATION' 'Checking' 'Validating signing keys before changing configuration. Encrypted file keys may prompt for a passphrase.'
    $publicKeys = @{}
    foreach ($p in $Configuration.Profiles.Values) {
        $publicKeys[$p.Id] = Test-SigningKey $p
        $description = if ($p.Mode -eq 'none') { 'Signing disabled by profile policy.' } else { 'Signing key validated.' }
        Write-SetupEvent '' 'Profile' "$($p.Id): $description" 'success'
    }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($global))
    $lockPath = "$global.lock"
    $lock = [IO.File]::Open($lockPath, 'CreateNew', 'Write', 'None')
    $managed = "$global.ghprofile"
    $stage = "$global.ghprofile-stage-$([guid]::NewGuid().ToString('N'))"
    try {
        Write-SetupEvent 'CONFIGURATION' 'Preparing' 'Lock acquired. Building and validating a new managed configuration.'
        $existed = [IO.File]::Exists($global)
        $original = [byte[]]@()
        if ($existed) { $original = [IO.File]::ReadAllBytes($global) }
        [IO.File]::WriteAllBytes($stage, $original)
        [void](Invoke-Native git @('config','--file',$stage,'--list'))
        # Detach only files bearing our ownership marker; preserve unrelated includes.
        $includes = (Invoke-Native git @('config','--file',$stage,'--null','--get-regexp','^(include\.path|includeif\..*\.path)$') -Allowed @(0,1)).Out
        foreach ($line in ($includes -split "`0")) {
            if (-not $line) { continue }
            $pair = $line -split "`n", 2
            $path = $pair[1]
            $expanded = if ($path.StartsWith('~/')) { Join-Path $HOME $path.Substring(2) } elseif ([IO.Path]::IsPathFullyQualified($path)) { $path } else { Join-Path ([IO.Path]::GetDirectoryName($global)) $path }
            if (Test-Path -LiteralPath $expanded -PathType Leaf) {
                $first = Get-Content -LiteralPath $expanded -TotalCount 1
                if ($first -in @('# Managed by ghprofile.ps1; do not edit.', '# Generated by ghprofile.ps1 from profiles.json - edit that file and re-run setup.')) {
                    [void](Invoke-Native git @('config','--file',$stage,'--fixed-value','--unset-all',$pair[0],$path) -Allowed @(0,5))
                }
            }
        }
        $generation = Join-Path $managed ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($generation)
        $dispatcher = Join-Path $generation 'config'
        [IO.File]::WriteAllText($dispatcher, "# Managed by ghprofile.ps1; do not edit.`n")
        Set-GitValue $dispatcher user.useConfigOnly true
        Set-GitValue $dispatcher user.name ''
        Set-GitValue $dispatcher user.email ''
        Set-GitValue $dispatcher user.signingkey ''
        Set-GitValue $dispatcher commit.gpgsign false
        Set-GitValue $dispatcher ghprofile.profile ''
        foreach ($hostName in @($Configuration.Profiles.Values.Host | Select-Object -Unique)) {
            Set-GitValue $dispatcher "credential.https://$hostName.username" ''
        }
        $signers = Join-Path $generation 'allowed_signers'
        $signerLines = [Collections.Generic.List[string]]::new()
        $oldSigners = (Invoke-Native git @('config','--global','--includes','--path','--get','gpg.ssh.allowedSignersFile') -Allowed @(0,1)).Out
        if ($oldSigners -and -not [IO.Path]::IsPathFullyQualified($oldSigners)) { throw 'Existing allowedSignersFile must be absolute; resolve its repository-relative policy before setup.' }
        if ($oldSigners -and -not (Test-Path -LiteralPath $oldSigners -PathType Leaf)) { throw 'Existing allowedSignersFile is missing; restore it or remove its stale Git configuration before setup.' }
        if ($oldSigners -and (Test-Path -LiteralPath $oldSigners -PathType Leaf)) {
            foreach ($line in [IO.File]::ReadAllLines($oldSigners)) { $signerLines.Add($line) }
        }
        Set-GitValue $dispatcher gpg.ssh.allowedSignersFile $signers.Replace('\','/')
        foreach ($p in $Configuration.Profiles.Values) {
            $file = Join-Path $generation "$($p.Id).gitconfig"
            [IO.File]::WriteAllText($file, "# Managed by ghprofile.ps1; do not edit.`n")
            Set-GitValue $file user.name $p.Name
            Set-GitValue $file user.email $p.Email
            Set-GitValue $file ghprofile.profile $p.Id
            Set-GitValue $file "credential.https://$($p.Host).username" $p.User
            Set-GitValue $file commit.gpgsign ($p.Mode -ne 'none').ToString().ToLowerInvariant()
            if ($p.Mode -ne 'none') {
                Set-GitValue $file gpg.format ssh
                $key = if ($p.Mode -eq 'file') { $p.Key.Substring(0,$p.Key.Length - 4) } else { $p.Key }
                Set-GitValue $file user.signingkey $key
                Set-GitValue $file gpg.ssh.allowedSignersFile $signers.Replace('\','/')
                $signerLines.Add("$($p.Email) namespaces=`"git`" $($publicKeys[$p.Id])")
            } else { Set-GitValue $file user.signingkey '' }
        }
        [IO.File]::WriteAllLines($signers, @($signerLines | Select-Object -Unique))
        if ($Configuration.Policy -eq 'default') { Set-GitValue $dispatcher include.path (Join-Path $generation "$($Configuration.Default).gitconfig").Replace('\','/') -Add }
        foreach ($p in $Configuration.Profiles.Values) {
            foreach ($root in $p.Roots) {
                $condition = if ($IsWindows) { 'gitdir/i' } else { 'gitdir' }
                Set-GitValue $dispatcher "includeIf.${condition}:$root.path" (Join-Path $generation "$($p.Id).gitconfig").Replace('\','/') -Add
            }
        }
        # --add can reuse an earlier [include] section. Serialize separately, then
        # append the entire section so our dispatcher is always last in this file.
        $integration = Join-Path $generation 'integration.gitconfig'
        Set-GitValue $integration include.path $dispatcher.Replace('\','/')
        [IO.File]::AppendAllText($stage, "`n" + [IO.File]::ReadAllText($integration))
        [void](Invoke-Native git @('config','--file',$stage,'--includes','--list'))
        # Includes not matched in this directory still need syntax validation.
        foreach ($p in $Configuration.Profiles.Values) {
            [void](Invoke-Native git @('config','--file',(Join-Path $generation "$($p.Id).gitconfig"),'--list'))
        }
        [IO.File]::WriteAllText((Join-Path $generation 'manifest.json'), (@{ version=$ScriptVersion; policy=$Configuration.Policy; source=[IO.Path]::GetFullPath($ConfigPath); created=[DateTime]::UtcNow.ToString('o') } | ConvertTo-Json))
        $backup = if ($existed) { "$global.bak-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff'))-$([guid]::NewGuid().ToString('N'))" } else { $null }
        if ($backup) { [IO.File]::Copy($global,$backup,$false) }
        # Same-volume atomic replacement: failure before this point leaves active config unchanged.
        if ($existed) { [IO.File]::Replace($stage,$global,[NullString]::Value) } else { [IO.File]::Move($stage,$global) }
        Write-SetupEvent 'COMPLETE' 'Activated' "Configured $($Configuration.Profiles.Count) profiles ($($Configuration.Policy) policy)." 'success'
        if ($backup) { Write-SetupEvent '' 'Backup' $backup }
        else { Write-SetupEvent '' 'Backup' 'Not needed: no previous global configuration existed.' }
        Write-SetupEvent 'NEXT STEP' 'Verify' 'Run ghprofile.ps1 doctor inside each repository. Git credentials and GitHub signing-key registration are checked separately.'
    } finally {
        if ([IO.File]::Exists($stage)) { [IO.File]::Delete($stage) }
        $lock.Dispose()
        [IO.File]::Delete($lockPath)
    }
}

function Get-TokenOverrides([string]$HostName) {
    $keys = if ($HostName -eq 'github.com' -or $HostName.EndsWith('.ghe.com')) { @('GH_TOKEN','GITHUB_TOKEN') } else { @('GH_ENTERPRISE_TOKEN','GITHUB_ENTERPRISE_TOKEN') }
    return @($keys | Where-Object { [Environment]::GetEnvironmentVariable($_) })
}

function Get-GhState([string]$HostName) {
    $overrides = @(Get-TokenOverrides $HostName)
    try {
        $r = Invoke-Native gh @('auth','status','--hostname',$HostName,'--json','hosts')
        $data = $r.Out | ConvertFrom-Json -AsHashtable
        $accounts = @($data.hosts[$HostName])
        $active = @($accounts | Where-Object { $_ -and $_.active })
        if ($active.Count -ne 1) { throw 'No unique active account.' }
        $a = $active[0]
        return [pscustomobject]@{ Host=$HostName; Login=$a.login; Healthy=($a.state -eq 'success'); TokenOverrides=$overrides; Error= $(if ($a.state -ne 'success') { 'Authentication could not be verified.' } else { '' }) }
    } catch { return [pscustomobject]@{ Host=$HostName; Login=''; Healthy=$false; TokenOverrides=$overrides; Error=(Protect-Text $_.Exception.Message) } }
}

function Get-Status($Configuration, [switch]$Doctor) {
    $issues = [Collections.Generic.List[string]]::new()
    $repo = Invoke-Native git @('rev-parse','--absolute-git-dir') -Allowed @(0,128)
    $inRepo = $repo.Code -eq 0
    if ($Doctor -and -not $inRepo) { $issues.Add('Run doctor inside a repository to validate repository identity and signing configuration.') }
    $expected = $null
    $actual = ''
    $settings = [ordered]@{}
    $remotes = @()
    if ($inRepo) {
        $gitDirectory = $repo.Out.Replace('\','/').TrimEnd('/') + '/'
        foreach ($p in $Configuration.Profiles.Values) {
            foreach ($root in $p.Roots) {
                $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
                if ($gitDirectory.StartsWith($root,$comparison)) { $expected = $p }
            }
        }
        if (-not $expected -and $Configuration.Policy -eq 'default') { $expected = $Configuration.Profiles[$Configuration.Default] }
        foreach ($key in @('user.name','user.email','user.signingkey','commit.gpgsign','gpg.format','gpg.ssh.allowedSignersFile','ghprofile.profile')) {
            $settings[$key] = [pscustomobject]@{ Value=(Get-GitValue $key); Origin=(Invoke-Native git @('config','--show-origin','--show-scope','--get',$key) -Allowed @(0,1)).Out }
        }
        $actual = $settings['ghprofile.profile'].Value
        if (-not $expected) { $issues.Add('Repository is outside all configured roots (strict policy).') }
        else {
            if (-not $actual) { $issues.Add('Managed profile marker is missing (legacy or unapplied setup). Run ghprofile.ps1 setup to migrate configuration.') }
            if (($actual -and $actual -cne $expected.Id) -or $settings['user.name'].Value -cne $expected.Name -or $settings['user.email'].Value -cne $expected.Email) { $issues.Add('Effective Git identity differs from the expected folder profile; inspect configuration origins and rerun setup if necessary.') }
            $expectedKey = if ($expected.Mode -eq 'file') { $expected.Key.Substring(0,$expected.Key.Length-4) } else { $expected.Key }
            $configuredKey = $settings['user.signingkey'].Value.Replace('\','/')
            $legacyKey = -not $actual -and $expected.Mode -eq 'file' -and $configuredKey -ceq $expected.Key
            if ($configuredKey -cne $expectedKey -and -not $legacyKey) { $issues.Add('Effective signing key differs from the expected profile.') }
            $signing = $settings['commit.gpgsign'].Value -in @('true','yes','on','1')
            if ($signing -ne ($expected.Mode -ne 'none') -or ($signing -and $settings['gpg.format'].Value -ne 'ssh')) { $issues.Add('Effective commit signing settings differ from the expected profile.') }
            if ($Doctor) { try { [void](Test-SigningKey $expected) } catch { $issues.Add((Protect-Text $_.Exception.Message)) } }
        }
        foreach ($kind in @('AUTHOR','COMMITTER')) {
            $ident = Invoke-Native git @('var',"GIT_${kind}_IDENT") -Allowed @(0,128)
            $settings[$kind.ToLowerInvariant()] = $ident.Out -replace ' \d+ [+-]\d{4}$',''
            if ($expected -and $settings[$kind.ToLowerInvariant()] -cne "$($expected.Name) <$($expected.Email)>") { $issues.Add("Effective $kind differs from the expected identity (environment or author/committer override).") }
        }
        foreach ($remote in ((Invoke-Native git @('remote')).Out -split '\r?\n')) {
            if (-not $remote) { continue }
            foreach ($url in ((Invoke-Native git @('remote','get-url','--push','--all',$remote)).Out -split '\r?\n')) {
                $transport = if ($url -match '^https://') { 'https' } elseif ($url -match '^(ssh://|[^/]+@[^:]+:)') { 'ssh' } else { 'other' }
                $username = ''; $helper = ''; $remoteHost = ''
                if ($transport -eq 'https') {
                    $uri = [uri]$url
                    $remoteHost = $uri.DnsSafeHost
                    $username = (Invoke-Native git @('config','--get-urlmatch','credential.username',$url) -Allowed @(0,1)).Out
                    $helper = (Invoke-Native git @('config','--get-urlmatch','credential.helper',$url) -Allowed @(0,1)).Out
                    if ($uri.UserInfo) { $issues.Add("Remote '$remote' contains URL credentials; remove them and use a credential manager.") }
                    if (-not $helper) { $issues.Add("Remote '$remote' has no configured HTTPS credential helper.") }
                    if ($expected -and $remoteHost -eq $expected.Host -and $username -cne $expected.User) { $issues.Add("Remote '$remote' HTTPS username differs from the expected profile.") }
                } elseif ($transport -eq 'ssh') { $issues.Add("Remote '$remote' uses SSH: its authentication key is separate from the commit-signing key; verify SSH configuration independently.") }
                else { $issues.Add("Remote '$remote' uses an unsupported authentication transport.") }
                if ($expected -and $remoteHost -and $remoteHost -ne $expected.Host) { $issues.Add("Remote '$remote' targets a different host from the expected profile.") }
                $remotes += [pscustomobject]@{ Remote=$remote; PushUrl=(Protect-Text $url); Transport=$transport; ConfiguredHttpsUsername=$username; CredentialHelper=(Protect-Text $helper); Authentication='unverified' }
            }
        }
        $top = Invoke-Native git @('rev-parse','--show-toplevel') -Allowed @(0,128)
        if ($top.Code -eq 0 -and -not $gitDirectory.StartsWith($top.Out.Replace('\','/').TrimEnd('/') + '/', [StringComparison]::OrdinalIgnoreCase)) { $issues.Add('Linked worktree or external Git directory: folder selection follows the Git metadata directory, not the checkout directory.') }
    }
    $gh = @()
    $hosts = if ($expected) { @($expected.Host) } else { @($Configuration.Profiles.Values.Host | Select-Object -Unique) }
    foreach ($hostName in $hosts) {
        $state = Get-GhState $hostName
        $gh += $state
        if (-not $state.Healthy) { $issues.Add("GitHub CLI authentication is not healthy for $hostName. $($state.Error)") }
        if ($state.TokenOverrides.Count) { $issues.Add("GitHub CLI authentication is overridden by environment variables: $($state.TokenOverrides -join ', ').") }
        if ($expected -and $state.Login -ne $expected.User) { $issues.Add("GitHub CLI account differs from profile '$($expected.Id)'; use switch $($expected.Id).") }
    }
    return [pscustomobject]@{ Version=$ScriptVersion; Directory=(Get-Location).ProviderPath; InRepository=$inRepo; ExpectedProfile=$(if ($expected) { $expected.Id } else { $null }); EffectiveProfile=$actual; Policy=$Configuration.Policy; Settings=$settings; PushDestinations=$remotes; GitHubCli=$gh; Issues=@($issues); Healthy=($issues.Count -eq 0) }
}

function Format-StatusLine {
    param([string]$Label, [string]$Value, [int]$Width = 96)
    $Label = Protect-Text $Label
    $Value = Protect-Text $Value
    $prefix = '{0,-12} : ' -f $Label
    $indent = ' ' * $prefix.Length
    $remaining = ($Value -replace '[\r\n\t]+', ' ').Trim()
    if (-not $remaining) { $remaining = '(not set)' }
    $available = [Math]::Max(1, $Width - $prefix.Length)
    while ($remaining.Length -gt $available) {
        $cut = $remaining.LastIndexOf(' ', $available)
        if ($cut -le 0) { $cut = $available }
        $prefix + $remaining.Substring(0, $cut)
        $remaining = $remaining.Substring($cut).TrimStart()
        $prefix = $indent
    }
    $prefix + $remaining
}

function Format-Status {
    param($Status, [int]$Width = 96)
    Format-StatusLine 'Directory' $Status.Directory $Width
    if ($Status.InRepository) {
        $profile = if ($Status.EffectiveProfile) { $Status.EffectiveProfile } else { 'unmanaged / legacy' }
        if ($Status.ExpectedProfile -ne $Status.EffectiveProfile) { $profile += "; expected: $($Status.ExpectedProfile ?? 'none')" }
        Format-StatusLine 'Profile' $profile $Width
        Format-StatusLine 'Author' $Status.Settings.author $Width
        if ($Status.Settings.committer -cne $Status.Settings.author) { Format-StatusLine 'Committer' $Status.Settings.committer $Width }
        $enabled = $Status.Settings.'commit.gpgsign'.Value -in @('true','yes','on','1')
        $signing = if ($enabled) {
            $key = $Status.Settings.'user.signingkey'.Value.Replace('\','/')
            "$($Status.Settings.'gpg.format'.Value) / $($key.Split('/')[-1])"
        } else { 'disabled' }
        Format-StatusLine 'Signing' $signing $Width
        foreach ($remote in $Status.PushDestinations) {
            Format-StatusLine 'Push remote' "$($remote.Remote) -> $($remote.PushUrl)" $Width
            if ($remote.Transport -eq 'https') {
                $user = if ($remote.ConfiguredHttpsUsername) { $remote.ConfiguredHttpsUsername } else { '(not set)' }
                Format-StatusLine 'HTTPS user' "$user (configured; authentication unverified)" $Width
            } else { Format-StatusLine 'Transport' "$($remote.Transport) (authentication unverified)" $Width }
        }
        if (-not $Status.PushDestinations.Count) { Format-StatusLine 'Push remote' 'none' $Width }
    } else { Format-StatusLine 'Profile' 'outside a Git repository' $Width }
    foreach ($account in $Status.GitHubCli) {
        $login = if ($account.Login) { $account.Login } else { '(no active account)' }
        $health = if ($account.Healthy) { 'authenticated' } else { 'not verified' }
        Format-StatusLine 'GitHub CLI' "$login @ $($account.Host) ($health)" $Width
    }
    if ($Status.Issues.Count) {
        ''
        foreach ($issue in $Status.Issues) { Format-StatusLine 'Warning' $issue $Width }
    }
}

function Get-ConsolePresentation([bool]$InPipeline) {
    $width = 96
    try { if ($Host.UI.RawUI.WindowSize.Width -gt 20) { $width = [Math]::Min(96, $Host.UI.RawUI.WindowSize.Width - 1) } } catch { }
    $interactive = -not [Console]::IsOutputRedirected -and $Host.UI.SupportsVirtualTerminal -and -not $InPipeline
    $autoColor = $interactive -and $env:TERM -ne 'dumb' -and $null -eq [Environment]::GetEnvironmentVariable('NO_COLOR') -and $PSStyle.OutputRendering -ne 'PlainText'
    return @{ Width=$width; Rich=(-not $Plain -and ($interactive -or $Color -eq 'Always')); UseColor=($Color -eq 'Always' -or ($Color -eq 'Auto' -and $autoColor)) }
}

function Write-ConsoleLines([string[]]$Lines, [switch]$ToError) {
    # Windows legacy code pages replace these symbols with '?'. Restore the
    # caller's encoding after each UI write, including failures.
    $encoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
        foreach ($line in $Lines) {
            if ($ToError) { [Console]::Error.WriteLine($line) } else { [Console]::WriteLine($line) }
        }
    } finally { [Console]::OutputEncoding = $encoding }
}

function Format-SetupEvent {
    param([string]$Section, [string]$Label, [string]$Value, [string]$Tone='normal', [int]$Width=96, [switch]$Rich, [switch]$UseColor)
    $Section = Protect-Text $Section
    $reset=''; $accent=''; $dim=''; $bold=''
    if ($Rich -and $UseColor) {
        $reset="`e[0m"; $dim="`e[90m"; $bold="`e[1m"
        $accent = switch ($Tone) { 'success' { "`e[32m" } 'warning' { "`e[33m" } 'error' { "`e[31m" } default { "`e[36m" } }
    }
    if ($Section) { ''; if ($Rich) { "  ${accent}${bold}$Section${reset}" } else { $Section } }
    $icon = switch ($Tone) { 'success' { '✓' } 'warning' { '!' } 'error' { '×' } default { '›' } }
    $rowWidth = if ($Rich) { $Width - 4 } else { $Width }
    foreach ($line in @(Format-StatusLine $Label $Value $rowWidth)) {
        if ($Rich) {
            $ink = if ($Tone -eq 'normal') { $dim } else { $accent }
            "  ${accent}$icon${reset} ${ink}$line${reset}"
            $icon=' '
        } else { $line }
    }
}

function Write-SetupEvent {
    param([string]$Section, [string]$Label, [string]$Value, [string]$Tone='normal')
    $lines = @(Format-SetupEvent $Section $Label $Value $Tone -Width $presentation.Width -Rich:$presentation.Rich -UseColor:$presentation.UseColor)
    if ($presentation.Rich -or $Tone -eq 'error') { Write-ConsoleLines $lines -ToError:($Tone -eq 'error') }
    else { $lines }
}

function Format-RichStatus {
    param($Status, [int]$Width = 96, [switch]$UseColor)
    # Style after wrapping: escape sequences must not count towards visible width.
    $reset = ''; $dim = ''; $bold = ''; $cyan = ''; $green = ''; $yellow = ''
    if ($UseColor) {
        $reset="`e[0m"; $dim="`e[90m"; $bold="`e[1m"
        $cyan="`e[36m"; $green="`e[32m"; $yellow="`e[33m"
    }
    ''
    "${cyan}${bold}  ◇ ghprofile${reset}  ${dim}v$(Protect-Text $Status.Version)${reset}"
    $attention = if ($Status.Issues.Count -eq 1) { '1 item needs attention' } else { "$($Status.Issues.Count) items need attention" }
    $health = if ($Status.Healthy) { "${green}✓ Checks passed${reset}" } else { "${yellow}! $attention${reset}" }
    "  $health"
    "${dim}  $('─' * [Math]::Max(1, $Width - 4))${reset}"
    $section = ''
    foreach ($line in @(Format-Status $Status -Width ($Width - 2))) {
        if (-not $line) { continue }
        if ($line -match '^(Directory|Profile|Author|Committer|Signing|Push remote|HTTPS user|Transport|GitHub CLI|Warning)\s+: (.*)$') {
            $label = $Matches[1].Trim(); $value = $Matches[2]
            $nextSection = switch ($label) {
                { $_ -in @('Directory','Profile','Author','Committer','Signing') } { 'IDENTITY'; break }
                { $_ -in @('Push remote','HTTPS user','Transport') } { 'GIT REMOTES'; break }
                'GitHub CLI' { 'GITHUB CLI'; break }
                'Warning' { 'ATTENTION'; break }
            }
            if ($nextSection -ne $section) {
                ''
                $section = $nextSection
                $accent = if ($section -eq 'ATTENTION') { $yellow } else { $cyan }
                "  ${accent}${bold}$section${reset}"
            }
            $icon = switch ($label) {
                'Directory' { '›' }
                'Profile' { '◆' }
                'Author' { '○' }
                'Committer' { '○' }
                'Signing' { '◇' }
                'Push remote' { '↗' }
                'HTTPS user' { '○' }
                'Transport' { '↔' }
                'GitHub CLI' { '○' }
                'Warning' { '!' }
            }
            $accent = if ($label -eq 'Warning') { $yellow } elseif ($label -eq 'Profile') { $cyan } elseif ($label -eq 'GitHub CLI' -and $value -match '\(authenticated\)$') { $green } else { '' }
            # Keep the same 15-column prefix as the plain formatter, plus 2 margins.
            $labelText = '{0,-12}' -f $label
            "  ${accent}$icon${reset} ${dim}${labelText}${reset} ${accent}${value}${reset}"
        } else {
            $accent = if ($section -eq 'ATTENTION') { $yellow } else { '' }
            "  ${accent}$line${reset}"
        }
    }
    ''
}

$presentation = Get-ConsolePresentation ($MyInvocation.PipelinePosition -ne $MyInvocation.PipelineLength)
try {
    if ($Command -notin @('setup','status','doctor','switch','init-key')) { throw 'Usage: ghprofile.ps1 setup|status|doctor|switch <profile>|init-key <profile>|--version [-ConfigPath path] [-Json] [-NonInteractive] [-WhatIf]' }
    if ($Name -and $Command -notin @('switch','init-key')) { throw 'A profile argument is only valid for switch and init-key.' }
    if ($Json -and $Command -notin @('status','doctor')) { throw '-Json is supported by status and doctor.' }
    Assert-Prerequisites
    if ($Command -eq 'setup') { Write-SetupEvent "ghprofile setup  v$ScriptVersion" 'Starting' 'Reading profile definitions and checking dependencies.' }
    $configuration = Read-Profiles
    $gitVersion = (Invoke-Native git @('--version')).Out
    if ($gitVersion -notmatch '(\d+)\.(\d+)\.(\d+)' -or [version]$Matches[0] -lt [version]'2.34.0') { throw 'Git 2.34 or newer is required.' }
    if ($Command -in @('switch','init-key')) {
        if (-not $Name -or -not $configuration.Profiles.Contains($Name)) { throw "Specify a known profile: $($configuration.Profiles.Keys -join ', ')" }
        $profile = $configuration.Profiles[$Name]
    }
    switch ($Command) {
        setup { Install-Profiles $configuration }
        init-key { New-ProfileKey $profile }
        switch {
            if (@(Get-TokenOverrides $profile.Host).Count) { throw 'An environment token overrides stored gh accounts. Unset the applicable token variable before switching.' }
            if ($PSCmdlet.ShouldProcess("$($profile.User)@$($profile.Host)", 'Change the shared GitHub CLI active account')) {
                [void](Invoke-Native gh @('auth','switch','--hostname',$profile.Host,'--user',$profile.User))
                $state = Get-GhState $profile.Host
                if (-not $state.Healthy -or $state.Login -ne $profile.User) { throw "Switch completed but account verification failed. $($state.Error)" }
                Write-Output (Protect-Text "GitHub CLI active account: $($state.Login)@$($profile.Host). This selection is shared across terminals.")
            }
        }
        default {
            $result = Get-Status $configuration -Doctor:($Command -eq 'doctor')
            if ($Json) { $result | ConvertTo-Json -Depth 12 }
            else {
                $width = $presentation.Width
                if ($presentation.Rich) {
                    # Terminal UI bypasses PowerShell's host formatter, which strips
                    # ANSI under TERM=dumb even after OutputRendering is changed.
                    # Plain/JSON remain ordinary pipeline output for automation.
                    Write-ConsoleLines @(Format-RichStatus $result -Width $width -UseColor:$presentation.UseColor)
                } else { Format-Status $result -Width $width }
                foreach ($entry in $result.Settings.GetEnumerator()) {
                    if ($entry.Value -isnot [string]) { Write-Verbose (Protect-Text "$($entry.Key): $($entry.Value.Value); origin: $($entry.Value.Origin)") }
                }
                foreach ($remote in $result.PushDestinations) { Write-Verbose (Protect-Text "Credential helper for $($remote.Remote): $($remote.CredentialHelper)") }
            }
            if ($Command -eq 'doctor' -and -not $result.Healthy) { exit 2 }
        }
    }
    exit 0
} catch {
    $message = Protect-Text $_.Exception.Message
    if ($Json) { @{ Version=$ScriptVersion; Error=$message } | ConvertTo-Json -Compress }
    elseif ($Command -eq 'setup') { Write-SetupEvent 'SETUP FAILED' 'Error' $message 'error' }
    else { [Console]::Error.WriteLine("ghprofile: $message") }
    exit 1
}
