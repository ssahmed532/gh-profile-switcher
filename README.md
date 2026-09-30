# gh-profile-switcher

> **Version:** 1.6 — Last updated 2026-09-30

Use more than one GitHub account on one Windows machine without mixing up commits, signatures or push credentials. Identity is chosen by folder: repos under a profile's `root` use that profile's name, email, SSH signing key and GitHub account, and all other repos use the default profile. The folder rule applies only inside a git repo: in a directory that is not a repo, including a profile's `root` folder itself, git uses the default profile, so `status` and `switch` show only the `gh` account and the folder rule there. Only the `gh` CLI account is switched by hand.

## Files

- `profiles.json`: the profile definitions. `default` names the profile kept in the global `~/.gitconfig`. Every other profile needs a `root` folder. It is git-ignored; create it by copying `profiles.example.json` and replacing every `REPLACE-ME` value.
- `ghprofile.ps1`: `setup`, `switch <profile>` and `status`. `setup` stops with an error if a profile's `signingKey` `.pub` file has no private key next to it (same path without `.pub`), because signing without `ssh-agent` needs that file.
- `docs/HOWTO.html`: the full guide, covering how it works, setup steps, daily use, troubleshooting, changes and removal, and limits. It is published as a private artifact at https://claude.ai/artifact/MtDvSF8CV4CsK59EXnX77o; others can open `docs/HOWTO.html` from the repo instead.
- Repo: https://github.com/ssahmed532/gh-profile-switcher (public).
- `CLAUDE.md`: rules and gotchas for Claude Code sessions in this folder.

---
*Produced with Claude Code (CLI, Windows / PowerShell), model Claude Opus 5.5.*
