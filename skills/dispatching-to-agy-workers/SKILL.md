---
name: dispatching-to-agy-workers
description: Use when you want Claude Code to act as orchestrator and dispatch execution tasks to agy (Antigravity CLI) headless sessions as external workers, coordinated through a file-based .agents/ ledger.
---

# Dispatching to agy Workers

## Overview

Claude Code (you) stays the **orchestrator**. Each **worker** is a separate
`agy` (Antigravity CLI, Google) process, launched headless via `--print`, run
as an external tool through the Bash tool — not a native Claude subagent.
You always spot-check the worker's claim yourself (cheap); an independent
**Claude subagent** reviewer is reserved for tasks that matter (see Review
Policy) — dispatching a full reviewer for every trivial task is pure
overhead, not safety.

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
│   └── handoff.md           # orchestrator writes: self-check result +
│                             #   verdict, and whether a reviewer was used
└── reviewer_N/               # OPTIONAL — only for tasks that meet the
                               # Review Policy bar below
    ├── BRIEFING.md          # orchestrator writes: what to verify, how
    ├── review.md            # reviewer writes: findings
    └── handoff.md           # reviewer writes: ends with "VERDICT: PASS/FAIL"
```

Real product files go in a sibling `workspace/` dir, never inside `.agents/`
— `.agents/` is dispatch bookkeeping only.

## The Process

0. **Clarify with the human before dispatching anything.** Same discipline
   as `superpowers:brainstorming`/`writing-plans`: if the request leaves
   real room for interpretation — scope ("simple" can mean a bare page or a
   full design system), style/aesthetic, what counts as done, how many
   workers/tabs/whatever — ask before writing `BRIEFING.md`, not after the
   worker returns something the human didn't ask for. Skip this step only
   when the task is already fully specified or is a repeat of a task type
   already clarified earlier in this session. Getting a confidently wrong
   BRIEFING to the worker fast is not faster than getting a right one to it
   five minutes later — the worker's tokens and the review cycle are not
   free, and re-dispatching after a mismatch costs more than asking upfront.
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
4. **Self-check — always, no exceptions, but cheap.** Before writing
   `handoff.md`, YOU (the orchestrator) directly inspect what the worker
   actually produced — `ls`/`cat` the file, run it, diff it, whatever takes
   one or two tool calls. Never accept `agy_raw_output.json`'s `status`
   field alone: it reported `SUCCESS` even the time the file landed in the
   wrong directory entirely (see the `--add-dir` gotcha above). This step
   is not optional and does not need a subagent.
5. **Independent reviewer subagent — only for tasks that meet the bar.**
   Dispatch a Claude subagent (Agent tool) with a `reviewer_N/BRIEFING.md`
   when **any** of these are true:
   - The output will be relied on without the human re-checking it (feeds
     an automated next step, gets committed/shipped, or you'll report it
     done and move on).
   - The task involves non-trivial logic where a plausible-looking wrong
     answer is easy to miss by eyeballing (not just "does the file exist").
   - It's one of the first few dispatches of a new *kind* of task — spend
     the review budget to calibrate whether this task type is reliable
     before trusting it lower-touch.
   - It touches shared/production code or data, or anything costly to
     get wrong.
   - The human explicitly flagged the task as important.

   **Skip the reviewer subagent** (self-check from step 4 is enough) for
   scratch/exploratory work, mechanical tasks you can fully verify yourself
   in one command, and repeat dispatches of a task type that has already
   passed reviewer verification several times with no surprises.

   Don't let "it worked last time" quietly become the excuse to stop
   self-checking too — step 4 never goes away, only step 5 is conditional.

   When used: the reviewer independently inspects the actual workspace
   files and re-runs/re-checks the claim itself — never just re-parses
   `agy_raw_output.json`. Its `handoff.md` must end with `VERDICT: PASS` or
   `VERDICT: FAIL` plus a one-sentence reason.
6. **Gate.** Update `.agents/orchestrator/GATE_STATUS.md` for every worker
   (self-check result, and reviewer verdict if one was dispatched — write
   `reviewer: skipped (self-checked)` when step 5 didn't apply). Only
   report the task done to the human once this line is clean.

## Confidence notes (as of 2026-08-10)

`agy` is a very new CLI (Google, ~May 2026). Community reports (GitHub
`google-antigravity/antigravity-cli#76`) describe `agy --print` producing no
stdout at all on some platforms/versions when stdout isn't a TTY — not
reproduced on this machine, but if a dispatch returns empty output with exit
0, this is the known suspect, not a bug in this skill's script.
