---
name: dispatching-to-herdr-workers
description: Use when you want Claude Code to act as orchestrator and dispatch execution tasks to CLI agent workers (agy, codex, or any other Herdr-supported kind) running in persistent Herdr-managed panes, coordinated through a file-based .agents/ ledger.
---

# Dispatching to Herdr Workers

## Overview

Claude Code (you) stays the **orchestrator**. Each **worker** is a CLI
agent of any Herdr-supported kind — `agy` (Antigravity CLI, Google), `codex`,
or any other kind `herdr agent` lists — started interactively inside a real
terminal pane managed by **Herdr**, and driven exclusively through the
`herdr` CLI (`herdr pane ...` / `herdr agent ...`) — not a native Claude
subagent, and not a one-shot headless subprocess. You always spot-check the
worker's claim yourself (cheap); an independent **Claude subagent** reviewer
is reserved for tasks that matter (see Review Policy) — dispatching a full
reviewer for every trivial task is pure overhead, not safety.

This skill was born as `dispatching-to-agy-workers` (agy-only, headless
`agy --print`). It was renamed and generalized (2026-08-13) once the Herdr
pane approach proved out for agy and the need showed up to drive other kinds
(starting with `codex`) through the exact same ledger/process. Read the
Lessons log below — it carries the real, verified-by-testing history of
both the headless→Herdr migration and the agy→multi-kind generalization;
don't re-derive what's already there.

This is a different shape than `superpowers:dispatching-parallel-agents` or
`superpowers:subagent-driven-development`: those dispatch *native,
homogeneous* subagents inside one harness (Claude's Task tool). Here the
controller and the worker are **separate CLIs**, coordinated through
Herdr's pane/agent layer plus the filesystem — use this skill specifically
when you want a different CLI's own models/cost-profile to do the execution
work while Claude does the coordination and review.

## Hard prerequisite: Herdr

This skill requires a live Herdr session. Before anything else:

```bash
test "${HERDR_ENV:-}" = 1
```

If that fails, **stop and say so explicitly** — do not fall back to a
headless subprocess, and do not silently do the task yourself in Claude
instead. Herdr-managed panes are the only supported dispatch path, because
they're what makes lifecycle polling (`idle`/`working`/`blocked`/`done`),
mid-task follow-up prompts, and live approval flows possible at all.

Also required: `herdr`, `jq`, and the target kind's own CLI on `PATH`, with
that kind present in `herdr agent`'s supported list (run `herdr agent` to
see it — at last check: `pi|claude|codex|gemini|cursor|devin|agy|cline|omp
|mastracode|opencode|copilot|kimi|kiro|droid|amp|grok|hermes|kilo|qodercli
|maki`).

**Only `agy` and `codex` have actually been exercised against this skill's
scripts.** Any other kind will run, but treat its first few dispatches like
"a new kind of task" under the Review Policy below — its startup timing,
error codes, and workspace-scoping needs haven't been verified the way
agy's and codex's have. See "Per-kind quirks" below for how to add one once
you've verified it.

## When to Use

- You explicitly want a specific CLI's own models/cost-profile to execute a
  task while Claude coordinates, reviews, and decides next steps.
- The task benefits from a persistent worker: long-running work you want to
  poll instead of block on, work that may need a follow-up prompt without
  losing context, or work where the worker may ask a question or need
  approval mid-task (the pane stays alive, so you resolve it interactively
  instead of needing to skip permissions).

**Don't use when:** you're not inside a Herdr session (see Hard prerequisite
above), or the task is naturally a Claude subagent's job — don't reach for
an external CLI just because you can.

## Per-kind quirks

Different kinds may need different treatment to scope a worker to the right
workspace. The dispatch scripts keep a small table (`KIND_NATIVE_ARGS` in
the Python script, a `case "$KIND"` block in the bash script) of extra
native args to pass at `herdr agent start ... -- <native-args>` time:

| Kind    | Extra native args                | Why |
|---------|-----------------------------------|-----|
| `agy`   | `--add-dir <absolute-workspace>`  | agy does **not** reliably use its launching cwd as its workspace — without this it may silently write into its own `~/.gemini/antigravity-cli/scratch/` while still reporting success. Verified empirically (2026-08-10). |
| `codex` | *(none)*                          | No such quirk found so far — `pane split --cwd` alone has been sufficient in testing. |
| *(any other kind)* | *(none, default)*     | Untested. If a kind silently writes to the wrong place or otherwise misbehaves, verify against real files first, then add a table entry — same discipline that caught the agy quirk. Never add an entry on assumption alone. |

