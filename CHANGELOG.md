# Changelog

## [0.3.1] - 2026-09-30

- Display native stdout/stderr prompts while interactive processes wait; capture public-key derivation stdout separately.
- Terminate owned native children on pipeline cancellation before releasing key locks.
- Escape terminal controls and directional overrides in external values before styling, including verbose, setup, error and streamed native output; preserve credential redaction across stream boundaries.
- Refuse control characters in interactive native arguments because OpenSSH can write directly to the console.
- Add deterministic prompt, cancellation, control-injection and streaming-redaction regression checks. Actual Windows terminal checks remain pending and will be performed separately; the patch version identifies the implemented fixes without claiming that manual verification is complete.

## [0.3.0] - 2026-09-30

- Extend rich console presentation to setup: profile plans, signing-key checks, configuration progress, activation results, backups and next steps.
- Add styled no-write previews and red stderr failures without displaying a premature success state.
- Share terminal capability/color detection with status; preserve plain output and ShouldProcess semantics.
- Emit rich console text in UTF-8, restoring the caller's encoding after each write to prevent legacy Windows code pages from replacing symbols with question marks.
- Add setup rendering and entrypoint tests, including narrow-width wrapping, previews, failures and activation.

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
