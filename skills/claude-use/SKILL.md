---
name: claude-use
description: Delegate the user's explicitly requested task work to the local Claude Code CLI via `claude -p`, then have Codex review the result and decide any follow-up improvements. Use only when the user explicitly invokes claude-use, asks to use Claude, or asks to hand the task to local Claude Code CLI; do not invoke this skill implicitly for ordinary coding, review, or debugging.
---

# Claude Use

## Overview

Use the local Claude Code CLI as the worker for the current task. Claude should perform the requested work; Codex should run the command, wait for completion, then review Claude's result and handle any needed critique, cleanup, or improvement decisions.

## Workflow

1. Confirm the request is an explicit Claude invocation.
2. Preflight the local CLI from Codex with `command -v claude` and, when cheap, `claude --version`.
3. Run Claude from the relevant working directory with `claude -p`.
4. Do not add an artificial timeout. Claude may run for a long time; keep the session open and poll until it completes.
5. Pass the full task, current constraints, expected deliverable, and the preflighted Claude path/version in the prompt.
6. After Claude exits, inspect what changed and what Claude reported.
7. Codex owns review and improvement: identify issues, make small follow-up fixes when clearly needed, and summarize the final state.

## Command Pattern

Prefer a heredoc so the prompt is readable and shell quoting is safe:

```bash
claude -p "$(cat <<'PROMPT'
You are Claude Code CLI working inside this local repository.

Claude CLI preflight from Codex:
- Path: <output of command -v claude>
- Version: <output of claude --version, if available>

Task:
<user request>

Constraints:
- Do the entire task yourself.
- Follow repository instructions and safety rules.
- Ask before destructive or hard-to-reverse actions.
- Do not commit or push unless the user explicitly asked.
- Report changed files, commands run, verification performed, and blockers.
- Do not review or improve the skill/process itself unless the user explicitly asks; Codex will handle review and improvements after you finish the assigned work.
PROMPT
)"
```

If `claude` is not on `PATH`, check the local install location before giving up:

```bash
command -v claude || ls -l "$HOME/.local/bin/claude"
```

Do this check from Codex before launching Claude. Do not ask Claude to verify whether `claude` itself is installed; nested Claude runs may not have permission to run that shell command even when Codex can launch Claude successfully.

## Codex Role

- Treat Claude as the worker, not just an advisor.
- Let Claude complete the assigned work before taking over.
- Review Claude's output, changed files, and claimed verification after the run.
- Make focused follow-up edits only when Claude's result is incomplete, unsafe, or clearly below the requested standard.
- Run only the verification needed for Codex's follow-up changes or for a user-requested review.
- If Claude leaves a blocker or uncertainty, summarize it plainly and decide whether Codex can resolve it without another Claude run.
- If Claude reports shell approval denial, permission blocking, or inability to run commands, treat that as a worker blocker. Do not keep relaunching the same prompt; review whether any useful work was completed, then report or adjust once.
- Keep the final response concise and in the user's language.

## Long-Running Runs

- Do not wrap `claude -p` in `timeout`.
- If Claude is still running, give short progress updates and continue waiting.
- Do not start a second Claude run for the same task while the first is still running.
- If the process appears stuck, report how long it has been running and keep waiting unless the user asks to stop.
