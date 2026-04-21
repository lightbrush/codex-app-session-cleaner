# English Usage Guide

## Purpose

Use this skill to safely and physically clean a local Codex session by session ID without doing destructive deletion.

Typical requests include:

- "Delete this session by session ID"
- "Physically clean a local Codex conversation"
- "Remove a session from local history but keep a recovery path"
- "Clean the session index and global state references for a session"

This guide assumes Windows or macOS. The main implementation uses only the Python standard library and requires `Python 3.9+`.

## Safety Model

This skill follows a conservative workflow:

1. Preview first, apply second.
2. Move session files into `trash` instead of permanently deleting them.
3. Remove only exact session ID references from indexes and global state.
4. Avoid modifying higher-risk SQLite files such as `state_*.sqlite` or `logs_*.sqlite`.
5. Stop if the target session appears to be the currently active conversation.

## Path Conventions

To avoid exposing any real username, machine-specific path, or other private information, all examples in this document use anonymous placeholders:

- `C:\Users\<user>\.codex`
  Example Codex home path for the current user.
- `<skill-dir>`
  The installed skill directory, for example `C:\Users\<user>\.codex\skills\codex-session-cleaner`.
- `<session-id>`
  The target session ID.

If the environment already defines `CODEX_HOME`, prefer `$CODEX_HOME` when reading or adapting path examples.

## Files and Directories That May Be Touched

The skill may read or update these locations:

- `$CODEX_HOME\sessions\...`
- `$CODEX_HOME\archived_sessions\...`
- `$CODEX_HOME\session_index.jsonl`
- `$CODEX_HOME\.codex-global-state.json`
- `$CODEX_HOME\trash\session-cleaner\...`

## Recommended Prompting

Explicit invocation:

```text
Use $codex-session-cleaner to preview cleaning session <session-id>
```

Or:

```text
Use $codex-session-cleaner to physically clean session <session-id>
```

## Direct CLI Usage

Windows preview:

```powershell
python "C:\Users\<user>\.codex\skills\codex-session-cleaner\scripts\remove-session-by-id.py" `
  --session-id "<session-id>"
```

Windows apply:

```powershell
python "C:\Users\<user>\.codex\skills\codex-session-cleaner\scripts\remove-session-by-id.py" `
  --session-id "<session-id>" `
  --apply
```

Windows apply with an explicit Codex home:

```powershell
python "C:\Users\<user>\.codex\skills\codex-session-cleaner\scripts\remove-session-by-id.py" `
  --session-id "<session-id>" `
  --codex-home "C:\Users\<user>\.codex" `
  --apply
```

macOS preview:

```bash
python3 "/Users/<user>/.codex/skills/codex-session-cleaner/scripts/remove-session-by-id.py" \
  --session-id "<session-id>"
```

macOS apply:

```bash
python3 "/Users/<user>/.codex/skills/codex-session-cleaner/scripts/remove-session-by-id.py" \
  --session-id "<session-id>" \
  --apply
```

macOS apply with an explicit Codex home:

```bash
python3 "/Users/<user>/.codex/skills/codex-session-cleaner/scripts/remove-session-by-id.py" \
  --session-id "<session-id>" \
  --codex-home "/Users/<user>/.codex" \
  --apply
```

Environment-variable style example:

```powershell
python "$CODEX_HOME\skills\codex-session-cleaner\scripts\remove-session-by-id.py" `
  --session-id "<session-id>" `
  --apply
```

```bash
python3 "$CODEX_HOME/skills/codex-session-cleaner/scripts/remove-session-by-id.py" \
  --session-id "<session-id>" \
  --apply
```

## How To Read Preview Output

The preview command returns a JSON summary. Focus on these fields:

- `SessionFiles`
  The session files that would be moved into `trash`.
- `SessionIndex.RemovedCount`
  How many records would be removed from `session_index.jsonl`.
- `GlobalState.RemovedReferenceCount`
  How many exact references would be removed from `.codex-global-state.json`.
- `Trash.TrashRoot`
  The target backup and recovery directory for the apply run.

