# GH profile switcher implementation roadmap

Last updated: 2026-09-30. Baseline: v0.3.0. This is an implementation plan, not a record of shipped functionality.

## Session entry point

1. Read this file, `CLAUDE.md`, `README.md`, and applicable agent instructions. Inspect `git status` and the current script version; preserve unrelated changes.
2. Start with the earliest unfinished phase unless the user selects another task. Implement a coherent task with its regression coverage before moving on. Do not start later phases to avoid a blocked task; record the dependency and continue independent work in the same phase.
3. Inspect the referenced functions and existing tests before editing. Findings below come from code review; reproduce suspected defects before treating them as confirmed. Record evidence or explain why the proposed fix is unnecessary.
4. Use the acceptance criteria as the completion contract. Make routine implementation decisions autonomously; record consequential interface decisions here. Ask only when missing information materially blocks safe implementation.
5. Update checkboxes and the handoff section after each work session. Record files changed, actual verification results, outstanding risks, and the exact next task. Never mark a task complete solely because code was written.
6. Completing a phase means implementing and verifying its scope, updating documentation and version references, and recording results. Publishing is a separate step: commit, push, tag, or create a release only when authorized by the current user instruction. This document is not standing permission to publish or modify the user's machine configuration.

## Baseline and invariants

- Current commands: `setup`, `status`, `doctor`, `switch <profile>`, `init-key <profile>`, and version-only `--version` / `-Version`.
- Current implementation: one PowerShell 7.2+ script, validated profile definitions, immutable managed generations, locked atomic global-config activation, backups, and rich/plain/JSON diagnostic output.
- Windows is the verified platform. Existing verification entry points are `tests/Run-Tests.ps1` and `tests/Render-Status.ps1`. The v0.3.0 release recorded 99 integration checks and 20 rendering checks; future runs must report their actual counts.
- Keep version-only output independent of configuration, Git, gh, network access, and console decoration.
- Preserve unrelated Git settings, external signer files, existing private keys, user edits, and historical signing trust.
- Git identity, commit signing, GitHub CLI identity, and push authentication are distinct. Never infer verified push identity or write permission from a configured username, an authenticated CLI account, or successful read access.
- `switch` changes shared GitHub CLI state across terminals; folder-based Git identity does not imply per-terminal gh isolation.
- Never run real `setup`, `switch`, key creation, rollback, uninstall, or cleanup as a side effect of development. Use disposable fixtures and isolated `GIT_CONFIG_GLOBAL`, `GH_CONFIG_DIR`, repositories, keys, and environment variables.
- `profiles.json` contains private configuration. Do not expose its values in documentation, tests, logs, commits, or responses. Use synthetic identities and paths.
- Keep machine-readable output free of progress text and ANSI codes. Preserve existing behavior unless a documented phase intentionally changes the interface.

## Release policy

Planned versions below are targets. Reconcile them with the actual branch version before starting; never overwrite an existing tag. Patch releases contain compatible fixes; new commands and intentional interface changes belong in minor releases during 0.x. Configuration schema versioning remains independent of script versioning.

`$ScriptVersion` is the source of truth. Update README, HOWTO, CHANGELOG, repository guidance version references, and version assertions together when releasing a phase. A roadmap-only edit does not bump the executable version. Follow repository instructions for the published guide; if its editor is unavailable, record that limitation and keep the local guide authoritative rather than claiming publication succeeded.

| Phase | Target | Outcome | Dependencies |
| --- | --- | --- | --- |
| 1 | v0.3.1 | Reliable interactive prompts and safe terminal text | v0.3.0 |
| 2 | v0.4.0 | Accurate, actionable, responsive diagnostics | Phase 1 |
| 3 | v0.5.0 | Safe recovery and generation lifecycle management | Phase 2 diagnostics |
| 4 | v0.6.0 | Reusable onboarding and consistent command UX | Phase 2 rendering/data model |
| 5 | v0.7.0 | Opt-in authentication investigation | Phase 2 findings and time budgets |
| 6 | v0.8.0 | Automated compatibility and release validation | Incrementally throughout earlier phases |

## Phase 1 — v0.3.1: correctness and terminal safety

