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

- [x] **P1.1 Reproduce and fix interactive native execution.** Inspect `Invoke-Native`, `Test-SigningKey`, and `New-ProfileKey`. Interactive execution currently captures stdout/stderr and waits for completion; prompts written to those streams can be hidden. Determine actual Windows OpenSSH behavior with disposable encrypted keys before choosing a fix. Separate captured machine-readable execution from interactive prompting without mixing prompt text into returned public-key data.
  - Acceptance: key creation and encrypted-key validation expose prompts while waiting; passphrases are never logged or passed on a command line; noninteractive validation fails promptly without prompting; cancellation returns control and releases owned locks; native failures preserve configuration and existing keys.
  - Verification: deterministic child-process prompt/cancellation tests plus a documented manual Windows terminal check using disposable keys. If interactive automation cannot establish visibility, retain the manual check as explicitly pending.
  - 2026-09-30 progress: stream-prompt defect reproduced against baseline `db1911f`; live stream draining, separate public-key capture, child termination and owned-key-lock cancellation tests implemented. User-supplied v0.3.2 manual report now passes all 24 checks, including real console prompt visibility, hidden input and Ctrl+C cleanup; see the manual-evidence session entry below.
- [x] **P1.2 Sanitize untrusted terminal values.** Inspect `Protect-Text`, all formatters, native errors, verbose output, and setup events. Remove or visibly escape terminal control sequences from external values before applying trusted styling. Cover escape/CSI/OSC sequences and other display-manipulating controls without damaging ordinary Unicode.
  - Acceptance: malicious profile text, Git identity, remote URLs, paths, and native error text cannot inject color resets, screen clearing, cursor movement, or terminal hyperlinks. Existing secret redaction still applies. Intentional layout and application-generated styling remain functional.
  - Verification: synthetic control-sequence fixtures across rich, plain, verbose, and error paths; JSON remains valid data and contains no application-generated styling. Do not execute injected control sequences in a real terminal during tests.
