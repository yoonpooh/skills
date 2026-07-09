# Skills

Personal Codex skills for local, practical workflows.

These skills are built for tasks where the agent needs local operating context: organizing Apple Mail and Messages, or delegating work to the local Claude Code CLI.

They are intentionally small. Each skill captures the parts that are easy to forget in the moment: the right command shape, safety rules, account-specific quirks, verification steps, and where Codex should stop versus continue.

## Install

```bash
npx skills@latest add yoonpooh/skills
```

## Why use it?

General agents are useful, but local workflows have sharp edges.

Mail.app has account-specific mailbox names, Gmail archive behavior is label-based, and UI state can lag behind local indexes. Messages has similar DB/UI mismatches and destructive cleanup risks. Claude Code delegation also needs a clear responsibility split: Claude can do the work, while Codex decides how to review and finish.

These skills turn those learned edge cases into reusable instructions.

## Reference

- `mail-use` — Work with Apple Mail and the local Mail.app cache. Supports reading, counting, archiving, deleting, and verifying email actions across iCloud, Gmail, Exchange, Naver, and Kakao.
- `claude-use` — Delegate explicitly requested work to the local Claude Code CLI with `claude -p`, wait without an artificial timeout, then have Codex review the result and decide any follow-up improvements.
- `message-use` — Work with local macOS Messages data for unread triage, conversation summaries, marking read, and spam cleanup without sending replies.

## Notes

- State-changing mail actions should be conservative and verified after the move.
- Mail and Messages may use native AppleScript or local indexes for data access, but every app UI task uses Computer Use from the start.
- Never edit Mail or Messages local databases directly.
- Destructive or hard-to-reverse actions should ask first.
- Claude delegation only runs when explicitly requested.