Regardless of kind, **always** also repeat the absolute workspace path
inside the prompt text itself (the dispatch scripts already do this) — belt
and suspenders, since a model can still choose to write elsewhere even when
correctly scoped.

Use `scripts/dispatch-herdr-worker.sh` (macOS/Linux/Git-Bash/WSL) or
`scripts/dispatch-herdr-worker.py` (Windows, or anywhere Python is
preferred) for the deterministic happy path — either one bakes in the
per-kind table above, plus the pane split / agent start / first prompt /
read sequence below. Pick whichever runs on the orchestrating machine; never
hand-roll the `herdr` invocation sequence without one of them, except when
resolving a `blocked` worker (see step 2b — that part is inherently
interactive and not scriptable).

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
├── worker_<kind>_N/              # e.g. worker_agy_1, worker_codex_2
│   ├── BRIEFING.md              # orchestrator writes: role, task, constraints
│   ├── DISPATCH.md              # auto-written by dispatch-herdr-worker.sh:
│   │                             #   kind, pane_id, agent_name, commands used
│   ├── herdr_pane_split.json     # auto-written: raw `herdr pane split` response
│   ├── herdr_agent_start.json    # auto-written: raw `herdr agent start` response
│   ├── herdr_agent_prompt.json   # auto-written: raw `herdr agent prompt` response
│   ├── herdr_agent_get.json      # auto-written: raw `herdr agent get` response (status)
│   ├── agent_output.txt          # auto-written: `herdr agent read` terminal snapshot
│   ├── progress.md               # auto-written; worker's self-reported status + blocked notes
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
   workers/tabs/whatever, **which kind to use if not specified** — ask
   before writing `BRIEFING.md`, not after the worker returns something the
   human didn't ask for. Skip this step only when the task is already fully
   specified or is a repeat of a task type already clarified earlier in
   this session. Getting a confidently wrong BRIEFING to the worker fast is
   not faster than getting a right one to it five minutes later — the
   worker's tokens and the review cycle are not free, and re-dispatching
   after a mismatch costs more than asking upfront.
1. **Brief the worker.** Write `.agents/worker_<kind>_N/BRIEFING.md`: exact
   task, constraints ("only touch files under `workspace/`"), expected
   output. Also pick a unique Herdr agent name (`[a-z][a-z0-9_-]{0,31}`,
   e.g. `worker_agy_2`, `worker_codex_1`) — check it's not already live
   with `herdr agent list`.
2. **Dispatch.** macOS/Linux/Git-Bash/WSL:
   ```bash
   skills/dispatching-to-herdr-workers/scripts/dispatch-herdr-worker.sh \
     <absolute-workspace-path> \
     .agents/worker_<kind>_N \
     "<task prompt>" \
     <agent_name> \
     <kind> \
     [timeout_ms, default 300000]
   ```
   Windows (native cmd/PowerShell, no bash needed) or wherever Python is
   preferred — same arguments, same output files:
   ```bash
   python3 skills/dispatching-to-herdr-workers/scripts/dispatch-herdr-worker.py \
     <absolute-workspace-path> \
     .agents/worker_<kind>_N \
     "<task prompt>" \
     <agent_name> \
     <kind> \
     [timeout_ms, default 300000]
   ```
   Under the hood this runs, in order: `herdr pane split --current
   --direction right --cwd <workspace> --no-focus`, then `herdr agent start
   <agent_name> --kind <kind> --pane <pane_id> -- <per-kind native args>`,
   then `herdr agent prompt <agent_name> "<task, workspace path repeated>"
   --wait --timeout <timeout_ms>`, then `herdr agent get` + `herdr agent
   read` to capture the settled status and terminal output — with the
   delivery-confirmation check from the Lessons log applied before trusting
   any of it. It writes `DISPATCH.md`, `progress.md`, the raw `herdr_*.json`
   responses, and `agent_output.txt`. Exit code: `0` = settled idle/done,
   `2` = settled blocked, `1` = no delivery confirmed / unknown / error —
   check the exit code, don't just assume success.

   2b. **If the worker comes back `blocked`** (a question, an approval
   request, etc.), the script has already stopped — it will not resolve
   this for you. Take over interactively:
   ```bash
   herdr agent read <agent_name> --source recent-unwrapped --lines 120
   ```
   to see what it's waiting on, then either
   `herdr agent send-keys <agent_name> <key>` for a UI control (e.g. an
   approval dialog) or `herdr agent prompt <agent_name> "<answer>" --wait
   --timeout <ms>` for a text answer. Repeat until it settles idle/done.
   Log what happened in `progress.md` before moving on.

   2c. **If the script exits with `no_delivery_confirmed`,** don't assume
   the task genuinely failed — this status exists precisely because the
   underlying error code that would normally mean "never delivered" has
   been observed to be wrong before (see Lessons log). Inspect
   `agent_output.txt` yourself: if the prompt text is visibly in the
   transcript and the agent is working/done, it landed — the automated
   marker check missed it (e.g. an even-more-unusual wrap pattern) and you
   can proceed with self-check as normal. If the pane is genuinely empty
   past the banner, it really didn't land — retry manually via
   `herdr agent prompt`.
