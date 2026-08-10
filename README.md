# agy-orchestrator

Claude Code as orchestrator, [agy](https://antigravity.google) (Antigravity
CLI) headless sessions as external workers — coordinated through a
file-based `.agents/` ledger, reviewed by an independent Claude subagent
before anything is trusted.

## Install on any machine

Requirements: [Claude Code](https://claude.com/claude-code) and
[agy](https://antigravity.google/cli/install) both installed.

```
/plugin marketplace add <this-repo-url>
/plugin install agy-orchestrator@agy-orchestrator-marketplace
```

That's it — the skill `dispatching-to-agy-workers` and its dispatch script
are now available in any Claude Code session on that machine.

## What's in here

- `skills/dispatching-to-agy-workers/` — the skill: SKILL.md (the pattern,
  the `--add-dir` gotcha, the review discipline) + `scripts/dispatch-agy-worker.sh`
  (the actual dispatch wrapper).
- `.agents/` — a real run of the pattern (smoke test: dispatched two agy
  workers, reviewed by a Claude subagent, gated PASS). Kept as a worked
  example.
- `workspace/`, `workspace2/` — the two workers' actual output, for
  reference.

## Why this exists

`agy plugin install` lets *agy itself* run Superpowers-style skills natively
(agy as its own controller + worker via `invoke_subagent`). This plugin is
for the opposite shape: Claude Code stays the controller, and dispatches to
agy as an external, heterogeneous worker over the CLI — useful when you
specifically want agy's models/cost profile doing the execution while Claude
coordinates and reviews.

See `skills/dispatching-to-agy-workers/SKILL.md` for the full pattern.