- [ ] **P1.1 Reproduce and fix interactive native execution.** Inspect `Invoke-Native`, `Test-SigningKey`, and `New-ProfileKey`. Interactive execution currently captures stdout/stderr and waits for completion; prompts written to those streams can be hidden. Determine actual Windows OpenSSH behavior with disposable encrypted keys before choosing a fix. Separate captured machine-readable execution from interactive prompting without mixing prompt text into returned public-key data.
  - Acceptance: key creation and encrypted-key validation expose prompts while waiting; passphrases are never logged or passed on a command line; noninteractive validation fails promptly without prompting; cancellation returns control and releases owned locks; native failures preserve configuration and existing keys.
  - Verification: deterministic child-process prompt/cancellation tests plus a documented manual Windows terminal check using disposable keys. If interactive automation cannot establish visibility, retain the manual check as explicitly pending.
- [ ] **P1.2 Sanitize untrusted terminal values.** Inspect `Protect-Text`, all formatters, native errors, verbose output, and setup events. Remove or visibly escape terminal control sequences from external values before applying trusted styling. Cover escape/CSI/OSC sequences and other display-manipulating controls without damaging ordinary Unicode.
  - Acceptance: malicious profile text, Git identity, remote URLs, paths, and native error text cannot inject color resets, screen clearing, cursor movement, or terminal hyperlinks. Existing secret redaction still applies. Intentional layout and application-generated styling remain functional.
  - Verification: synthetic control-sequence fixtures across rich, plain, verbose, and error paths; JSON remains valid data and contains no application-generated styling. Do not execute injected control sequences in a real terminal during tests.
- [ ] **P1.3 Complete patch release verification and documentation.** Keep interface changes out of this patch. Record any unreproduced hypothesis accurately.

## Phase 2 — v0.4.0: trustworthy diagnostics and responsive status

- [ ] **P2.1 Introduce structured findings.** Replace the single undifferentiated issue list internally with findings containing stable code, severity, category, message, evidence, and suggested action. Categories should distinguish identity, signing, CLI authentication, push authentication, configuration, and repository layout. Define severity and exit-code behavior before implementation; ordinary SSH use and linked worktrees are informational unless a concrete fault is found. Represent unknown/not-checked separately from failed checks.
  - Acceptance: valid SSH remotes and linked worktrees alone do not fail `doctor`; actual identity/signing errors still do. Document precisely which severities cause exit 2, retaining exit 1 for command/execution errors and exit 0 for successful status collection. Document JSON compatibility or migration for `Issues` and `Healthy`; prefer additive fields where practical.
- [ ] **P2.2 Render directly from structured data.** Refactor `Format-RichStatus`, which currently parses plain formatter strings. Share semantic rows/sections and findings, not parsed presentation text, between rich and plain renderers.
  - Acceptance: changing a label cannot break section grouping, icon selection, or severity styling. Rich/plain/JSON describe the same results. Preserve wrapping and output-mode controls.
- [ ] **P2.3 Validate effective signing trust.** Extend `Get-Status` / doctor beyond expected-key validation. Inspect effective signer-file path, accessibility, matching principal/key, relevant overrides, and unsupported trust constructs. Distinguish local trust from GitHub registration. Unsupported syntax must yield an honest unknown result, not a false failure or success.
  - Acceptance: missing/unreadable signer files, wrong principal/key, and conflicting effective signing settings produce specific findings. Retained historical trust remains valid. An optional signing smoke test uses a disposable repository with relevant effective settings, never creating commits or changing configuration in the user's repository; document signing-agent/passphrase interaction.
- [ ] **P2.4 Explain configuration drift.** Use managed markers, manifests, definitions, effective values, and Git origins to distinguish legacy/unapplied setup, changed definitions, missing managed files, and local/environment overrides. If a normalized definition fingerprint is added to manifests, treat older manifests as supported legacy metadata and never embed secrets.
  - Acceptance: diagnostics include expected/actual values and relevant origin with redaction, plus a targeted remedy. Do not recommend rerunning setup as a cure for a higher-precedence local/environment override. Cover changed roots, identity, signing mode, removed profiles, and missing generations.