3. **Never dispatch two workers at the same absolute workspace path
   concurrently** — same reasoning as never running two implementers on the
   same files in `subagent-driven-development`: conflicting writes, no lock.
   Also never reuse a live agent name — check `herdr agent list` first.
4. **Self-check — always, no exceptions, but cheap.** Before writing
   `handoff.md`, YOU (the orchestrator) directly inspect what the worker
   actually produced — `ls`/`cat` the file, run it, diff it, whatever takes
   one or two tool calls. Never accept a settled `idle`/`done` status alone:
   it has reported success even when the file landed in the wrong directory
   entirely, or was never actually created (see the Lessons log — twice).
   This step is not optional and does not need a subagent.
5. **Independent reviewer subagent — only for tasks that meet the bar.**
   Dispatch a Claude subagent (Agent tool) with a `reviewer_N/BRIEFING.md`
   when **any** of these are true:
   - The output will be relied on without the human re-checking it (feeds
     an automated next step, gets committed/shipped, or you'll report it
     done and move on).
   - The task involves non-trivial logic where a plausible-looking wrong
     answer is easy to miss by eyeballing (not just "does the file exist").
   - It's one of the first few dispatches of a new *kind* of task, OR a
     new agent *kind* you haven't run through this skill before — spend
     the review budget to calibrate whether it's reliable before trusting
     it lower-touch.
   - It touches shared/production code or data, or anything costly to
     get wrong.
   - The human explicitly flagged the task as important.

   **Skip the reviewer subagent** (self-check from step 4 is enough) for
   scratch/exploratory work, mechanical tasks you can fully verify yourself
   in one command, and repeat dispatches of a task type (and kind) that has
   already passed reviewer verification several times with no surprises.

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
7. **Cleanup.** You created the worker's pane, so you may close it
   (`herdr pane close <pane_id>`) once its `handoff.md` is written and no
   follow-up is expected — but leaving it alive costs nothing and preserves
   the ability to send one more prompt if review turns up a gap. Never
   close a pane or kill an agent you did not create.

## Lessons from real dispatches (running log)

Append to this list when a dispatch teaches you something non-obvious —
that's the point of keeping this skill in one file instead of re-learning
it every session.

- **2026-08-10, hello.py smoke test (agy, headless era):** `agy --print`
  without `--add-dir` reported `SUCCESS` while writing into its own scratch
  dir, not the workspace asked for. → the `--add-dir` quirk in the Per-kind
  quirks table above; scripts bake it in via `agent start ... --
  --add-dir <path>`.
- **2026-08-10, cross-platform:** the dispatch script is bash-only in one
  form — doesn't run on native Windows (cmd/PowerShell) without WSL or Git
  Bash. Added a behavior-identical Python port. Pick by platform, not by
  habit.
