#!/usr/bin/env python3
"""Cross-platform twin of dispatch-agy-worker.sh --- same behavior, no bash
required. Use this on Windows (native cmd/PowerShell, no WSL/Git Bash
needed) or anywhere Python is preferred over a shell script.

Dispatch one task to an agy (Antigravity CLI) worker running INSIDE a
Herdr-managed pane, and record a DISPATCH.md/progress.md scaffold for a
.agents/ file-based orchestration.

Replaces the old headless `agy --print` approach entirely: the worker now
lives in a real, persistent Herdr pane, so the orchestrator can poll its
lifecycle (idle/working/blocked/done), read its terminal output, and send
follow-up prompts without relaunching anything.

Usage:
    python3 dispatch-agy-worker.py <workspace_abs_path> <agent_record_dir> <prompt> <agent_name> [timeout_ms]

    workspace_abs_path   Absolute path the worker is allowed to read/write.
                         Passed to agy's own --add-dir (via
                         `agent start ... -- --add-dir <path>`) AND repeated
                         inside the prompt --- agy does NOT use the
                         launching process's cwd as its workspace; without
                         --add-dir it silently writes into its own scratch
                         dir while still reporting status: SUCCESS.
    agent_record_dir      Where to write DISPATCH.md, progress.md, and the
                         raw herdr JSON responses (e.g. .agents/worker_agy_2/).
    prompt                Task text. The workspace path is prefixed
                         automatically.
    agent_name            Unique Herdr agent name for this worker (must
                         match [a-z][a-z0-9_-]{0,31}, unique among live
                         agents). Used to target every later
                         `herdr agent ...` call.
    timeout_ms            Optional, default 300000 (5m). Passed to
                         `herdr agent prompt --timeout`.

Requires: HERDR_ENV=1 (this must run from inside a Herdr-managed pane),
`herdr` on PATH, and `agy` installed as a Herdr-recognized agent kind
(`herdr agent` lists supported kinds; `agy` is one of them).

This script only does the deterministic happy path: split pane, start
agent, send the first prompt, wait for it to settle, read the result. If
the worker ends up `blocked` (agy asking a question, an approval prompt,
etc.), this script does NOT try to resolve that --- it reports the blocked
status and exits 2. The orchestrator must then take over interactively via
`herdr agent read/send-keys/prompt <agent_name>`.
"""

import json
import os
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


