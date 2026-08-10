---
name: dispatching-to-agy-workers
description: Use when you want Claude Code to act as orchestrator and dispatch execution tasks to agy (Antigravity CLI) headless sessions as external workers, coordinated through a file-based .agents/ ledger.
---

# Dispatching to agy Workers

## Overview

Claude Code (you) stays the **orchestrator**. Each **worker** is a separate
`agy` (Antigravity CLI, Google) process, launched headless via `--print`, run
as an external tool through the Bash tool — not a native Claude subagent.
An independent **Claude subagent** (Agent tool) reviews every worker's claim
before you trust it.

This is a different shape than `superpowers:dispatching-parallel-agents` or
`superpowers:subagent-driven-development`: those dispatch *native, homogeneous*
subagents inside one harness (Claude's Task tool, or agy's own
`invoke_subagent` if agy itself is the controller). Here the controller and
the worker are **two different CLIs**, talking only through the filesystem
and a JSON response on stdout — use this skill specifically when you want
agy (its models, its cost profile) to do the execution work while Claude does
the coordination and review.

## When to Use

- You explicitly want an `agy` session to execute a task (e.g. to use its
  Gemini-family models, or to keep execution cost/tokens off the Claude
  session) while Claude coordinates, reviews, and decides next steps.
- The task is scriptable as a single self-contained prompt agy can complete
  in one headless turn (`agy --print`) — not an interactive back-and-forth.

**Don't use when:** the task needs a live human-in-the-loop approval flow
(use interactive `agy` instead), or the task is naturally a Claude subagent's
job — don't reach for agy just because you can.

## The one gotcha that will bite you

`agy --print` does **not** use the launching process's cwd as its workspace.
Without `--add-dir <absolute-path>`, agy may silently write files into its
own `~/.gemini/antigravity-cli/scratch/` instead of your intended directory —
**while still reporting `"status":"SUCCESS"`**. Verified empirically
(2026-08-10): identical prompt, only difference was `--add-dir`.

**Always:**
1. Pass `--add-dir <absolute-path-to-workspace>`.
2. Repeat that same absolute path inside the prompt text itself.
3. Never trust `status: SUCCESS` alone — always have a reviewer independently
   check the actual files/output (see Review step below).

Use `scripts/dispatch-agy-worker.sh` — it bakes in both (1) and (2).

## The `.agents/` ledger convention

Same convention this project's own `senior_product_designer_agent` uses and
Superpowers' skills use in spirit (ledger files survive context loss —
compaction, session restart, or a different machine picking up the work):

```
.agents/
├── ORIGINAL_REQUEST.md      # the goal, written once by the orchestrator
├── orchestrator/
│   ├── plan.md              # orchestrator's running plan/summary
│   └── GATE_STATUS.md       # pass/fail table across all agents
├── worker_agy_N/
│   ├── BRIEFING.md          # orchestrator writes: role, task, constraints
│   ├── DISPATCH.md          # auto-written by dispatch-agy-worker.sh
│   ├── progress.md          # auto-written; agy's self-reported status
│   ├── agy_raw_output.json  # raw --output-format json response
│   └── handoff.md           # orchestrator writes after reviewing: verdict
└── reviewer_N/
    ├── BRIEFING.md          # orchestrator writes: what to verify, how
    ├── review.md            # reviewer writes: findings
    └── handoff.md           # reviewer writes: ends with "VERDICT: PASS/FAIL"
```

Real product files go in a sibling `workspace/` dir, never inside `.agents/`
— `.agents/` is dispatch bookkeeping only.

## The Process

1. **Brief the worker.** Write `.agents/worker_agy_N/BRIEFING.md`: exact task,
   constraints ("only touch files under `workspace/`"), expected output.
2. **Dispatch.**
   ```bash
   skills/dispatching-to-agy-workers/scripts/dispatch-agy-worker.sh \
     <absolute-workspace-path> \
     .agents/worker_agy_N \
     "<task prompt>" \
     [timeout, default 5m]
   ```
   This writes `DISPATCH.md`, `progress.md`, and `agy_raw_output.json` for
   you, and prints the raw JSON to stdout too.
3. **Never dispatch two agy workers at the same absolute workspace path
   concurrently** — same reasoning as never running two implementers on the
   same files in `subagent-driven-development`: conflicting writes, no lock.
4. **Review — always, no exceptions.** Dispatch a Claude subagent (Agent
   tool, `general-purpose` is fine) with a `reviewer_N/BRIEFING.md` that says:
   read the worker's files, then **independently** inspect the actual
   workspace files and re-run/re-check the claim yourself — do not just
   parse `agy_raw_output.json` and trust `status`. The reviewer's
   `handoff.md` must end with `VERDICT: PASS` or `VERDICT: FAIL` plus a
   one-sentence reason.
5. **Gate.** Update `.agents/orchestrator/GATE_STATUS.md` with every
   worker/reviewer pair. Only report the task done to the human once the
   reviewer's verdict is PASS.

## Confidence notes (as of 2026-08-10)

`agy` is a very new CLI (Google, ~May 2026). Community reports (GitHub
`google-antigravity/antigravity-cli#76`) describe `agy --print` producing no
stdout at all on some platforms/versions when stdout isn't a TTY — not
reproduced on this machine, but if a dispatch returns empty output with exit
0, this is the known suspect, not a bug in this skill's script.
