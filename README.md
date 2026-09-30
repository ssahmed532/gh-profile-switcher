# gh-profile-switcher

> **Version:** v0.1.1 — Last updated 2026-09-30

Manage folder-based Git identities and signing settings, with explicit GitHub CLI account switching and diagnostics; push authentication is reported separately as unverified.

- Requires PowerShell 7.2+, Git 2.34+, a current GitHub CLI, and OpenSSH for signing; Windows is the verified platform.
- Copy `profiles.example.json` to `profiles.json`, fill in the values, then run `./ghprofile.ps1 setup -WhatIf` followed by `setup`.
- `strict` policy requires explicit roots for every profile; `default` policy retains an unmatched-repository fallback for compatibility.
- `init-key <profile>` creates a new signing key interactively and refuses to overwrite either existing key file.
- `switch <profile>` changes the shared gh account; `status` explains identity selection; `doctor` detects configuration and authentication issues.
- Default status is a compact, width-aware console summary; `status -Verbose` shows configuration origins and helpers, while `status -Json` retains structured details.
- `-ConfigPath`, `-WhatIf`, `-NonInteractive`, and status/doctor `-Json` support reuse and automation.
- `./ghprofile.ps1 --version` prints only `v0.1.1`, without loading configuration or checking dependencies.
- Versioning follows [SemVer](https://semver.org/spec/v2.0.0.html); the current patch release is `0.1.1`, with release details in [CHANGELOG.md](CHANGELOG.md).
- Run isolated regression tests with `pwsh -NoProfile -File tests/Run-Tests.ps1`.

## Files

- `profiles.json`: git-ignored profile definitions; existing `default`/`root` configurations remain supported.
- `ghprofile.ps1`: validated setup with immutable generations, an atomic global-config activation, backups, and checked native commands.
- [docs/HOWTO.html](docs/HOWTO.html): full setup, credential provisioning, signing, migration, recovery, limitations and versioning guide.
- The previously published private guide is at https://claude.ai/artifact/MtDvSF8CV4CsK59EXnX77o; use the local guide for v0.1.1 until that artifact is republished.
- Repo: https://github.com/ssahmed532/gh-profile-switcher (public).
- `CLAUDE.md`: rules and gotchas for Claude Code sessions in this folder.
