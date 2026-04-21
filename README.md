# Codex Session Cleaner

[简体中文说明](README.zh-CN.md)

Safely and physically clean a local Codex session by session ID on Windows and macOS, using a Python-based workflow that moves files into `trash` instead of permanently deleting them.

## Highlights

- Preview-first workflow before any write action
- Exact-reference cleanup for `session_index.jsonl` and `.codex-global-state.json`
- Moves matched session files into `trash` for recovery
- Keeps a recovery path with backups and a cleanup manifest
- Avoids modifying higher-risk SQLite files
- Explicit invocation only: `allow_implicit_invocation: false`

## Repository Layout

This repository is intended to be published with the skill root as the repository root.

Key entries:

- `SKILL.md`
  Skill instructions and behavior contract
- `scripts/remove-session-by-id.py`
  Main Python implementation for Windows and macOS
- `references/`
  Detailed usage, layout, recovery, and safety notes

## Requirements

- Codex with access to a local Codex home directory
- Python `3.9+`
- Read/write access to the target `$CODEX_HOME` when running in apply mode

## Installation

### Method A: Install from GitHub with `skill-installer`

Because this repository is designed as a standalone skill repo, install it from the repo root with `--path "."` and an explicit destination name.

Windows:

```powershell
python "$CODEX_HOME\skills\.system\skill-installer\scripts\install-skill-from-github.py" `
  --repo "<owner>/<repo>" `
  --path "." `
  --name "codex-session-cleaner"
```

macOS:

```bash
python3 "$CODEX_HOME/skills/.system/skill-installer/scripts/install-skill-from-github.py" \
  --repo "<owner>/<repo>" \
  --path "." \
  --name "codex-session-cleaner"
```

If `CODEX_HOME` is not set in your environment, replace it with your local Codex home path.

### Method B: Manual install

1. Clone or download this repository.
2. Copy the repository root into `$CODEX_HOME/skills/codex-session-cleaner`.
3. Restart Codex so the new skill can be discovered.

## Quick Start

Recommended prompt:

```text
Use $codex-session-cleaner to preview cleaning session <session-id>
```

Or:

```text
Use $codex-session-cleaner to physically clean session <session-id>
```

Direct CLI usage:

Windows preview:

```powershell
python "$CODEX_HOME\skills\codex-session-cleaner\scripts\remove-session-by-id.py" `
  --session-id "<session-id>"
```

Windows apply:

```powershell
python "$CODEX_HOME\skills\codex-session-cleaner\scripts\remove-session-by-id.py" `
  --session-id "<session-id>" `
  --apply
```

macOS preview:

```bash
python3 "$CODEX_HOME/skills/codex-session-cleaner/scripts/remove-session-by-id.py" \
  --session-id "<session-id>"
```

macOS apply:

```bash
python3 "$CODEX_HOME/skills/codex-session-cleaner/scripts/remove-session-by-id.py" \
  --session-id "<session-id>" \
  --apply
```

Optional explicit Codex home:

```text
--codex-home "<codex-home>"
```

## Safety Notes

- Do not physically clean the currently active conversation from inside itself.
- Preview first and verify the hit counts before running `--apply`.
- Session files are moved into `trash`; they are not permanently deleted by default.
- This skill does not modify `state_*.sqlite`, `logs_*.sqlite`, or other SQLite files.
- Only exact session ID references are cleaned; ordinary free text is not fuzzy-rewritten.

## More Docs

- [Chinese README](README.zh-CN.md)
- [Detailed English usage guide](references/usage-en.md)
- [Session layout, trash structure, and recovery notes](references/codex-session-layout.md)