def fail(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def find_key(obj, key):
    """Recursive-descent search for the first occurrence of `key` anywhere
    in a parsed JSON tree --- doesn't depend on knowing herdr's exact
    response nesting, just that the key exists somewhere."""
    if isinstance(obj, dict):
        if key in obj:
            return obj[key]
        for v in obj.values():
            found = find_key(v, key)
            if found is not None:
                return found
    elif isinstance(obj, list):
        for item in obj:
            found = find_key(item, key)
            if found is not None:
                return found
    return None


def run_herdr(args, record_dir, out_name):
    """Run a herdr subcommand, save its raw response as JSON, return (rc, parsed_or_None).

    herdr writes server errors as JSON to STDERR with exit status 1 (per
    the herdr skill docs), not stdout --- on success the JSON is on
    stdout. Prefer whichever stream is non-empty so an error body is never
    silently missed (bit us in the 2026-08-13 smoke test: an
    `agent_prompt_stalled`/`agent_pane_busy` error on stderr was ignored
    because only stdout was parsed, so the retry logic below never fired).
    """
    proc = subprocess.run(args, capture_output=True, text=True)
    raw = proc.stdout if proc.stdout.strip() else proc.stderr
    (record_dir / out_name).write_text(raw, encoding="utf-8")
    parsed = None
    try:
        parsed = json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        pass
    return proc.returncode, parsed


def main():
    if len(sys.argv) < 5:
        fail(
            "usage: dispatch-agy-worker.py <workspace_abs_path> "
            "<agent_record_dir> <prompt> <agent_name> [timeout_ms]"
        )

    if os.environ.get("HERDR_ENV") != "1":
        fail("HERDR_ENV != 1. This script must run inside a Herdr-managed pane.")

    workspace = str(Path(sys.argv[1]).resolve())
    record_dir = Path(sys.argv[2])
    task = sys.argv[3]
    agent_name = sys.argv[4]
    timeout_ms = sys.argv[5] if len(sys.argv) > 5 else "300000"
    start_timeout_ms = os.environ.get("HERDR_START_TIMEOUT_MS", "30000")

    herdr = shutil.which("herdr")
    if not herdr:
        fail("herdr not found on PATH.")
    if not shutil.which("agy"):
        fail(
            "agy not found on PATH. Install:\n"
            "  macOS/Linux:       curl -fsSL https://antigravity.google/cli/install.sh | bash\n"
            "  Windows PowerShell: irm https://antigravity.google/cli/install.ps1 | iex\n"
            "  Docs: https://antigravity.google/docs/cli/install"
        )

    record_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    full_prompt = (
        f"Trong thư mục tuyệt đối {workspace} (dùng đúng đường dẫn này, "
        f"KHÔNG dùng thư mục scratch riêng của bạn): {task}"
    )

    print(f"Splitting pane for workspace {workspace} ...", file=sys.stderr)
    split_rc, split_json = run_herdr(
        [herdr, "pane", "split", "--current", "--direction", "right",
         "--cwd", workspace, "--no-focus"],
        record_dir, "herdr_pane_split.json",
    )
    if split_rc != 0:
        fail(f"herdr pane split failed (exit {split_rc}). See herdr_pane_split.json")
    pane_id = find_key(split_json, "pane_id") if split_json else None
    if not pane_id:
        fail("could not extract pane_id from herdr pane split response.")

    print(f"Starting agy agent '{agent_name}' in pane {pane_id} ...", file=sys.stderr)
    # A pane fresh out of `pane split` can briefly not be "an available
    # shell" yet --- observed empirically (2026-08-13 smoke test):
    # {"error":{"code":"agent_pane_busy",...}} even though the pane has no
    # agent attached. Retry a few times with a short settle delay.
    start_attempts = 4
    start_rc = 1
    for attempt in range(1, start_attempts + 1):
        start_rc, start_json = run_herdr(
            [herdr, "agent", "start", agent_name, "--kind", "agy",
             "--pane", pane_id, "--timeout", start_timeout_ms,
             "--", "--add-dir", workspace],
            record_dir, "herdr_agent_start.json",
        )
        if start_rc == 0:
            break
        err_code = find_key(start_json, "code") if start_json else None
        if err_code != "agent_pane_busy":
            break
        print(
            f"  attempt {attempt}/{start_attempts}: agent_pane_busy "
            "(pane not ready yet), retrying in 2s ...",
            file=sys.stderr,
        )
        time.sleep(2)
    if start_rc != 0:
        fail(f"herdr agent start failed (exit {start_rc}). See herdr_agent_start.json")

    print(f"Prompting '{agent_name}' and waiting for it to settle (timeout {timeout_ms}ms) ...",
          file=sys.stderr)
    # The first prompt right after `agent start` can race the agent's TUI
    # becoming actually input-ready even though `interactive_ready: true`
    # is already reported --- observed empirically (2026-08-13 smoke test):
    # herdr returns {"error":{"code":"agent_prompt_stalled",...}}, status
    # stays idle, state_change_seq doesn't move, and the prompt text never
    # lands in the pane at all. Retry a few times with a short settle delay
    # before giving up --- do NOT treat that error as "nothing to do".
    prompt_attempts = 4
    prompt_rc = 1
    prompt_json = None
    for attempt in range(1, prompt_attempts + 1):
        prompt_rc, prompt_json = run_herdr(
            [herdr, "agent", "prompt", agent_name, full_prompt, "--wait", "--timeout", timeout_ms],
            record_dir, "herdr_agent_prompt.json",
        )
        err_code = find_key(prompt_json, "code") if prompt_json else None
        if err_code != "agent_prompt_stalled":
            break
        print(
            f"  attempt {attempt}/{prompt_attempts}: agent_prompt_stalled "
            "(TUI not ready yet), retrying in 3s ...",
            file=sys.stderr,
        )
        time.sleep(3)

    # Authoritative status: re-query rather than trust prompt's own response shape.
    get_rc, get_json = run_herdr(
        [herdr, "agent", "get", agent_name], record_dir, "herdr_agent_get.json"
    )
    status = find_key(get_json, "agent_status") if get_json else None
    status = status or "UNKNOWN"

    read_proc = subprocess.run(
        [herdr, "agent", "read", agent_name, "--source", "recent-unwrapped", "--lines", "300"],
        capture_output=True, text=True,
    )
    read_text = read_proc.stdout
    (record_dir / "agent_output.txt").write_text(read_text, encoding="utf-8")

    # `agent_prompt_stalled` proved unreliable in practice (2026-08-13 smoke
    # test): it fired on every one of 4 retry attempts even though the
    # prompt HAD landed and the task completed correctly. Trusting the
    # error alone would wrongly report failure; trusting a settled `idle`
    # status alone would repeat the ORIGINAL false-positive bug (idle
    # because nothing ever ran). So require actual delivery evidence: our
    # prompt template always starts with the fixed Vietnamese marker below
    # regardless of task content --- if it never appears in the pane
    # transcript, the prompt never landed, full stop, no matter what any
    # status code says.
    #
    # Compare with whitespace stripped on both sides: a narrow pane makes
    # agy hard-wrap the marker across multiple lines (e.g. "Trong thư mục"
    # / "tuyệt đối" on separate lines) even under `recent-unwrapped`, which
    # only re-joins Herdr's own soft-wrap bookkeeping, not text the app
    # itself already wrapped when rendering at that column width. A plain
    # substring check would miss that split and false-negative.
    read_compact = "".join(read_text.split())
    if "Trongthưmụctuyệtđối" not in read_compact:
        status = "no_delivery_confirmed"

    dispatch_md = f"""# Dispatch — {record_dir.name}

- **Timestamp:** {ts}
- **Workspace:** `{workspace}`
- **Herdr agent name:** `{agent_name}`
- **Herdr pane:** `{pane_id}`
- **agy status after wait:** {status}
- **prompt exit code:** {prompt_rc}
- **Commands used:**
```
herdr pane split --current --direction right --cwd "{workspace}" --no-focus
herdr agent start "{agent_name}" --kind agy --pane "{pane_id}" --timeout {start_timeout_ms} -- --add-dir "{workspace}"
herdr agent prompt "{agent_name}" "{full_prompt}" --wait --timeout {timeout_ms}
```
- **Raw responses:** `herdr_pane_split.json`, `herdr_agent_start.json`, `herdr_agent_prompt.json`, `herdr_agent_get.json`
- **Terminal output snapshot:** `agent_output.txt`
"""
    (record_dir / "DISPATCH.md").write_text(dispatch_md, encoding="utf-8")

    blocked_note = ""
    if status == "blocked":
        blocked_note = (
            "- **BLOCKED** — agy is asking something or waiting on approval.\n"
            "  Orchestrator must resolve interactively:\n"
            f"  `herdr agent read {agent_name} --source recent-unwrapped --lines 120`\n"
            f"  then `herdr agent send-keys {agent_name} ...` or "
            f"`herdr agent prompt {agent_name} \"...\" --wait`.\n"
        )
    elif status == "no_delivery_confirmed":
        blocked_note = (
            "- **NO DELIVERY CONFIRMED** — the prompt marker text never showed up\n"
            f"  in the pane transcript after {prompt_attempts} attempts. The task was\n"
            "  very likely never received. Inspect `agent_output.txt`, and if the\n"
            "  pane is truly still empty, retry manually:\n"
            f"  `herdr agent prompt {agent_name} \"...\" --wait --timeout {timeout_ms}`.\n"
        )

    progress_md = f"""# Progress — {record_dir.name}

- [x] Dispatched at {ts}
- Herdr agent: `{agent_name}` in pane `{pane_id}`
- agy status: {status} (prompt exit code {prompt_rc})
{blocked_note}- Reviewer MUST independently verify the actual workspace files — do not trust this status string alone.
- Pane `{pane_id}` / agent `{agent_name}` left alive for follow-up prompts and self-check reads.
"""
    (record_dir / "progress.md").write_text(progress_md, encoding="utf-8")

    print(f"Dispatched. status={status} pane={pane_id} agent={agent_name}", file=sys.stderr)

    if status in ("idle", "done"):
        sys.exit(0)
    elif status == "blocked":
        print("BLOCKED — see progress.md for how to resolve.", file=sys.stderr)
        sys.exit(2)
    elif status == "no_delivery_confirmed":
        print("NO DELIVERY CONFIRMED — see progress.md for how to resolve.", file=sys.stderr)
        sys.exit(1)
    else:
        print(f"WARNING: unrecognized/unknown status '{status}'. Inspect {record_dir} manually.",
              file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
