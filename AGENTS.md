# Codex session guidance

Read `CLAUDE.md` for repository constraints and `TODO.md` for the release roadmap, acceptance criteria, verification, and current handoff.

When asked to continue roadmap implementation, start with the earliest unfinished task unless the user specifies otherwise. Follow the session workflow in `TODO.md`, preserve unrelated changes, and update its checkboxes and handoff with actual results before ending the session.

The roadmap is planning guidance, not permission to apply configuration to this machine or publish changes. Use isolated fixtures for development; real setup, account switching, key creation, recovery, cleanup, and publication require applicable user authorization.

## Verification and handoff

- Run `tests/Native-Execution.ps1` for interactive execution or streaming-redaction changes, alongside the relevant integration and rendering suites. Record actual results in `TODO.md`.
- Automated stream and pipeline-cancellation tests do not establish Windows OpenSSH console prompt visibility, hidden passphrase input, or terminal Ctrl+C behavior. Use the disposable manual checklist in `docs/HOWTO.html` and record the terminal, PowerShell/OpenSSH versions and observed results; never record passphrases or private-key material.
- Keep P1.1 and P1.3 open until the manual check and release verification are complete. Follow `TODO.md` for the current handoff; do not infer completion from a commit or push.
- Unfinished phase changes may be committed and pushed when explicitly requested, with an unreleased changelog entry and the existing executable version. Synchronize release versions only when the phase is verified. Repository publication does not by itself authorize a tag, release, external guide update, or real machine configuration change.
