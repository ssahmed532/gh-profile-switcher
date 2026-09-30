# Changelog

## [0.2.0] - 2026-09-30

- Add a rich interactive status/doctor display with colored headings, authentication states, Unicode symbols and grouped identity, remote, CLI and warning sections.
- Add `-Plain` and `-Color Auto|Always|Never`; automatically use plain output when redirected or piped, and honor NO_COLOR, TERM=dumb and PowerShell's PlainText rendering preference in automatic color mode.
- Preserve JSON output, diagnostics, wrapped values and verbose configuration origins.
- Add focused rendering tests at 40, 60, 80 and 96 columns and a synthetic preview command.

## [0.1.1] - 2026-09-30

- Replace JSON fragments in default status/doctor output with aligned, width-aware console summaries and wrapped warnings.
- Hide repeated committer identity and full configuration paths by default; expose origins and credential helpers through `-Verbose`, preserving the `-Json` schema.
- Explain missing managed markers and matching legacy public-key paths as unapplied migration instead of falsely claiming the identity differs.

## [0.1.0] - 2026-09-30

First semantic-versioned release (v0.1). Earlier documentation revision numbers were not script release versions.

- Add version-only `--version` / `-Version`, with no configuration or dependency access.
- Check native exit codes and isolate stdout from returned paths and generated configuration.
- Validate complete profile data and signing keys before setup activation.
- Stage immutable configurations, preserve owned-file history, lock global updates, back up and atomically activate one ordered include.
- Reconcile changed/removed profiles and migrate recognized legacy includes without deleting unrelated settings.
- Add strict unmatched-repository policy, multiple roots, enterprise hosts and explicit file/agent/disabled signing modes.
- Separate interactive key creation from setup; reject incomplete, mismatched or unavailable keys without overwriting them.
- Configure SSH signing and local verification explicitly while retaining historical trust entries.
- Add diagnostic `doctor`, JSON output, config-path selection, noninteractive validation and mutation previews.
- Detect identity overrides, signing mismatches, unhealthy CLI authentication, token overrides and worktree metadata rules.
- Report actual push destinations and credential configuration without claiming a verified push account.
- Add isolated regression coverage and update setup, migration and recovery documentation.

The documented CLI, JSON fields, exit codes and configuration schema form the versioned interface. During 0.x, compatible fixes increment PATCH; features and breaking changes increment MINOR. From 1.0.0, breaking changes increment MAJOR. The configuration schema version is independent of the script version.
