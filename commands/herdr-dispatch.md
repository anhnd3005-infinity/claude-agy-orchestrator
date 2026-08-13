---
description: Force-dispatch a task to a Herdr-managed CLI agent worker using the dispatching-to-herdr-workers skill, instead of waiting for auto-match.
disable-model-invocation: false
---

## Task from the user

$ARGUMENTS

## Your job

Use the **`dispatching-to-herdr-workers`** skill (from the `agy-orchestrator`
plugin) for the task above — do not skip straight to doing it yourself, and
do not silently fall back to a native Claude subagent instead of dispatching
to a worker. This skill requires a live Herdr session; check
`test "${HERDR_ENV:-}" = 1` first, and if that fails, say so explicitly
instead of doing anything else. Follow that skill's process exactly:

1. Determine the worker **kind** (`agy`, `codex`, or another Herdr-supported
   kind) — from the task text if stated, otherwise ask the human. Pick (or
   create) a `.agents/worker_<kind>_N/` directory and write its
   `BRIEFING.md` from the task above. Pick a unique Herdr agent name
   (check `herdr agent list` first).
2. Dispatch via `scripts/dispatch-herdr-worker.sh` (macOS/Linux/Git-Bash/WSL)
   or `scripts/dispatch-herdr-worker.py` (Windows / no bash available) —
   pick by platform — passing the absolute workspace path, the record dir,
   the task, the agent name, and the kind. This runs `herdr pane split` →
   `herdr agent start --kind <kind> ... -- <per-kind native args>` → `herdr
   agent prompt --wait` under the hood, with built-in retries for the known
   `agent_pane_busy` / `agent_prompt_stalled` races and a real
   delivery-confirmation check (see `SKILL.md`'s Lessons log) — don't
   hand-roll the `herdr` sequence yourself.
3. If the script exits `2` (worker `blocked`), resolve it interactively
   yourself via `herdr agent read` / `send-keys` / `prompt` on that agent
   name — do not treat a blocked worker as failed, and do not leave it
   hanging.
4. If the script exits `1` with status `no_delivery_confirmed`, inspect
   `agent_output.txt` yourself before concluding it failed — the underlying
   error code has been unreliable before (see `SKILL.md`).
5. Self-check the actual produced files/output yourself — never trust a
   settled `idle`/`done` status alone.
6. Only dispatch an independent Claude reviewer subagent if this task meets
   the importance bar in `SKILL.md`'s Review Policy — this includes
   treating the first dispatch of a kind you haven't used through this
   skill before as "a new kind of task". If the user's task text above
   contains "quan trọng", "important", or "--important", treat that as
   forcing the reviewer regardless of the other criteria.
7. Update `.agents/orchestrator/GATE_STATUS.md` and report the result back
   in your own words — don't just paste the worker's raw response.

If Herdr is not active, the requested kind's CLI is not installed, or the
plugin's skill file is missing, say so explicitly instead of quietly doing
the task natively in Claude.
