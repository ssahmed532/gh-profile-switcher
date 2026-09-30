# gh-profile-switcher

> **Version:** v0.3.2 — Last updated 2026-09-30
> **Verification:** Automated checks pass; the user-reported Windows prompt, hidden-input and Ctrl+C verification passed all 24 checks.

Manage folder-based Git identities and signing settings, with explicit GitHub CLI account switching and diagnostics; push authentication is reported separately as unverified.

- Requires PowerShell 7.2+, Git 2.34+, a current GitHub CLI, and OpenSSH for signing; Windows is the verified platform.
- Copy `profiles.example.json` to `profiles.json`, fill in the values, then run `./ghprofile.ps1 setup -WhatIf` followed by `setup`.
- `strict` policy requires explicit roots for every profile; `default` policy retains an unmatched-repository fallback for compatibility.
- `init-key <profile>` creates a new signing key interactively and refuses to overwrite either existing key file.
- v0.3.2 checks for `gh` and `git` on PATH before loading profiles; missing tools cause exit 1 with installation guidance.
- `switch <profile>` changes the shared gh account; `status` explains identity selection; `doctor` detects configuration and authentication issues.
- Interactive status uses colored sections and Unicode symbols; `-Plain` selects plain text, `-Color Auto|Always|Never` controls color, and redirected output stays plain by default.
- Setup uses the same styling for plans, validation, activation, backups and errors; `setup -WhatIf` shows a no-write preview.
- `status -Verbose` shows configuration origins and helpers, while `status -Json` retains structured details.
- `-ConfigPath`, `-WhatIf`, `-NonInteractive`, and status/doctor `-Json` support reuse and automation.
- `./ghprofile.ps1 --version` prints only `v0.3.2`, without loading configuration or checking dependencies.
- Versioning follows [SemVer](https://semver.org/spec/v2.0.0.html); the current release is `0.3.2`, with release details in [CHANGELOG.md](CHANGELOG.md).
- Check missing-tool startup errors with `pwsh -NoProfile -File tests/Prerequisites.ps1`.
- Run isolated regression tests with `pwsh -NoProfile -File tests/Run-Tests.ps1`.
- Check prompt streaming, cancellation and redaction with `pwsh -NoProfile -File tests/Native-Execution.ps1`; manual Windows checks are in the local guide.
- Run guided Windows prompt/Ctrl+C verification with `pwsh -NoProfile -File tests/Manual-Windows.ps1`; it isolates fixtures, validates results and writes a resumable report.
- Check terminal rendering with `pwsh -NoProfile -File tests/Render-Status.ps1`; add `-Preview` for synthetic healthy and warning examples.

## Where state is stored

There is no single state file: profile definitions, effective Git settings, and GitHub CLI authentication are separate.

Paths below are generic: `~` means the user's home directory, `<global-config>` means the global Git file selected by setup, and `<gh-config>` means GitHub CLI's configuration directory.

| Location | Contents |
| --- | --- |
| `profiles.json` beside `ghprofile.ps1`, or the file supplied with `-ConfigPath` | Profile identities, folder roots, GitHub usernames/hosts, and signing-key paths; the default file is git-ignored. |
| `<global-config>` (normally `~/.gitconfig`) | Include pointing to the active managed configuration generation. |
| `<global-config>.ghprofile/<generation-id>/config` | Folder-based profile selection rules and base/default settings. |
| `<global-config>.ghprofile/<generation-id>/<profile>.gitconfig` | Generated identity, signing settings, HTTPS username hint, and `ghprofile.profile` marker. |
| `<global-config>.ghprofile/<generation-id>/allowed_signers` | Public signing trust, including retained historical entries; no private keys or tokens. |
| `<global-config>.ghprofile/<generation-id>/manifest.json` | Setup version, policy, source configuration path, and creation time. |
| `<global-config>.ghprofile/<generation-id>/integration.gitconfig` | Include fragment used to activate that generation. |
| `<global-config>.bak-<timestamp>-<id>` | Global Git configuration backups retained by setup. |
| `<gh-config>/hosts.yml` | GitHub CLI host/account configuration and active-account selection; may also contain tokens when plaintext storage is used. |
| `<gh-config>/config.yml` | General GitHub CLI preferences. |
| System credential store | GitHub CLI tokens normally live here; on Windows this is the Windows credential store. |
| Each profile's configured `signingKey` path | Public signing key; file mode uses the adjacent private key with the `.pub` suffix removed. |

- Setup honors `GIT_CONFIG_GLOBAL`; otherwise it uses `~/.gitconfig`, falling back to an existing `$XDG_CONFIG_HOME/git/config` (or `~/.config/git/config`) only when `~/.gitconfig` is absent.
- GitHub CLI uses `GH_CONFIG_DIR`, then `$XDG_CONFIG_HOME/gh`, then `%APPDATA%/GitHub CLI` on Windows, otherwise `~/.config/gh`.
- The effective Git profile is selected dynamically by Git's folder rules, subject to configuration overrides; there is no saved “last selected Git profile.”
- Inside a repository, `git config --show-origin --get ghprofile.profile` shows the effective managed marker and its source, without retrieving authentication tokens.
- `switch <profile>` delegates to `gh auth switch`, changing the shared CLI account across terminals using the same configuration; it does not change folder-based Git identity.
- Authentication health is queried live with `gh auth status`; the script keeps no persistent authentication-health cache and does not manage its own token store.
- `GH_TOKEN`/`GITHUB_TOKEN`, or `GH_ENTERPRISE_TOKEN`/`GITHUB_ENTERPRISE_TOKEN` for enterprise hosts, override stored CLI credentials.
- Git push authentication uses its configured credential helper or SSH setup separately; a CLI login or configured username does not verify push identity.
- See the [storage reference](docs/HOWTO.html#storage) for path resolution, temporary files, and credential-storage details; actual configuration and diagnostic output can contain private identities and paths.

## Files

- [TODO.md](TODO.md): phased implementation roadmap, acceptance criteria, verification, and session handoff for future Codex work.
- `profiles.json`: git-ignored profile definitions; existing `default`/`root` configurations remain supported.
- `ghprofile.ps1`: validated setup with immutable generations, an atomic global-config activation, backups, and checked native commands.
- [docs/HOWTO.html](docs/HOWTO.html): full setup, credential provisioning, signing, migration, recovery, limitations and versioning guide.
- The previously published private guide is at https://claude.ai/artifact/MtDvSF8CV4CsK59EXnX77o; use the local guide for v0.3.2 until that artifact is republished.
- Repo: https://github.com/ssahmed532/gh-profile-switcher (public).
- `CLAUDE.md`: rules and gotchas for Claude Code sessions in this folder.
