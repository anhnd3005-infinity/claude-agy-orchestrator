---
name: dispatching-to-agy-workers
description: Use when you want Claude Code to act as orchestrator and dispatch execution tasks to agy (Antigravity CLI) workers running in persistent Herdr-managed panes, coordinated through a file-based .agents/ ledger.
---

# Dispatching to agy Workers

## Overview

Claude Code (you) stays the **orchestrator**. Each **worker** is a separate
`agy` (Antigravity CLI, Google) agent, started interactively inside a real
terminal pane managed by **Herdr**, and driven exclusively through the
`herdr` CLI (`herdr pane ...` / `herdr agent ...`) — not a native Claude
subagent, and no longer a one-shot headless `agy --print` subprocess.
You always spot-check the worker's claim yourself (cheap); an independent
**Claude subagent** reviewer is reserved for tasks that matter (see Review
Policy) — dispatching a full reviewer for every trivial task is pure
overhead, not safety.

This is a different shape than `superpowers:dispatching-parallel-agents` or
`superpowers:subagent-driven-development`: those dispatch *native, homogeneous*
subagents inside one harness (Claude's Task tool, or agy's own
`invoke_subagent` if agy itself is the controller). Here the controller and
the worker are **two different CLIs**, coordinated through Herdr's pane/agent
layer plus the filesystem — use this skill specifically when you want agy
(its models, its cost profile) to do the execution work while Claude does
the coordination and review.

## Hard prerequisite: Herdr

This skill requires a live Herdr session. Before anything else:

```bash
test "${HERDR_ENV:-}" = 1
```

If that fails, **stop and say so explicitly** — do not fall back to headless
`agy --print`, and do not silently do the task yourself in Claude instead.
This skill previously supported a headless `agy --print` mode; that mode is
gone. Herdr-managed panes are the only supported dispatch path now, because
they're what makes lifecycle polling (`idle`/`working`/`blocked`/`done`),
mid-task follow-up prompts, and live approval flows possible at all.

Also required: `herdr` and `agy` on `PATH`, and `agy` present in `herdr
agent`'s supported kind list (check with `herdr agent` — kinds line lists
`agy` alongside `claude`, `codex`, `gemini`, etc.).

## When to Use

- You explicitly want an `agy` session to execute a task (e.g. to use its
  Gemini-family models, or to keep execution cost/tokens off the Claude
  session) while Claude coordinates, reviews, and decides next steps.
- The task benefits from a persistent worker: long-running work you want to
  poll instead of block on, work that may need a follow-up prompt without
  losing context, or work where agy may ask a question or need approval
  mid-task (the pane stays alive, so you resolve it interactively instead of
  needing `--dangerously-skip-permissions`).

**Don't use when:** you're not inside a Herdr session (see Hard prerequisite
above), or the task is naturally a Claude subagent's job — don't reach for
agy just because you can.

## The one gotcha that will bite you

agy does **not** use its launching process's cwd as its workspace. Without
`--add-dir <absolute-path>`, it may silently write files into its own
`~/.gemini/antigravity-cli/scratch/` instead of your intended directory —
**while still reporting `"status":"SUCCESS"`**. Verified empirically
(2026-08-10, under the old headless mode; the underlying agy behavior is
unchanged under Herdr).

**Always:**
1. Pass `--add-dir <absolute-path-to-workspace>` as a **native agy arg** when
   starting the agent: `herdr agent start ... --kind agy --pane <id> --
   --add-dir <absolute-path>` (everything after `--` goes straight to agy).
2. Repeat that same absolute path inside the prompt text itself.
3. Never trust a status string alone — always self-check the actual
   workspace files yourself (step 4 below), and have an independent
   reviewer check for tasks that meet the Review Policy bar.

Use `scripts/dispatch-agy-worker.sh` (macOS/Linux/Git-Bash/WSL) or
`scripts/dispatch-agy-worker.py` (Windows, or anywhere Python is preferred)
for the deterministic happy path — either one bakes in (1) and (2), plus the
pane split / agent start / first prompt / read sequence below. Pick whichever
runs on the orchestrating machine; never hand-roll the `herdr` invocation
sequence without one of them, except when resolving a `blocked` worker
(see step 2b — that part is inherently interactive and not scriptable).

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
│   ├── BRIEFING.md              # orchestrator writes: role, task, constraints
│   ├── DISPATCH.md              # auto-written by dispatch-agy-worker.sh:
│   │                             #   pane_id, agent_name, commands used
│   ├── herdr_pane_split.json     # auto-written: raw `herdr pane split` response
│   ├── herdr_agent_start.json    # auto-written: raw `herdr agent start` response
│   ├── herdr_agent_prompt.json   # auto-written: raw `herdr agent prompt` response
│   ├── herdr_agent_get.json      # auto-written: raw `herdr agent get` response (status)
│   ├── agent_output.txt          # auto-written: `herdr agent read` terminal snapshot
│   ├── progress.md               # auto-written; agy's self-reported status + blocked notes
│   └── handoff.md                # orchestrator writes: self-check result +
│                                  #   verdict, and whether a reviewer was used
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
   Also pick a unique Herdr agent name (`[a-z][a-z0-9_-]{0,31}`, e.g.
   `worker_agy_2`) — check it's not already live with `herdr agent list`.