- **2026-08-10, helloworld-tabs-demo (agy, headless era):** two more lessons
  from one dispatch:
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
- **2026-08-13, migration to Herdr-managed panes (agy):** replaced the
  headless `agy --print --dangerously-skip-permissions` mode entirely.
  Motivation: a one-shot subprocess can't be polled mid-task, can't take a
  follow-up prompt without a fresh full relaunch, and forced
  `--dangerously-skip-permissions` because nothing was present to answer an
  approval prompt. A Herdr-managed pane fixes all three: `herdr agent get`
  gives live `idle`/`working`/`blocked`/`done` status, `herdr agent prompt`
  can be called again on the same live agent, and a `blocked` status means
  an approval/question is genuinely waiting for the orchestrator to answer
  rather than being silently skipped. Tradeoff: this skill now hard-depends
  on running inside a Herdr session — no more headless/CI fallback.
- **2026-08-13, smoke test caught a real race (agy):** the very first
  `agent prompt --wait` sent immediately after `agent start` failed with
  `{"error":{"code":"agent_prompt_stalled",...}}` even though `agent get`
  reported `interactive_ready: true` and `agent_status: idle`. The prompt
  text never reached the pane (`state_change_seq` didn't move, box stayed
  empty) — but the script's old logic just read the post-prompt status as
  `idle` and reported success, which would have been a **false-positive**:
  no file was actually created. A manual retry of the exact same `agent
  prompt --wait` call one attempt later worked immediately and produced
  correct output. Fix: scripts retry up to 4 times with a 3s delay whenever
  the response's `error.code` is `agent_prompt_stalled`, and only read the
  settled status after a non-stalled response. **Never treat
  `agent_prompt_stalled` as "the agent had nothing to do" — it means the
  prompt was never delivered; retry, don't skip.**
- **2026-08-13, two more races in the same smoke test (agy, but the first
  two are Herdr-level, not agy-specific):** (a) calling `herdr agent start`
  immediately after `herdr pane split` can hit `{"error":{"code":
  "agent_pane_busy","message":"... is not an available shell"}}` — the pane
  isn't an available shell yet even with no agent attached. Fixed the same
  way: retry with a short delay. (b) **herdr writes server errors as JSON
  to stderr, not stdout** (this is documented behavior, easy to miss) — a
  naive `"$(herdr ...)"` capture only sees stdout, so error-code-based retry
  logic silently never fires unless stderr is captured too. Both scripts
  capture stderr explicitly for every retryable call. (c) Even after fixing
  (b), `agent_prompt_stalled` itself turned out unreliable: on one dispatch
  it fired on **all 4** retry attempts, yet the prompt had actually landed
  on the first attempt and the task completed correctly — the error is a
  heuristic, not a reliable non-delivery signal. Fix: after the retry loop,
  check the pane transcript itself (`herdr agent read`) for the fixed
  prompt-template marker text ("Trong thư mục tuyệt đối...", present in
  every prompt this skill sends regardless of task content or kind) before
  trusting any status. No marker in the transcript → force status to
  `no_delivery_confirmed` and refuse to report success, no matter what
  `agent get` says. Lesson underneath all three: **when a new integration's
  error/status codes haven't been battle-tested, verify against the actual
  artifact (pane text, file contents) — never chain trust through an
  unverified status string, even in the "fixed" version of a script.**
  Because (a) and (b) are Herdr CLI behaviors, not agy behaviors, they were
  assumed to transfer to other kinds without re-verification when this
  skill was generalized — but that assumption itself hasn't been tested
  yet; treat it as a hypothesis, not a fact, until a codex (or other kind)
  dispatch actually confirms it.
- **2026-08-13, generalized beyond agy to any Herdr-supported kind:** added
  a `kind` parameter and the Per-kind quirks table above, so this skill
  (renamed from `dispatching-to-agy-workers`) can drive `codex` and, in
  principle, any other kind `herdr agent` supports. `codex` has no known
  workspace-scoping quirk yet (default: none) — but as of this rename it
  has **not yet been exercised in a real dispatch** through this skill, only
  reasoned about. Treat the first codex dispatch (and the first dispatch of
  any other new kind) like "a new kind of task" under the Review Policy:
  verify against real files, and update the quirks table and this log with
  whatever you actually observe — don't assume codex behaves like agy, and
  don't assume it behaves perfectly cleanly either.