- [ ] **P2.5 Reduce status latency.** Measure current subprocess counts and timings using fixtures with multiple remotes/hosts. Batch compatible configuration reads while preserving Git precedence, multivalues, includes, and origins. Add an explicit offline mode and an overall configurable deadline; retain per-process limits. Avoid persistent authentication caching unless invalidation and freshness are designed and documented.
  - Acceptance: offline status starts no network-capable authentication probe and reports those checks as not checked. Slow/failing gh cannot exceed the documented overall budget except for a small documented shutdown allowance. Partial results survive timeout. Use deterministic delayed stubs to test deadlines and record before/after process counts and timing evidence without brittle wall-clock performance assertions.
- [ ] **P2.6 Finish minor-release migration notes and regression coverage.** Explain severity, exit codes, JSON changes, offline behavior, and any new flags.

## Phase 3 — v0.5.0: recovery and managed-file lifecycle

- [ ] **P3.1 Add generation/backup inventory.** Identify active, historical, incomplete, and externally referenced generations using ownership metadata and include references. Display provenance and timestamps; filenames alone must not establish ownership.
- [ ] **P3.2 Add previewable rollback.** Select an explicit known generation or backup, validate it, acquire the configuration lock, back up current state, and activate atomically. Detect edits since the relevant baseline. Refuse ambiguous restoration; do not silently overwrite unrelated settings to restore a whole historical file.
- [ ] **P3.3 Add previewable uninstall.** Remove only owned integration. Preserve unrelated includes and settings, keys, external signer files, and recovery data. Explain the resulting unmanaged identity/signing state in the preview. Do not guess which overwritten legacy values the user wants restored.
- [ ] **P3.4 Add previewable cleanup.** Inventory candidates before deletion and define retention policy. Protect active generations, retained-backup references, and uncertain/external references. Handle unused generations left by failed setup. Validate every resolved deletion target remains inside the owned managed directory; do not follow links/reparse points into other locations.
  - Shared acceptance: `-WhatIf` performs no writes; concurrent operations respect locking; stale/missing metadata yields actionable refusal; repeated operations are safe; failures leave a usable configuration; unrelated user edits survive. Test injected failures, lock contention, changed global config, malformed metadata, retained references, and paths outside ownership boundaries.
- [ ] **P3.5 Document recovery recipes and publish the verified command contract.** Keep the manual backup recovery path available if the tool itself cannot run.

## Phase 4 — v0.6.0: onboarding, reuse, and presentation consistency

- [ ] **P4.1 Add complete command help.** Include parameter applicability, examples, exit codes, profile-selection rules, and shared gh-state semantics. Help and version must work without valid profiles or external dependencies. Choose and document PowerShell-native and any supported GNU-style argument forms consistently.
- [ ] **P4.2 Add a profile JSON Schema and configuration-only validation.** Describe required fields, supported policy/signing modes, root/roots exclusivity, and schema version. Keep runtime validation authoritative for filesystem/overlap/semantic checks. Validation must not authenticate, generate keys, mutate Git settings, or require Git when checking only JSON definitions.
- [ ] **P4.3 Make switching scope explicit.** Command help and successful switch output explain that gh state is shared, folder identity remains determined by Git configuration, and push credentials are a separate mechanism. Do not silently switch accounts on directory changes.
- [ ] **P4.4 Reuse rendering for switch and init-key.** Apply shared rich/plain/color behavior to plans, completion, and failures. Preserve usable interactive prompts and never report success before verification.
- [ ] **P4.5 Improve terminal compatibility.** Handle very narrow windows, display-cell width for wide Unicode/combining characters, and an explicit ASCII fallback if needed. Retain `NO_COLOR`, `TERM=dumb`, redirection, pipeline, and encoding-restoration behavior. Add tests for narrow/wide terminals, non-ASCII paths, and capture without console leakage.
- [ ] **P4.6 Document installation/configuration discovery.** Explain invocation from another directory, `-ConfigPath`, upgrade behavior, and shell usage. Avoid unnecessary dependencies or a packaging framework without demonstrated need.

## Phase 5 — v0.7.0: optional authentication investigation

