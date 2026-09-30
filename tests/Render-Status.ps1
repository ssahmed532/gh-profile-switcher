#requires -Version 7.2
param([switch]$Preview)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$source = Join-Path (Split-Path $PSScriptRoot) 'ghprofile.ps1'
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($source,[ref]$null,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($fn in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and ($n.Name -like 'Format-*' -or $n.Name -eq 'Protect-Text')},$false)) {
    . ([scriptblock]::Create($fn.Extent.Text))
}
$fixture = [pscustomobject]@{
    Version='0.3.1'; Directory='C:/personal/gh-profile-switcher'; InRepository=$true
    EffectiveProfile='personal'; ExpectedProfile='personal'; Healthy=$true
    Settings=@{
        author='Personal Example <personal@example.com>'; committer='Personal Example <personal@example.com>'
        'commit.gpgsign'=@{Value='true'}; 'gpg.format'=@{Value='ssh'}
        'user.signingkey'=@{Value='C:/Users/example/.ssh/personal-signing.pub'}
    }
    PushDestinations=@([pscustomobject]@{Remote='origin';PushUrl='https://github.com/example/gh-profile-switcher.git';Transport='https';ConfiguredHttpsUsername='personal-user'})
    GitHubCli=@([pscustomobject]@{Login='personal-user';Host='github.com';Healthy=$true})
    Issues=@()
}
$checks=0
function Assert([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:checks++
    if (-not $Preview) { Write-Output "PASS: $Message" }
}
function Strip([string]$Line) { $Line -replace '\x1b\[[0-9;]*m','' }
$rich=@(Format-RichStatus $fixture -Width 80 -UseColor)
Assert (($rich -join "`n") -match '\x1b\[') 'Rich output contains ANSI styling'
Assert (($rich -join "`n") -match '✓ Checks passed' -and ($rich -join "`n") -match 'IDENTITY' -and ($rich -join "`n") -match 'GIT REMOTES') 'Header and sections explain status'
Assert (($rich -join "`n") -match 'authentication unverified') 'Styling preserves credential uncertainty'
$mono=@(Format-RichStatus $fixture -Width 80)
Assert (($mono -join "`n") -notmatch '\x1b') 'Rich monochrome mode contains no escape sequences'
Assert ((($rich | ForEach-Object { Strip $_ }) -join "`n") -ceq ($mono -join "`n")) 'Color does not alter layout or information'
$fixture.Healthy=$false; $fixture.EffectiveProfile=''
$fixture.Issues=@('Managed profile marker is missing (legacy or unapplied setup). Run ghprofile.ps1 setup to migrate configuration.', 'A long explanation: keep this text together even if the colon lands on a wrapped continuation line.')
foreach ($width in @(40,60,80,96)) {
    $lines=@(Format-RichStatus $fixture -Width $width -UseColor)
    Assert (@($lines | Where-Object { (Strip $_).Length -gt $width }).Count -eq 0) "Visible output fits $width columns"
    Assert (($lines -join "`n") -match 'ATTENTION' -and ($lines -join "`n") -match '2 items need attention') "Warnings remain visible at $width columns"
}
$plain=@(Format-Status $fixture -Width 80)
Assert (($plain -join "`n") -notmatch '\x1b|◇|◆|✓|↗') 'Plain output preserves ASCII-friendly labels'
$fixture.InRepository=$false; $fixture.Settings=@{}; $fixture.PushDestinations=@()
Assert (((Format-RichStatus $fixture -Width 80) -join "`n") -match 'outside a Git repository') 'Outside-repository view renders'
foreach ($width in @(40,60,96)) {
    $setupLines=@(Format-SetupEvent 'COMPLETE' 'Backup' ('C:/long-backup-path/' * 8) 'success' -Width $width -Rich -UseColor)
    Assert (@($setupLines | Where-Object { (Strip $_).Length -gt $width }).Count -eq 0) "Setup paths wrap to $width columns"
}
$setupError=(Format-SetupEvent 'SETUP FAILED' 'Error' 'Key validation failed.' 'error' -Rich -UseColor) -join "`n"
Assert ($setupError -match '\x1b\[31m' -and $setupError -notmatch 'COMPLETE') 'Setup errors are red and never claim completion'
$setupPlain=(Format-SetupEvent 'PREVIEW' 'No changes' 'Validation will run when applying setup.' 'warning') -join "`n"
Assert ($setupPlain -notmatch '\x1b' -and $setupPlain -match 'No changes') 'Plain setup preview has no ANSI escapes'
if (-not $Preview) {
    $attack = "name`e[0m`e[2J`e[H`e]8;;https://example.invalid`aLINK`e]8;;`e\" + [char]0x9b + '2J' + [char]0x202e + "`r`b`0"
    $fixture.InRepository=$true
    $fixture.Version=$attack; $fixture.Directory=$attack; $fixture.EffectiveProfile=$attack
    $fixture.Settings=@{author=$attack;committer=$attack;'commit.gpgsign'=@{Value='true'};'user.signingkey'=@{Value=$attack};'gpg.format'=@{Value=$attack}}
    $fixture.PushDestinations=@([pscustomobject]@{Remote=$attack;PushUrl=$attack;Transport='https';ConfiguredHttpsUsername=$attack})
    $fixture.GitHubCli=@([pscustomobject]@{Login=$attack;Host=$attack;Healthy=$true})
    $fixture.Issues=@($attack)
    foreach ($mode in @('plain','rich','color')) {
        $lines = if ($mode -eq 'plain') { @(Format-Status $fixture) } else { @(Format-RichStatus $fixture -UseColor:($mode -eq 'color')) }
        $clean = ($lines | ForEach-Object { Strip $_ }) -join ''
        Assert ($clean -notmatch '[\p{Cc}\u202e]') "$mode neutralizes controls across all status fields"
        Assert ($clean -match '\\u001B') "$mode visibly escapes injected terminal sequences"
    }
    $safeSetup = (Format-SetupEvent $attack $attack $attack -Rich -UseColor | ForEach-Object { Strip $_ }) -join ''
    Assert ($safeSetup -notmatch '[\p{Cc}\u202e]') 'Setup sanitizes section, label and value before styling'
    Assert ((Protect-Text "日本語 café é 👩‍💻") -ceq "日本語 café é 👩‍💻") 'Ordinary Unicode, combining characters and emoji remain intact'
    Assert ((Protect-Text ($attack + ' https://user:secret@example.invalid ghp_fixturesecret')) -notmatch 'user:secret|ghp_fixturesecret') 'Control escaping preserves credential redaction'
}
if ($Preview) {
    $rich | ForEach-Object { [Console]::WriteLine($_) }
    $fixture.InRepository=$true
    $fixture.Settings=@{author='Personal Example <personal@example.com>';committer='Personal Example <personal@example.com>'; 'commit.gpgsign'=@{Value='false'}}
    Format-RichStatus $fixture -Width 80 -UseColor | ForEach-Object { [Console]::WriteLine($_) }
} else { Write-Output "$checks rendering checks passed." }
