# CLAUDE.md — gh-profile-switcher

> **Version:** v0.3.1 — Last updated 2026-09-30

## Rules

- Any change to script behavior updates `README.md` and `docs/HOWTO.html` in the same turn, and bumps the version and date in each.
- `docs/HOWTO.html` is the source of the published guide artifact (link in `README.md`). After editing it, republish it to that same artifact URL; never publish it as a new artifact.
- Detail lives in `docs/HOWTO.html`. `README.md` gets one-line summaries only.

## Constraints

- This is a public GitHub repo (link in `README.md`). It sits under the personal profile's `root` folder (see `profiles.json`), so its commits use the personal profile. Every tracked file is public.
- Run real `setup` or `switch` only when the user asks to apply configuration or switch accounts; requests to edit the script do not require applying it to the machine.
- Tests use `tests/Run-Tests.ps1`, isolated `GIT_CONFIG_GLOBAL`/`GH_CONFIG_DIR`, temporary repositories and disposable keys. Never use real profiles for integration tests.
- Setup writes immutable generations beside the selected global Git config, then atomically activates one managed include. Old files and external allowed-signers files are preserved.
- `ssh-agent` is disabled on this machine. File signing uses the private-key path explicitly and validates the matching `.pub` file; agent mode is separately supported.
- `$ScriptVersion` in `ghprofile.ps1` is the release version source. Keep README, HOWTO, CHANGELOG and version tests synchronized.

## Gotchas

- `includeIf "gitdir/i:..."` matches only inside a git repo. Test `status` inside a repo under a profile root (this repo works), not in the root folder itself.
- `profiles.json` holds real names and emails and is git-ignored. Don't copy its values into chat replies, commit messages or any tracked file; `docs/HOWTO.html` uses placeholders and the example root `C:\personal\` only.

---
*Produced with Claude Code (CLI, Windows / PowerShell), model Claude Opus 5.5.*