- **2026-08-14, read https://herdr.dev/docs/agent-automation/ and tested
  every idea it suggested before adopting any of it:**
  - **`--timeout` is hard-bounded to `(3000, 300000]` ms.** Herdr rejects
    values outside that range rather than clamping. Our old default
    (300000) sits exactly at the ceiling, which is fine, but nothing
    stopped a caller from passing something bigger and getting a cryptic
    failure. Both scripts now validate `timeout_ms` and
    `HERDR_START_TIMEOUT_MS` up front and fail with a clear message. **For
    genuinely long tasks, there is no bigger single-call timeout to reach
    for** — loop `herdr agent wait <agent_name> --timeout 300000` instead
    of trying to raise this value.
  - **Tested and rejected: dropping `--wait` to dodge `agent_prompt_stalled`.**
    Hypothesis was that decoupling submission (`agent prompt` without
    `--wait`) from waiting (`agent wait` separately) would avoid the
    5-second-no-change stall check that's produced false failures before.
    Live test: `agent prompt <name> "<text>"` (no `--wait`) returned
    `{"...":"agent_prompted"}` — reporting success — **while the pane was
    still on agy's startup/account-check screen and the text never landed
    at all.** Without `--wait`, herdr gives zero feedback that delivery
    failed; it's strictly worse than the current retry+marker-check
    approach, not better. Kept `--wait`. Recorded here so nobody
    "optimizes" this away again without re-testing it first.
  - **New error code found: `{"error":{"code":"timeout","message":"timed
    out waiting for agent status"}}`**, distinct from
    `agent_prompt_stalled`. Observed when the target agent was already mid
    an unrelated task: the new prompt gets silently **queued** (visible in
    the transcript as a `▸ ...` line under "Press up to edit queued
    messages") instead of running immediately, and `--wait` can genuinely
    time out waiting for the queue to clear — this is a real "still busy"
    condition, not a delivery failure, and should not be blindly retried
    the way `agent_pane_busy`/`agent_prompt_stalled` are. Relevant mainly
    to step 2b (sending a follow-up prompt to an *existing* agent): check
    `herdr agent get <name>` is `idle` first, or expect your follow-up to
    queue behind whatever it's already doing.
  - **The idle/done false-positive isn't unique to `idle`.** A follow-up
    smoke test hit the *exact* original bug again, but this time settled
    as `done`: `agent prompt --wait` returned success with a bumped
    `state_change_seq` and no error at all, `agent get` reported `done`,
    and the pane transcript was still completely empty — nothing was ever
    typed. An earlier revision of the delivery-marker fix only re-checked
    the marker when `status == idle`, on the theory that `done` implies
    real completion; that theory was wrong and let this exact
    false-positive back through. Fixed by applying the marker check to
    **both** `idle` and `done` (herdr's own docs describe `done` as "the
    same underlying idle state after unseen background work finishes" —
    it was never a materially different state to begin with). Lesson on
    top of the lesson: a "fix" narrowed from a broader, already-verified
    check is itself a new claim that needs its own live re-test — it isn't
    grandfathered in by the original fix's testing.
  - Net result of this reading-and-testing pass: one genuine improvement
    shipped (timeout bounds), one plausible optimization tested and
    correctly discarded (dropping `--wait`), one new error class
    documented but intentionally not auto-retried (`timeout`/queued), and
    one self-inflicted regression caught and fixed before it reached
    main (`idle`-only marker scoping). All four came from combining the
    doc with live dispatches — reading the doc alone would have shipped
    the regression.

## Confidence notes (as of 2026-08-13)

`agy` is a very new CLI (Google, ~May 2026). Community reports (GitHub
`google-antigravity/antigravity-cli#76`) describe `agy --print` producing no
stdout at all on some platforms/versions when stdout isn't a TTY — this was
the known suspect for empty-output headless dispatches; it does not apply
under the current Herdr-pane mode since agy now runs fully interactively
with its own real TTY inside the pane, not through a piped subprocess.

Herdr's exact `agent get`/`agent prompt` JSON response shapes are new
integration surface for this skill — the dispatch scripts extract fields
defensively (recursive key search rather than a fixed JSON path)
specifically because that shape hasn't been battle-tested across many
dispatches or across kinds yet. Treat the first several dispatches of any
given kind like the "first few dispatches of a new kind of task" case in
the Review Policy above — this applies doubly to any kind beyond `agy` and
`codex`, which have zero and one real verified dispatch respectively as of
this rename.