## What Apply Mode Does

Apply mode will:

1. Back up `session_index.jsonl`
2. Back up `.codex-global-state.json`
3. Move matching session files into `trash\session-cleaner\...`
4. Write a `cleanup-manifest.json`

## Trash Folder Structure

A typical structure looks like this:

```text
$CODEX_HOME/trash/session-cleaner/<timestamp>-<session-id>/
├── backups/
│   ├── session_index.jsonl.bak
│   └── .codex-global-state.json.bak
├── session-files/
│   ├── sessions/
│   └── archived_sessions/
└── cleanup-manifest.json
```

How to read it:

- `backups/`
  Stores the pre-change copies of the index and global state files.
- `session-files/`
  Stores the moved session files.
- `sessions/` / `archived_sessions/`
  Preserve the original source scope so restoration can put files back in the correct place.
- `cleanup-manifest.json`
  Stores a summary of the cleanup run for review.

## Recovery Guide

If you need to restore a cleaned session, follow this order:

1. Find the target trash folder
   For example `$CODEX_HOME/trash/session-cleaner/<timestamp>-<session-id>/`
2. Restore `backups/session_index.jsonl.bak`
   Copy it back over `session_index.jsonl`
3. Restore `backups/.codex-global-state.json.bak`
   Copy it back over `.codex-global-state.json`
4. Move the session files from `session-files/...` back to their original location
   Put them back under `sessions/` or `archived_sessions/` based on the saved scope
5. Restart Codex
   So the UI reloads the restored session state

Recovery boundaries:

- Restore from the same cleanup batch folder; do not mix backups from one cleanup with session files from another.
- Restoring only the index without the session file can leave the UI pointing at a missing conversation file.
- Restoring only the session file without the index/global state can leave the conversation hidden in the UI.
- This guide does not include SQLite restoration, and manual database edits are not recommended.

## Structured Completion Report Example

```text
Cleanup Report
Status: `Completed, Restart Codex`
Session ID: `<session-id>`
Thread Name: `<thread-name>`
Original Conversation Location: `<original-session-path>`
Session Files Moved: `<count>`
Session Index Records Removed: `<count>`
Global State References Removed: `<count>`
Trash Directory: `<path>`
Next Step: `If needed, restore from the matching trash folder, then restart Codex`
```

Notes:

- `Original Conversation Location` usually comes from the original session file path in `SessionFiles`.
- If multiple session files are matched, show the first path and note that additional matched files also exist.
- Keep all dynamic values wrapped in backticks as raw text, and do not render them as `[]()` Markdown links.

## Preview Result Example

```text
Preview Result
Status: `Preview Only`
Session ID: `<session-id>`
Thread Name: `<thread-name>`
Original Conversation Location: `<original-session-path>`
Session Files To Move: `<count>`
Session Index Records To Remove: `<count>`
Global State References To Remove: `<count>`
Target Trash Directory: `<path>`
Next Step: `If everything looks correct, run the actual cleanup`
```

Notes:

- `Original Conversation Location` usually comes from the original session file path in `SessionFiles`.
- If multiple session files are matched, show the first path and note that additional matched files also exist.
- Keep all dynamic values wrapped in backticks as raw text, and do not render them as `[]()` Markdown links.

## Failure Summary Example

```text
Cleanup Incomplete
Status: `Failed`
Session ID: `<session-id>`
Thread Name: `<thread-name>`
Original Conversation Location: `<original-session-path>`
Reason: `<reason>`
Write Status: `<write-status>`
Next Step: `Check the session ID, preview hits, or active-thread state before retrying`
```

Notes:

- `Reason` should stay short and directly describe the failure.
- `Write Status` should clearly state whether no write happened or where the write stopped.
- Keep all dynamic values wrapped in backticks as raw text, and do not render them as `[]()` Markdown links.

## Risk Notes

- Do not physically clean the current live conversation from inside itself.
- If preview returns zero matches, verify the session ID before applying.
- Even when a user asks for permanent deletion, prefer the `trash` workflow first.
