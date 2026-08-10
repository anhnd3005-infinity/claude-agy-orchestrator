#!/usr/bin/env python3
"""Cross-platform twin of dispatch-agy-worker.sh — same behavior, no bash
required. Use this on Windows (native cmd/PowerShell, no WSL/Git Bash
needed) or anywhere Python is preferred over a shell script.

Dispatch one task to an agy (Antigravity CLI) headless worker and record a
DISPATCH.md/progress.md scaffold for a .agents/ file-based orchestration.

Usage:
    python3 dispatch-agy-worker.py <workspace_abs_path> <agent_record_dir> <prompt> [timeout]

    workspace_abs_path   Absolute path agy is allowed to read/write. Passed
                         to --add-dir AND repeated inside the prompt --- agy
                         does NOT use the launching process's cwd as its
                         workspace; without --add-dir it silently writes
                         into its own scratch dir (on Windows:
                         %USERPROFILE%\\.gemini\\antigravity-cli\\scratch\\,
                         mirroring ~/.gemini/antigravity-cli/scratch/ on
                         macOS/Linux) while still reporting status: SUCCESS.
    agent_record_dir      Where to write DISPATCH.md, progress.md and the
                         raw JSON response (e.g. .agents/worker_agy_2/).
    prompt                Task text. The workspace path is prefixed
                         automatically.
    timeout               Optional, default 5m (agy's own --print-timeout).

Requires `agy` on PATH. Uses --dangerously-skip-permissions because this
runs headless with nobody to approve prompts --- only use on tasks confined
to the given workspace, never on anything touching real/production data
without the human's explicit go-ahead first.
"""

import json
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def fail(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def main():
    if len(sys.argv) < 4:
        fail(
            "usage: dispatch-agy-worker.py <workspace_abs_path> "
            "<agent_record_dir> <prompt> [timeout]"
        )

    workspace = str(Path(sys.argv[1]).resolve())
    record_dir = Path(sys.argv[2])
    task = sys.argv[3]
    timeout = sys.argv[4] if len(sys.argv) > 4 else "5m"

    agy = shutil.which("agy")
    if not agy:
        fail(
            "agy not found on PATH. Install: "
            "curl -fsSL https://antigravity.google/cli/install.sh | bash "
            "(or the Windows equivalent from https://antigravity.google/cli/install)"
        )

    record_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    raw_path = record_dir / "agy_raw_output.json"
    err_path = record_dir / "agy_stderr.log"

    full_prompt = (
        f"Trong thư mục tuyệt đối {workspace} (dùng đúng đường dẫn này, "
        f"KHÔNG dùng thư mục scratch riêng của bạn): {task}"
    )

    cmd = [
        agy,
        "--print",
        full_prompt,
        "--add-dir",
        workspace,
        "--output-format",
        "json",
        "--print-timeout",
        timeout,
        "--dangerously-skip-permissions",
    ]

    proc = subprocess.run(cmd, capture_output=True, text=True)
    raw_path.write_text(proc.stdout, encoding="utf-8")
    err_path.write_text(proc.stderr, encoding="utf-8")

    status = "UNKNOWN"
    try:
        status = json.loads(proc.stdout).get("status", "UNKNOWN")
    except (json.JSONDecodeError, ValueError):
        pass  # leave as UNKNOWN --- self-check must not trust this alone anyway

    dispatch_md = f"""# Dispatch — {record_dir.name}

- **Timestamp:** {ts}
- **Workspace (--add-dir):** `{workspace}`
- **Exit code:** {proc.returncode}
- **Command:**
```
agy --print "{full_prompt}" --add-dir "{workspace}" --output-format json --print-timeout {timeout} --dangerously-skip-permissions
```
- **Raw output:** `{raw_path.name}` (+ `{err_path.name}` if non-empty)
"""
    (record_dir / "DISPATCH.md").write_text(dispatch_md, encoding="utf-8")

    progress_md = f"""# Progress — {record_dir.name}

- [x] Dispatched at {ts}
- agy status: {status} (exit code {proc.returncode})
- Reviewer MUST independently verify — do not trust this status string alone.
"""
    (record_dir / "progress.md").write_text(progress_md, encoding="utf-8")

    print(f"Dispatched. status={status} rc={proc.returncode} raw={raw_path}", file=sys.stderr)
    print(proc.stdout)
    sys.exit(proc.returncode)


if __name__ == "__main__":
    main()