2. **Dispatch.** macOS/Linux/Git-Bash/WSL:
   ```bash
   skills/dispatching-to-agy-workers/scripts/dispatch-agy-worker.sh \
     <absolute-workspace-path> \
     .agents/worker_agy_N \
     "<task prompt>" \
     <agent_name> \
     [timeout_ms, default 300000]
   ```
   Windows (native cmd/PowerShell, no bash needed) or wherever Python is
   preferred — same arguments, same output files:
   ```bash
   python3 skills/dispatching-to-agy-workers/scripts/dispatch-agy-worker.py \
     <absolute-workspace-path> \
     .agents/worker_agy_N \
     "<task prompt>" \
     <agent_name> \
     [timeout_ms, default 300000]
   ```
   Under the hood this runs, in order: `herdr pane split --current
   --direction right --cwd <workspace> --no-focus`, then `herdr agent start
   <agent_name> --kind agy --pane <pane_id> -- --add-dir <workspace>`, then
   `herdr agent prompt <agent_name> "<task, workspace path repeated>" --wait
   --timeout <timeout_ms>`, then `herdr agent get` + `herdr agent read` to
   capture the settled status and terminal output. It writes `DISPATCH.md`,
   `progress.md`, the raw `herdr_*.json` responses, and `agent_output.txt`.
   Exit code: `0` = settled idle/done, `2` = settled blocked, `1` =
   unknown/error — check the exit code, don't just assume success.

   2b. **If the worker comes back `blocked`** (agy asked a question, wants
   approval, etc.), the script has already stopped — it will not resolve
   this for you. Take over interactively:
   ```bash
   herdr agent read <agent_name> --source recent-unwrapped --lines 120
   ```
   to see what it's waiting on, then either
   `herdr agent send-keys <agent_name> <key>` for a UI control (e.g. an
   approval dialog) or `herdr agent prompt <agent_name> "<answer>" --wait
   --timeout <ms>` for a text answer. Repeat until it settles idle/done.
   Log what happened in `progress.md` before moving on.
3. **Never dispatch two agy workers at the same absolute workspace path
   concurrently** — same reasoning as never running two implementers on the
   same files in `subagent-driven-development`: conflicting writes, no lock.
   Also never reuse a live agent name — check `herdr agent list` first.
4. **Self-check — always, no exceptions, but cheap.** Before writing
   `handoff.md`, YOU (the orchestrator) directly inspect what the worker
   actually produced — `ls`/`cat` the file, run it, diff it, whatever takes
   one or two tool calls. Never accept a settled `idle`/`done` status alone:
   it reported `SUCCESS`-equivalent even the time the file landed in the
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
   files and re-runs/re-checks the claim itself — never just re-parses the
   herdr JSON responses. Its `handoff.md` must end with `VERDICT: PASS` or
   `VERDICT: FAIL` plus a one-sentence reason.