- [x] **P1.3 Complete patch release verification and documentation.** Keep interface changes out of this patch. Record any unreproduced hypothesis accurately.

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
pwsh -NoProfile -File tests/Native-Execution.ps1
pwsh -NoProfile -File tests/Run-Tests.ps1
pwsh -NoProfile -File ghprofile.ps1 --version
git diff --check
```

- Extend existing tests for observable behavior, regressions, and failure boundaries. Avoid tests that only mirror implementation structure.
- Use temporary configurations, repositories, keys, helper stubs, and gh state. Native-call failures, timeouts, cancellation, lock handling, and no-write previews need appropriate coverage.
- Do not rerun broad suites without a new change or unresolved concern. If a sandbox blocks a required test, use the established approval mechanism; never bypass it or report blocked tests as passing.
- Review rich/plain/JSON output, exit codes, redaction, and documentation for every affected command. Interactive behavior needs terminal evidence in addition to captured-output tests.
- Record actual test outcomes and limitations. By explicit user direction on 2026-09-30, version the implemented Phase 1 fixes as v0.3.1 while manual Windows verification is deferred. Keep outstanding acceptance checks open; a version bump does not establish phase completion. Synchronize version references and documentation together.

## Session handoff

- **State:** Current version is v0.3.2 with early Git/gh prerequisite checks; Phase 1 fixes were introduced in v0.3.1; P1.1, P1.2 and P1.3 are complete based on the automated checks and assessed user-supplied manual report. Version references and documentation are synchronized.
- **Current version:** v0.3.2 for the requested prerequisite checks, following repository patch-version policy. Manual Phase 1 verification passed on the reported Windows environment. Original roadmap baseline: v0.3.0.
- **Next task:** On the next roadmap implementation request, start P2.1 (structured findings); Phase 1 acceptance is complete. The user authorized committing all current changes, pushing main to origin and applying the v0.3.2 release tag in this session.
- **Known uncertainty:** A deterministic child reproduces hidden stream-written prompts in baseline commit `db1911f`. Windows OpenSSH's encrypted-key probe waited for input with empty captured stdout/stderr; this does not prove that its direct console prompt was invisible. The user has now verified current-version console visibility, hidden input and Ctrl+C behavior. This does not retrospectively establish baseline OpenSSH console behavior. Terminal version was supplied only as Windows Terminal 1.x; the exact build is not recorded.
- **Verification:** v0.3.2 passed 14 prerequisite, 113 integration, 29 rendering and 20 native-execution checks on PowerShell 7.6.6, Git 2.56.0.windows.1, GitHub CLI 2.102.0 and Windows OpenSSH file version 9.5.6.2. Version-only output and `git diff --check` passed. The manual-runner helper suite also passed 13 checks. The user supplied a Complete report with all 24 manual checks passing. PowerShell 7.2 compatibility remains untested; the exact Windows Terminal build was not supplied.
- **Publication scope:** User now authorizes committing all current changes, pushing main to origin and applying an annotated v0.3.2 release tag. Phase 1 completion is established by the recorded automated/manual evidence. A hosted GitHub Release and external guide publication are not part of this tag operation; the local guide remains authoritative.
- **Future session log format:** Date; task IDs; changes; verification command/result; decisions; blockers or limitations; exact next step. Append concise entries below and keep the current state above accurate.

### 2026-09-30 — P1.1/P1.2 implementation; P1.3 preparation

- Changed `ghprofile.ps1`: asynchronously drain interactive streams while waiting; use explicit stdout capture for key derivation; kill the owned process tree in `finally` before callers release locks. Noninteractive execution retains its 30-second limit and empty-passphrase validation. No new CLI flags or commands.
- Terminal protection visibly escapes C0/C1 controls, directional controls and Unicode line separators before trusted styling. Applied to status rows, setup headings/values, verbose details, native errors, success messages and ShouldProcess paths. Streaming output retains ordinary line breaks and buffers incomplete credential patterns for redaction. Interactive arguments with terminal controls are refused because direct OpenSSH console writes cannot be sanitized after emission. JSON retains raw identity fields as data; downstream consumers must sanitize their own displays.
- Added `tests/Native-Execution.ps1`; extended `tests/Render-Status.ps1` and `tests/Run-Tests.ps1`. Native tests check prompts before releasing child-process handshakes, separate captured key data, failure propagation, pipeline cancellation/lock release, argument protection and every split point of a credential/control/Unicode/CRLF fixture.
- Evidence: `tests/Native-Execution.ps1 -Source <temporary HEAD script>` fails at the first live stderr-prompt assertion, while the working-tree version passes. The disposable Windows OpenSSH encrypted-key probe waited past three seconds with empty captured streams and was terminated. Automated integration verifies encrypted `-NonInteractive` failure without activation, preserved existing keys/configuration, and released owned configuration locks after injected failures.
- Verification: `pwsh -NoProfile -File tests/Run-Tests.ps1` passed 113 checks after an approved outside-sandbox run (sandbox denied atomic replacement of temporary config). The first outside-sandbox attempt caught an overly strict JSON test that treated raw directional characters in data as terminal presentation; corrected the test and reran successfully. `tests/Render-Status.ps1` passed 29 checks; `tests/Native-Execution.ps1` passed 20 checks. Both focused suites were rerun after the final native newline-preservation adjustment. `ghprofile.ps1 --version` printed only v0.3.0; `git diff --check` passed.
- Updated README, local HOWTO and CHANGELOG with unreleased behavior and an isolated manual terminal checklist. Preserved the pre-existing README roadmap link. No real profiles were read, no real machine configuration was applied, and no publication was attempted.
- Remaining: perform the documented manual terminal check, then complete patch version synchronization and final P1.3 checks. Guide republishing remains a separate authorized action.

### 2026-09-30 — Manual-check handoff and authorized main-branch checkpoint

- Clarified the remaining manual check: visible key-creation and encrypted-key-validation prompts, hidden passphrase input, Ctrl+C returning control and releasing owned locks, unchanged configuration/key hashes after cancellation, and prompt-free noninteractive failure. The disposable preparation and commands are in `docs/HOWTO.html`, under Tests and versioning.
- Updated `AGENTS.md` so future sessions distinguish automated stream tests from actual Windows console evidence and keep P1.1/P1.3 open until verified. Commit/push authorization does not imply phase completion or permission to modify real configuration.
- User requested all current changes be committed and pushed to `main`; retain v0.3.0 and the unreleased changelog entry. Prior automated results remain 113 integration, 29 rendering and 20 native checks; this follow-up changes guidance only. The next implementation task remains the manual Windows check, followed by v0.3.1 release verification.

### 2026-09-30 — v0.3.1 version bump; manual verification deferred by user

- User explicitly requested the patch version for the implemented changes and will perform manual Windows verification later. This supersedes the earlier decision to hold v0.3.0 until that check.
- Updated `$ScriptVersion`, README, HOWTO, CHANGELOG, CLAUDE and both suites' version references to v0.3.1. Updated AGENTS and the current handoff to separate versioning from outstanding acceptance evidence. Historical session entries above retain their original versions and results.
- Verification: `pwsh -NoProfile -File tests/Run-Tests.ps1` passed 113 checks, including v0.3.1 version-only output with missing config and no dependencies on PATH. `pwsh -NoProfile -File tests/Render-Status.ps1` passed 29 checks. Direct `ghprofile.ps1 --version` printed only v0.3.1; `git diff --check` passed. Native execution behavior was unchanged, so its prior 20 passing checks were not rerun for this metadata-only correction.
- Next: user performs the HOWTO manual terminal checklist; record and assess the results before closing P1.1/P1.3. No tag, hosted release, external guide publication or real machine configuration change is part of this bump.

### 2026-09-30 — Sanitized state-storage documentation

- Added README storage locations and ownership explanations for profile definitions, managed Git generations/backups, GitHub CLI account selection/tokens, signing keys, live authentication checks and separate push authentication. Added the detailed local HOWTO storage reference using generic paths and placeholders only.
- Verification: checked documentation against the script and installed GitHub CLI help; `git diff --check` passed, and added documentation passed a scan for known local identifiers. No private profile or credential contents were read. Documentation-only change; executable tests were not rerun and v0.3.1 remains unchanged.
- Handoff unchanged: manual Windows verification for P1.1/P1.3 remains pending. The external guide was not republished; this request authorizes local documentation edits only.

### 2026-09-30 - Requested CLI prerequisite checks (v0.3.2)

- [x] Add early executable availability checks for `gh` and `git` to all operational commands, including previews, before reading profiles. Report all missing tools with PATH/install guidance and exit 1; retain existing JSON errors and dependency-free version output.
- Changed `ghprofile.ps1`, README, HOWTO, CHANGELOG, CLAUDE and version assertions together; added `tests/Prerequisites.ps1` with isolated missing/both-present PATH fixtures. Existing Git minimum-version validation remains unchanged.
- Verification: `pwsh -NoProfile -File tests/Prerequisites.ps1` passed 14 checks; `pwsh -NoProfile -File tests/Render-Status.ps1` passed 29. `tests/Run-Tests.ps1` passed its first five checks (version and parser), then stopped because Git was unavailable. Git is also unavailable in an approved outside-sandbox status check, so repository status/diff checks and full integration verification remain blocked. Native execution/streaming code was unchanged; the native suite was not rerun.
- No real configuration or publication was performed. The local guide remains authoritative; external guide publication is outside this request. P1.1 and P1.3 remain open.
- Next: rerun integration and `git diff --check` where Git is available, then record the user's deferred manual Windows terminal verification before closing P1.1/P1.3.

### 2026-09-30 - Pre-commit verification after Git installation

- Confirmed Git 2.56.0.windows.1 and GitHub CLI 2.102.0 are discoverable. All suites passed: `tests/Prerequisites.ps1` 14, `tests/Run-Tests.ps1` 113, `tests/Render-Status.ps1` 29, and `tests/Native-Execution.ps1` 20 checks. PowerShell 7.6.6; Windows OpenSSH file version 9.5.6.2.
- The first integration run hit a sandbox denial on atomic replacement of a disposable configuration file. The approved outside-sandbox rerun passed all 113 checks. No real configuration or accounts were changed.
- `ghprofile.ps1 --version` printed only v0.3.2; `git diff --check` passed. Updated README/HOWTO verification notes to remove the resolved Git blocker and removed a duplicated test command in HOWTO. Preserved existing storage documentation edits.
- Verification only: no commit, push, tag, release or guide publication performed. Next: commit when requested; the deferred manual Windows checklist still gates P1.1/P1.3 completion.

### 2026-09-30 - Guided manual Windows verification runner

- Added `tests/Manual-Windows.ps1`: one interactive driver for disposable key creation, creation cancellation, encrypted-key validation, validation cancellation, and bounded noninteractive failure. It records versions, explicit human observations, exit/file/lock checks and resumable checkpoints. Ctrl+C can interrupt the driver; the printed `-Resume` command continues verification of the pending cancellation. Forced fallback termination cannot be counted as successful cleanup.
- Reports contain metadata, results and hashes only; native output, passphrases and private-key contents are not logged. The driver restores Git/gh environment variables and working directory, retains disposable fixtures, and requires all checks plus human observations to pass before reporting Complete. Blank-passphrase keys fail the expected noninteractive exit-1 check.
- Added `tests/Manual-Windows.Tests.ps1`; all 13 helper checks passed, including snapshot additions/deletions/modifications, JSON checkpoint round trip, content exclusion, prompt detection, child exit handling, timeout and owned-child termination. `tests/Native-Execution.ps1` passed 20 checks; `git diff --check` passed. The existing CLI was unchanged, so the prior 14 prerequisite / 113 integration / 29 rendering results still apply; version remains v0.3.2.
- Updated README and HOWTO with invocation, resume and reporting instructions. No interactive manual run has been claimed: actual console visibility, hidden input and terminal Ctrl+C still require the user's observations. P1.1/P1.3 remain open. No real configuration, commit or publication performed.
- Next: run the driver in the user's Windows terminal, share its report.txt, and assess the results before closing manual acceptance criteria.

### 2026-09-30 - User-supplied manual Windows evidence; Phase 1 accepted

- Evidence source: the user's pasted `Manual-Windows.ps1` report, Status Complete, Next stage 5, Pending False, with all 24 checks Pass. This is user-observed console evidence, not a new automated run by the agent.
- Environment: Windows Terminal 1.x (exact build not supplied), PowerShell 7.6.6, tool v0.3.2, Git 2.56.0.windows.1, GitHub CLI 2.102.0 (2026-09-30), Windows OpenSSH file version 9.5.6.2 at `C:\WINDOWS\System32\OpenSSH\ssh-keygen.exe`.
- Key creation: exit 0, both key files present, lock released, both prompts visible before input, both passphrase entries hidden. Creation cancellation returned control without forced termination, released its lock, created no global configuration, preserved the existing sample pair and left no partial cancelled private/public key files.
- Setup: exit 0, validation prompt visible before input, passphrase hidden, isolated global configuration created and lock released. Validation cancellation returned control, preserved all fixture files and left no global lock.
- Noninteractive encrypted-key validation completed in 1.07 seconds, exit 1, with neither captured-stream nor direct-console passphrase prompts. All fixture files remained unchanged and no global lock remained.
- Assessment: the report meets the remaining manual acceptance criteria. Together with recorded automated verification (14 prerequisite, 113 integration, 29 rendering, 20 native and 13 runner-helper checks), synchronized v0.3.2 references and local documentation, P1.1/P1.3 are complete. Exact terminal build and PowerShell 7.2 compatibility remain evidence limitations, not claims of additional tested environments.
- Follow-up verification: `git diff --check` passed; `ghprofile.ps1 --version` printed only v0.3.2; script, current guide/README/CLAUDE references and version assertions remain synchronized.
- Updated README, HOWTO and the current changelog status; retained historical session entries. Documentation-only follow-up, no executable changes or broad-suite rerun. No commit, push, release, tag, real configuration change or external guide publication performed. Next: commit when requested; P2.1 is the next roadmap implementation task.
