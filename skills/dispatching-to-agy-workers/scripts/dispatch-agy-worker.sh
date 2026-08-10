#!/usr/bin/env bash
# Dispatch one task to an agy (Antigravity CLI) headless worker and record a
# DISPATCH.md/progress.md scaffold for a .agents/ file-based orchestration.
#
# Usage:
#   dispatch-agy-worker.sh <workspace_abs_path> <agent_record_dir> <prompt> [timeout]
#
#   workspace_abs_path  Absolute path agy is allowed to read/write. Passed to
#                        --add-dir AND repeated inside the prompt — agy does
#                        NOT use the launching process's cwd as its workspace;
#                        without --add-dir it silently writes into its own
#                        ~/.gemini/antigravity-cli/scratch/ while still
#                        reporting status: SUCCESS.
#   agent_record_dir     Where to write DISPATCH.md, progress.md and the raw
#                        JSON response (e.g. .agents/worker_agy_2/).
#   prompt                Task text. The workspace path is prefixed automatically.
#   timeout               Optional, default 5m (agy's own --print-timeout).
#
# Requires `agy` on PATH. Uses --dangerously-skip-permissions because this
# runs headless with nobody to approve prompts — only use on tasks confined
# to the given workspace, never on anything touching real/production data
# without the human's explicit go-ahead first.

set -euo pipefail

WORKSPACE="$1"
RECORD_DIR="$2"
TASK="$3"
TIMEOUT="${4:-5m}"

if ! command -v agy >/dev/null 2>&1; then
  echo "ERROR: agy not found on PATH. Install: curl -fsSL https://antigravity.google/cli/install.sh | bash" >&2
  exit 1
fi

mkdir -p "$RECORD_DIR"
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
RAW="$RECORD_DIR/agy_raw_output.json"
ERR="$RECORD_DIR/agy_stderr.log"

FULL_PROMPT="Trong thư mục tuyệt đối $WORKSPACE (dùng đúng đường dẫn này, KHÔNG dùng thư mục scratch riêng của bạn): $TASK"

set +e
agy --print "$FULL_PROMPT" \
    --add-dir "$WORKSPACE" \
    --output-format json \
    --print-timeout "$TIMEOUT" \
    --dangerously-skip-permissions \
    > "$RAW" 2> "$ERR"
RC=$?
set -e

{
  echo "# Dispatch — $(basename "$RECORD_DIR")"
  echo
  echo "- **Timestamp:** $TS"
  echo "- **Workspace (--add-dir):** \`$WORKSPACE\`"
  echo "- **Exit code:** $RC"
  echo "- **Command:**"
  echo '```'
  echo "agy --print \"$FULL_PROMPT\" --add-dir \"$WORKSPACE\" --output-format json --print-timeout $TIMEOUT --dangerously-skip-permissions"
  echo '```'
  echo "- **Raw output:** \`$(basename "$RAW")\` (+ \`$(basename "$ERR")\` if non-empty)"
} > "$RECORD_DIR/DISPATCH.md"

STATUS="$(sed -n 's/.*"status":"\([A-Z]*\)".*/\1/p' "$RAW" | head -1)"
{
  echo "# Progress — $(basename "$RECORD_DIR")"
  echo
  echo "- [x] Dispatched at $TS"
  echo "- agy status: ${STATUS:-UNKNOWN} (exit code $RC)"
  echo "- Reviewer MUST independently verify — do not trust this status string alone."
} > "$RECORD_DIR/progress.md"

echo "Dispatched. status=${STATUS:-UNKNOWN} rc=$RC raw=$RAW" >&2
cat "$RAW"
exit "$RC"
