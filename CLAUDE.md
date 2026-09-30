# CLAUDE.md — gh-profile-switcher

> **Version:** 1.3 — Last updated 2026-09-30

## Rules

- Any change to script behavior updates `README.md` and `docs/HOWTO.html` in the same turn, and bumps the version and date in each.
- `docs/HOWTO.html` is the source of the published guide artifact (link in `README.md`). After editing it, republish it to that same artifact URL; never publish it as a new artifact.
- Detail lives in `docs/HOWTO.html`. `README.md` gets one-line summaries only.

## Constraints

- This is a public GitHub repo (link in `README.md`). It sits under the personal profile's `root` folder (see `profiles.json`), so its commits use the personal profile. Every tracked file is public.
- `setup` rewrites the real `~/.gitconfig`, `~/.gitconfig-<profile>` and `~/.ssh/allowed_signers`. Run it only when the user asks. To test a single function, load it from the script's AST in a scratch script and stub `git` so `allowed_signers` is not touched.
- `ssh-agent` is disabled on this machine. Signing runs `ssh-keygen` with the `.pub` path in `user.signingkey`, and it loads the private key from the same path without `.pub`.

## Gotchas

- `includeIf "gitdir/i:..."` matches only inside a git repo. Test `status` inside a repo under a profile root (this repo works), not in the root folder itself.
- `profiles.json` holds real names and emails and is git-ignored. Don't copy its values into chat replies, commit messages or any tracked file; `docs/HOWTO.html` uses placeholders and the example root `C:\personal\` only.

---
*Produced with Claude Code (CLI, Windows / PowerShell), model Claude Opus 5.5.*
