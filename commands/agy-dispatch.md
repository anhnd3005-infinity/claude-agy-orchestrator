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
Follow that skill's process exactly:

1. Pick (or create) a `.agents/worker_agy_N/` directory and write its
   `BRIEFING.md` from the task above.
2. Dispatch via `scripts/dispatch-agy-worker.sh` (macOS/Linux/Git-Bash/WSL)
   or `scripts/dispatch-agy-worker.py` (Windows / no bash available) —
   pick by platform — with an absolute `--add-dir` workspace path.
3. Self-check the actual produced files/output yourself — never trust
   `agy_raw_output.json`'s `status` field alone.
4. Only dispatch an independent Claude reviewer subagent if this task meets
   the importance bar in `SKILL.md`'s Review Policy. If the user's task text
   above contains "quan trọng", "important", or "--important", treat that
   as forcing the reviewer regardless of the other criteria.
5. Update `.agents/orchestrator/GATE_STATUS.md` and report the result back
   in your own words — don't just paste agy's raw response.

If `agy` is not installed or the plugin's skill file is missing, say so
explicitly instead of quietly doing the task natively in Claude.