6. **Gate.** Update `.agents/orchestrator/GATE_STATUS.md` for every worker
   (self-check result, and reviewer verdict if one was dispatched — write
   `reviewer: skipped (self-checked)` when step 5 didn't apply). Only
   report the task done to the human once this line is clean.
7. **Cleanup.** You created the worker's pane, so you may close it once its
   `handoff.md` is written and no follow-up is expected — but leaving it
   alive costs nothing and preserves the ability to send one more prompt if
   review turns up a gap. Never close a pane or kill an agent you did not
   create.

## Lessons from real dispatches (running log)

Append to this list when a dispatch teaches you something non-obvious —
that's the point of keeping this skill in one file instead of re-learning
it every session.

- **2026-08-10, hello.py smoke test:** `agy --print` without `--add-dir`
  reported `SUCCESS` while writing into its own scratch dir, not the
  workspace asked for. → the `--add-dir` gotcha above; scripts now bake it
  in via `agent start ... -- --add-dir <path>`.
- **2026-08-10, cross-platform:** the dispatch script is bash-only in one
  form — doesn't run on native Windows (cmd/PowerShell) without WSL or Git
  Bash. Added a behavior-identical Python port. Pick by platform, not by
  habit.
- **2026-08-10, helloworld-tabs-demo:** two more lessons from one dispatch:
  - **Self-check with a naive substring match can false-negative.**
    Grepping the produced HTML for the literal string "Hello World" found
    nothing, because the worker had written
    `<h1>Hello <span class="gradient-text">World!</span></h1>` — the text
    was real and correctly displayed, just split by a tag. Self-check for
    *rendered/semantic* content, not raw substrings, before concluding
    something is missing.
  - **"SUCCESS" can hide scope creep, not just wrong location.** Asked for
    a "simple" hello-world page; got a full "Premium Dark & Glassmorphism"
    design system with an external CDN dependency (Google Fonts, Font
    Awesome) nobody asked for. Nothing was *broken* — the reported status
    was accurate this time — but the result didn't match intent. This is
    exactly what step 0 (clarify first) exists to prevent, and exactly
    what self-check should flag even when the worker's own report reads
    clean: note surprises (unrequested dependencies, scope beyond the
    brief), not just pass/fail.
  - When asked, the human owns the final call on both directions: keep an
    over-delivered result as-is, or skip a reviewer step the policy would
    otherwise recommend. Record whichever they choose in `handoff.md` /
    `GATE_STATUS.md` — don't let an explicit human decision look like a
    process gap on paper later.
- **2026-08-13, migration to Herdr-managed panes:** replaced the headless
  `agy --print --dangerously-skip-permissions` mode entirely. Motivation: a
  one-shot subprocess can't be polled mid-task, can't take a follow-up
  prompt without a fresh full relaunch, and forced
  `--dangerously-skip-permissions` because nothing was present to answer an
  approval prompt. A Herdr-managed pane fixes all three: `herdr agent get`
  gives live `idle`/`working`/`blocked`/`done` status, `herdr agent prompt`
  can be called again on the same live agent, and a `blocked` status means
  an approval/question is genuinely waiting for the orchestrator to answer
  rather than being silently skipped. Tradeoff: this skill now hard-depends
  on running inside a Herdr session — no more headless/CI fallback.
- **2026-08-13, smoke test caught a real race:** the very first `agent
  prompt --wait` sent immediately after `agent start` failed with
  `{"error":{"code":"agent_prompt_stalled",...}}` even though `agent get`
  reported `interactive_ready: true` and `agent_status: idle`. The prompt
  text never reached the pane (`state_change_seq` didn't move, box stayed
  empty) — but the script's old logic just read the post-prompt status as
  `idle` and reported success, which would have been a **false-positive**:
  no file was actually created. A manual retry of the exact same `agent
  prompt --wait` call one attempt later worked immediately and produced
  correct output. Fix: both scripts now retry up to 4 times with a 3s delay
  whenever the response's `error.code` is `agent_prompt_stalled`, and only
  read the settled status after a non-stalled response. **Never treat
  `agent_prompt_stalled` as "the agent had nothing to do" — it means the
  prompt was never delivered; retry, don't skip.**
- **2026-08-13, two more races in the same smoke test:** (a) calling
  `herdr agent start` immediately after `herdr pane split` can hit
  `{"error":{"code":"agent_pane_busy","message":"... is not an available
  shell"}}` — the pane isn't an available shell yet even with no agent
  attached. Fixed the same way: retry with a short delay. (b) **herdr
  writes server errors as JSON to stderr, not stdout** (this is documented
  behavior, easy to miss) — a naive `"$(herdr ...)"` capture only sees
  stdout, so error-code-based retry logic silently never fires unless
  stderr is captured too. Both scripts now capture stderr explicitly for
  every retryable call. (c) Even after fixing (b), `agent_prompt_stalled`
  itself turned out unreliable: on one dispatch it fired on **all 4** retry
  attempts, yet the prompt had actually landed on the first attempt and the
  task completed correctly — the error is a heuristic, not a reliable
  non-delivery signal. Fix: after the retry loop, check the pane transcript
  itself (`herdr agent read`) for the fixed prompt-template marker text
  ("Trong thư mục tuyệt đối...", present in every prompt this skill sends
  regardless of task content) before trusting any status. No marker in the
  transcript → force status to `no_delivery_confirmed` and refuse to
  report success, no matter what `agent get` says. Lesson underneath all
  three: **when a new integration's error/status codes haven't been
  battle-tested, verify against the actual artifact (pane text, file
  contents) — never chain trust through an unverified status string, even
  in the "fixed" version of a script.**

## Confidence notes (as of 2026-08-13)

`agy` is a very new CLI (Google, ~May 2026). Community reports (GitHub
`google-antigravity/antigravity-cli#76`) describe `agy --print` producing no
stdout at all on some platforms/versions when stdout isn't a TTY — this was
the known suspect for empty-output headless dispatches; it does not apply
under the current Herdr-pane mode since agy now runs fully interactively
with its own real TTY inside the pane, not through a piped subprocess.

Herdr's `agy` kind support and its exact `agent get`/`agent prompt` JSON
response shapes are new integration surface as of this migration (2026-08-13)
— the dispatch scripts extract fields defensively (recursive key search
rather than a fixed JSON path) specifically because that shape hasn't been
battle-tested across many dispatches yet. Treat the first several
Herdr-mode dispatches like the "first few dispatches of a new kind of task"
case in the Review Policy above.
