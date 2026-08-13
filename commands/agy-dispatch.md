---
description: Force-dispatch a task to an agy worker using the dispatching-to-agy-workers skill, instead of waiting for auto-match.
disable-model-invocation: false
---

## Task from the user

$ARGUMENTS

## Your job

Use the **`dispatching-to-agy-workers`** skill (from the `agy-orchestrator`
plugin) for the task above — do not skip straight to doing it yourself, and
do not silently fall back to a native Claude subagent instead of `agy`.
This skill requires a live Herdr session; check `test "${HERDR_ENV:-}" = 1`
first, and if that fails, say so explicitly instead of doing anything else.
Follow that skill's process exactly:

1. Pick (or create) a `.agents/worker_agy_N/` directory and write its
   `BRIEFING.md` from the task above. Pick a unique Herdr agent name
   (check `herdr agent list` first).
2. Dispatch via `scripts/dispatch-agy-worker.sh` (macOS/Linux/Git-Bash/WSL)
   or `scripts/dispatch-agy-worker.py` (Windows / no bash available) —
   pick by platform — passing the absolute workspace path, the record dir,
   the task, and the agent name. This runs `herdr pane split` → `herdr
   agent start --kind agy ... -- --add-dir <workspace>` → `herdr agent
   prompt --wait` under the hood.
3. If the script exits `2` (worker `blocked`), resolve it interactively
   yourself via `herdr agent read` / `send-keys` / `prompt` on that agent
   name — do not treat a blocked worker as failed, and do not leave it
   hanging.
4. Self-check the actual produced files/output yourself — never trust a
   settled `idle`/`done` status alone.
5. Only dispatch an independent Claude reviewer subagent if this task meets
   the importance bar in `SKILL.md`'s Review Policy. If the user's task text
   above contains "quan trọng", "important", or "--important", treat that
   as forcing the reviewer regardless of the other criteria.
6. Update `.agents/orchestrator/GATE_STATUS.md` and report the result back
   in your own words — don't just paste agy's raw response.

If Herdr is not active, `agy` is not installed, or the plugin's skill file
is missing, say so explicitly instead of quietly doing the task natively in
Claude.
