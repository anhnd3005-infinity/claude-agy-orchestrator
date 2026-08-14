# agy-orchestrator

Claude Code as orchestrator, CLI agent workers of any
[Herdr](https://herdr.dev)-supported kind (`agy`, `codex`, and in principle
any other kind Herdr recognizes) running interactively inside
Herdr-managed panes — coordinated through a file-based `.agents/` ledger.
Claude clarifies scope before dispatching, always self-checks a worker's
output directly against real files (never trusts a status code alone), and
only spins up an independent reviewer for tasks that meet a stated
importance bar.

## Requirements

- [Claude Code](https://claude.com/claude-code), **running inside a
  Herdr-managed pane** (see step 1 — this is the one thing people miss)
- **Herdr** itself
- At least one worker CLI: **`agy`**, **`codex`**, or another kind `herdr
  agent` supports

## Quick install

### 1. Install Herdr, then run Claude Code *inside* it

Herdr is a hard prerequisite — the skill checks `HERDR_ENV=1` before doing
anything and refuses to run outside a Herdr-managed pane. Installing Herdr
is not enough by itself: **Claude Code has to actually be running inside a
pane Herdr created**, not a plain terminal.

**macOS (Homebrew — official core formula):**
```bash
brew install herdr
brew services start herdr        # keep it running in the background, or:
/opt/homebrew/opt/herdr/bin/herdr server   # run it directly, no service
```

**Other platforms:** see [herdr.dev](https://herdr.dev) for the current
Linux/Windows install steps (not independently verified from this machine,
so no exact command is claimed here).

Then open/attach a Herdr session and start Claude Code **from inside one of
its panes** — e.g. Herdr's own UI, or `herdr session attach <name>`.

✅ **Verify before moving on:**
```bash
herdr --version
echo "$HERDR_ENV"    # must print 1
```
If `$HERDR_ENV` is empty, you're in a plain terminal, not a Herdr pane —
nothing past this point will work until that's fixed.

### 2. Install the worker CLI(s) you'll dispatch to

```bash
# agy (Antigravity CLI, Google)
curl -fsSL https://antigravity.google/cli/install.sh | bash        # macOS/Linux
irm https://antigravity.google/cli/install.ps1 | iex                # Windows PowerShell
curl -fsSL https://antigravity.google/cli/install.cmd -o install.cmd && install.cmd && del install.cmd  # Windows CMD
```

For `codex` or any other kind, install it per its own docs.

✅ **Verify:**
```bash
agy --help                # or the equivalent for your kind
herdr agent               # kinds line should list what you installed
```

On **Windows**, the dispatch script has a pure-Python twin
(`dispatch-herdr-worker.py`) — no WSL or Git Bash needed just for this
plugin.

### 3. Install the plugin

```
/plugin marketplace add https://github.com/anhnd3005-infinity/claude-agy-orchestrator.git
/plugin install agy-orchestrator@agy-orchestrator-marketplace
```

Repo is **public** — no SSH key, no GitHub login needed. (SSH also works if
preferred: `git@github.com:anhnd3005-infinity/claude-agy-orchestrator.git`.)

✅ **Verify:**
```
/plugin
```
should list `agy-orchestrator@agy-orchestrator-marketplace` as enabled.
Works from **any** project on the machine, not just this repo.

### Updating later

New commits land on `main` over time (see Version history at the bottom).
You do **not** need to re-add the marketplace or reinstall from scratch —
two commands:

```
/plugin marketplace update
/plugin update agy-orchestrator@agy-orchestrator-marketplace
```

The first refreshes the marketplace catalog from git (pulls latest
commits); the second actually installs the new version — running only the
first does not update the plugin itself. From a plain terminal instead of
an interactive session (e.g. scripting/CI), use `claude plugin update
agy-orchestrator@agy-orchestrator-marketplace -y` (the `-y` skips the
confirmation prompt; it's required outside an interactive session, ignored
inside one). There's no "update all" — update by plugin name.

✅ **Verify the version landed:** re-run `/plugin` and check the version
number shown against the one in this README's Version history.

### You're set up. Try it:

> "Dùng agy làm worker để tạo file hello.py, chạy thử, rồi báo kết quả cho tôi."

Claude will ask a clarifying question first if anything about scope, style,
"done", or which kind is ambiguous — that's expected, not a bug.

## How to use it

No slash command required — this is a **skill**, Claude pulls it in
automatically when a request matches. Just ask normally:

> "Dispatch this to a codex worker qua Herdr, rồi tự self-check kết quả."

To force it explicitly instead of relying on auto-match:

```
/herdr-dispatch Tạo file X bằng agy, chạy thử, báo kết quả cho tôi.
```

Add "quan trọng"/"important" in the task text to force an independent
reviewer subagent regardless of the normal importance-bar check.

Read `skills/dispatching-to-herdr-workers/SKILL.md` for the full process —
one file, worth reading end to end once.

## How it works
![AI Coding Workflow](./ai_coding_workflow.gif)


*(Under the hood, "dispatch" and "checks the real files" are each a small
sequence of `herdr pane`/`herdr agent` calls with retries and a ledger
written to `.agents/` — see the full step-by-step process in `SKILL.md` if
you want that detail.)*

**The rules that matter most:**
1. **Never trust a status code alone.** Real dispatches caught `agy`
   reporting success while writing to the wrong directory, a fresh pane
   returning `agent_pane_busy`, and `agent_prompt_stalled` firing even when
   the prompt had actually landed — every one only caught by checking the
   real file or pane transcript. Self-check is never skippable, even when
   the reviewer subagent is.
2. Asking "what do you mean by simple" costs one message. Discovering the
   worker overshot scope costs a whole dispatch cycle. Clarify first.
3. **A worker kind is only as trusted as its track record.** `agy` has
   several real dispatches behind it; `codex` or any other kind is new
   integration surface the first time you use it — treat its first
   dispatch like a new task type, not a known quantity.

## Known gotchas

- **No Herdr session → nothing works.** `HERDR_ENV` must be `1`. There is
  no headless fallback.
- **`agy` needs `--add-dir`; other kinds might not.** Handled by a small
  per-kind quirks table in the dispatch scripts — `codex` needs nothing
  extra (reasoned about, not yet dispatch-verified).
- **`--timeout` is capped at 300000 ms (5 min) per call**, hard-rejected
  above that. For longer tasks, loop `herdr agent wait <name> --timeout
  300000` after dispatch instead of raising the number. Exit code `3` means
  exactly this: still working past the timeout, not a failure.
- **`agent_pane_busy` and `agent_prompt_stalled`** can fire right after
  `pane split`/`agent start` even when nothing is actually wrong — both
  scripts retry, and cross-check the real pane transcript before trusting
  any status. Don't hand-roll the `herdr` sequence without one of them.
- **`done` is not safer to trust than `idle`.** Both are "settled" states
  and both have independently produced a false-positive (settled + zero
  error + completely empty pane). The delivery-marker check covers both.
- **Don't drop `--wait`** to dodge a flaky stall error — tested live to be
  worse: herdr reports success immediately with zero signal that delivery
  actually failed.
- **herdr writes errors to stderr, not stdout** — easy to miss when
  scripting your own `herdr` calls.
- **Naive string checks during self-check can false-negative** on content
  split across HTML tags or wrapped terminal lines. Check meaning, not raw
  substrings.
- **A worker doing exactly what it was told can still overshoot intent.**
  That's a step-0 (clarify first) problem, not a step-4 (self-check) one.

Full history and exact repro steps for each of these: `skills/
dispatching-to-herdr-workers/SKILL.md`'s "Lessons from real dispatches" log.

## What's in here

- `skills/dispatching-to-herdr-workers/` — the skill: `SKILL.md` (process,
  per-kind quirks table, review policy, full lessons log) +
  `scripts/dispatch-herdr-worker.sh` / `.py` (behavior-identical dispatch
  wrappers, bash and pure-Python).
- `commands/herdr-dispatch.md` — `/herdr-dispatch <task>`, forces the skill
  instead of relying on auto-match.
- `.agents/`, `workspace/`, `workspace2/` — a real worked-example dispatch,
  kept for reference (see Worked examples below).

## Why this exists

`agy plugin install` lets *agy itself* run Superpowers-style skills
natively. This plugin is the opposite shape: Claude Code stays the
controller, and dispatches to an external, heterogeneous worker over
Herdr — useful when you want a different CLI's models/cost profile doing
execution while Claude coordinates and reviews. Doesn't require Superpowers
either way.

**Note on cost:** not automatically cheaper than asking Claude directly — a
trivial task can cost *more* total tokens across both providers (measured:
~150k tokens on the agy side for a "create hello.py" smoke test). What it
does is shift execution-heavy work off Claude's metered usage onto a
separate provider's quota — a budget-allocation tool, not a
total-cost-reduction one.

## Worked examples

Real dispatches, kept as evidence:

**1. `hello.py` smoke test** (this repo). First-ever dispatch, headless
era. Attempt 1 silently wrote to agy's scratch dir despite reporting
success; attempt 2 (with `--add-dir`) worked and was independently
verified. Produced the `--add-dir` quirk and the ledger convention.

**2. `helloworld-tabs-demo`** (a separate project). Asked for "1 website
đơn giản helloworld." Dispatched without clarifying "đơn giản" first (a
mistake — added step 0 to the process); agy delivered a full
"Premium Dark & Glassmorphism" site, accurate to the letter, well beyond
intended spirit. `grep -i "hello world"` false-negatived on text split
across an HTML tag — manual check found it. Human chose to keep the
over-delivered design; independent reviewer skipped since a human looked
directly.

**3. Herdr-pane migration smoke tests** (`workspace4`–`workspace9`,
cleaned up after). Six live dispatches pressure-testing the new pane mode:
caught `agent_prompt_stalled` producing a false-positive `idle` status,
`agent_pane_busy` right after pane split, herdr writing errors to stderr
(missed by a stdout-only capture), and `agent_prompt_stalled` firing on all
4 retries once even though the task had genuinely completed. Final run:
fully automatic, correct file, correct exit code.

**4. Doc-driven optimization pass** (2026-08-14). Read
[herdr.dev/docs/agent-automation](https://herdr.dev/docs/agent-automation/)
and tested every idea before adopting it: shipped `--timeout` bounds
validation; tested and *rejected* dropping `--wait` (made delivery
detection strictly worse, confirmed live); found a new `timeout`/queued-
prompt error distinct from `agent_prompt_stalled`; caught and fixed a
self-inflicted regression where a delivery-check fix only covered `idle`
and let the identical bug back through under `done`.

All of the above are captured in `SKILL.md`'s "Lessons from real
dispatches" log, so the next dispatch starts from what these already
learned.

## Version history

- **0.4.1** — doc-driven optimization pass (see Worked example 4): timeout
  bounds validation + new `working` exit code (`3`), `--wait`-dropping
  tested and rejected, new `timeout` error documented, `idle`-only
  delivery-check regression found and fixed to cover `done` too.
- **0.4.0** — replaced headless `agy --print` with Herdr-managed
  interactive panes (lifecycle polling, follow-up prompts, live approval
  instead of `--dangerously-skip-permissions`); fixed 3 real races via live
  smoke testing; generalized from agy-only to any Herdr-supported kind via
  a per-kind native-args table; renamed `dispatching-to-agy-workers` →
  `dispatching-to-herdr-workers`, `/agy-dispatch` → `/herdr-dispatch`.
- **0.3.0** — cross-platform dispatch: pure-Python port, no WSL/Git Bash
  required just for this plugin.
- **0.2.0** — step 0 (clarify before dispatching), tiered review policy,
  `/agy-dispatch` slash command.
- **0.1.0** — initial skill: `.agents/` ledger convention, `--add-dir`
  gotcha, mandatory reviewer, dispatch script, self-hosted marketplace.