- [ ] **P5.1 Inspect SSH configuration locally.** Explain effective host aliases, user, identity selection, and relevant overrides without contacting hosts or displaying private material. Distinguish signing keys from transport keys. Treat arbitrary SSH configuration commands and helpers as potentially executable; do not run them implicitly in ordinary status.
- [ ] **P5.2 Explain HTTPS credential selection.** Account for helper chains, reset entries, URL matching, path-sensitive credentials, environment overrides, and embedded-credential redaction. Do not call credential retrieval merely to display configuration or expose returned secrets.
- [ ] **P5.3 Add explicitly requested online probes.** Define exact capabilities and timeout behavior before implementing. Report the identity actually established by a supported probe and the remaining uncertainty. Read access does not prove push permission; gh API authentication does not establish Git transport identity. Never push, alter remotes, accept unknown host keys automatically, or modify credentials as a verification shortcut.
  - Acceptance: normal/offline status does not run opt-in probes; probes are bounded and redact secrets; unsupported transports/helpers produce unknown results; enterprise hosts and aliases have fixtures. Prefer mocks for automated network tests and document any optional live checks.
- [ ] **P5.4 Update documentation and diagnostic output examples with explicit evidence levels.**

## Phase 6 — v0.8.0: CI and release discipline

This work can begin earlier as infrastructure for preceding phases; reserve the release milestone for the completed compatibility contract.

- [ ] **P6.1 Add CI for isolated integration and rendering tests.** Begin with Windows and the supported PowerShell floor plus a current supported version. Ensure fixtures cannot use runner credentials or real user configuration; avoid secrets in ordinary PR tests.
- [ ] **P6.2 Add static and contract checks.** Parse PowerShell, check whitespace, validate example configuration/schema, exercise version-only output in a missing-config environment, and verify documentation/version consistency. Add targeted static analysis with justified exceptions rather than unrelated style churn.
- [ ] **P6.3 Establish platform support through tests.** Add Linux/macOS jobs and path/case/symlink/SSH coverage before claiming support. Keep failures visible and document unsupported behaviors; do not silently downgrade required checks.
- [ ] **P6.4 Automate release validation.** Verify SemVer, matching script/docs/tests version, changelog entry, clean intended release state, and matching annotated tag/commit. Never move an existing published tag. Publishing remains an explicitly authorized action.
- [ ] **P6.5 Produce a release checklist and support matrix.** Record required checks, manual terminal checks, dependencies, supported platform versions, and remaining known limitations. Dependency-free runtime remains preferred.

## Verification and definition of done

Run focused checks while developing, then the existing suites when implementation is ready:

```powershell
pwsh -NoProfile -File tests/Render-Status.ps1
pwsh -NoProfile -File tests/Run-Tests.ps1
pwsh -NoProfile -File ghprofile.ps1 --version
git diff --check
```

- Extend existing tests for observable behavior, regressions, and failure boundaries. Avoid tests that only mirror implementation structure.
- Use temporary configurations, repositories, keys, helper stubs, and gh state. Native-call failures, timeouts, cancellation, lock handling, and no-write previews need appropriate coverage.
- Do not rerun broad suites without a new change or unresolved concern. If a sandbox blocks a required test, use the established approval mechanism; never bypass it or report blocked tests as passing.
- Review rich/plain/JSON output, exit codes, redaction, and documentation for every affected command. Interactive behavior needs terminal evidence in addition to captured-output tests.
- Record actual test outcomes and limitations. No executable version bump for unfinished functionality; a completed release phase must synchronize version references and documentation before publication.

## Session handoff

- **State:** Roadmap recorded; implementation of these phases has not started.
- **Baseline:** v0.3.0. No behavior changes in this planning task.
- **Next task:** P1.1 — reproduce prompt visibility and cancellation behavior with disposable encrypted keys; inspect `Invoke-Native`, `Test-SigningKey`, and `New-ProfileKey`.
- **Known uncertainty:** Hidden interactive prompts are a code-review hypothesis, not a reproduced defect. Confirm before modifying the execution path.
- **Verification for this document:** Documentation review only; implementation tests are not required for the roadmap itself.
- **Future session log format:** Date; task IDs; changes; verification command/result; decisions; blockers or limitations; exact next step. Append concise entries below and keep the current state above accurate.
