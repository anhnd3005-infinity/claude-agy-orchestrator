#!/usr/bin/env bash
# Dispatch one task to an agy (Antigravity CLI) worker running INSIDE a
# Herdr-managed pane, and record a DISPATCH.md/progress.md scaffold for a
# .agents/ file-based orchestration.
#
# Replaces the old headless `agy --print` approach entirely: the worker now
# lives in a real, persistent Herdr pane, so the orchestrator can poll its
# lifecycle (idle/working/blocked/done), read its terminal output, and send
# follow-up prompts without relaunching anything.
#
# Usage:
#   dispatch-agy-worker.sh <workspace_abs_path> <agent_record_dir> <prompt> <agent_name> [timeout_ms]
#
#   workspace_abs_path   Absolute path the worker is allowed to read/write.
#                         Passed to agy's own --add-dir (via `agent start ... -- --add-dir <path>`)
#                         AND repeated inside the prompt --- agy does NOT use
#                         the launching process's cwd as its workspace;
#                         without --add-dir it silently writes into its own
#                         ~/.gemini/antigravity-cli/scratch/ while still
#                         reporting status: SUCCESS. Same gotcha as before,
#                         fixed the same way, just via `agent start`'s
#                         native-arg passthrough instead of a CLI flag.
#   agent_record_dir      Where to write DISPATCH.md, progress.md, and the
#                         raw herdr JSON responses (e.g. .agents/worker_agy_2/).
#   prompt                Task text. The workspace path is prefixed automatically.
#   agent_name            Unique Herdr agent name for this worker
#                         (must match [a-z][a-z0-9_-]{0,31}, unique among
#                         live agents). Used to target every later
#                         `herdr agent ...` call (read/send-keys/prompt/wait).
#   timeout_ms            Optional, default 300000 (5m). Passed to
#                         `herdr agent prompt --timeout`.
#
# Requires: HERDR_ENV=1 (this must run from inside a Herdr-managed pane),
# `herdr` on PATH, `jq` on PATH, and `agy` installed as a Herdr-recognized
# agent kind (`herdr agent` lists supported kinds; `agy` is one of them).
#
# This script only does the deterministic happy path: split pane, start
# agent, send the first prompt, wait for it to settle, read the result.
# If the worker ends up `blocked` (agy asking a question, an approval
# prompt, etc.), this script does NOT try to resolve that --- it reports
# the blocked status and exits 2. The orchestrator must then take over
# interactively via `herdr agent read/send-keys/prompt <agent_name>`.

set -euo pipefail

WORKSPACE_ARG="$1"
RECORD_DIR="$2"
TASK="$3"
AGENT_NAME="$4"
TIMEOUT_MS="${5:-300000}"
START_TIMEOUT_MS="${HERDR_START_TIMEOUT_MS:-30000}"

if [ "${HERDR_ENV:-}" != "1" ]; then
  echo "ERROR: HERDR_ENV != 1. This script must run inside a Herdr-managed pane." >&2
  exit 1
fi

if ! command -v herdr >/dev/null 2>&1; then
  echo "ERROR: herdr not found on PATH." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq not found on PATH (required to parse herdr's JSON output)." >&2
  exit 1
fi

if ! command -v agy >/dev/null 2>&1; then
  echo "ERROR: agy not found on PATH. Install: curl -fsSL https://antigravity.google/cli/install.sh | bash" >&2
  exit 1
fi

WORKSPACE="$(cd "$WORKSPACE_ARG" && pwd)"
mkdir -p "$RECORD_DIR"
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Recursive-descent status/pane_id extraction --- doesn't depend on knowing
# herdr's exact response nesting, just that the key exists somewhere in the
# JSON tree. Robust against minor response-shape differences across herdr
# versions/commands.
jq_find() {
  jq -r --arg k "$1" '[.. | objects | select(has($k)) | .[$k]] | .[0] // empty'
}

FULL_PROMPT="Trong thư mục tuyệt đối $WORKSPACE (dùng đúng đường dẫn này, KHÔNG dùng thư mục scratch riêng của bạn): $TASK"

echo "Splitting pane for workspace $WORKSPACE ..." >&2
set +e
SPLIT_JSON="$(herdr pane split --current --direction right --cwd "$WORKSPACE" --no-focus)"
SPLIT_RC=$?
set -e
echo "$SPLIT_JSON" > "$RECORD_DIR/herdr_pane_split.json"
if [ "$SPLIT_RC" -ne 0 ]; then
  echo "ERROR: herdr pane split failed (exit $SPLIT_RC). See $RECORD_DIR/herdr_pane_split.json" >&2
  exit 1
fi
PANE_ID="$(echo "$SPLIT_JSON" | jq_find pane_id)"
if [ -z "$PANE_ID" ]; then
  echo "ERROR: could not extract pane_id from herdr pane split response." >&2
  exit 1
fi

echo "Starting agy agent '$AGENT_NAME' in pane $PANE_ID ..." >&2
# A pane fresh out of `pane split` can briefly not be "an available shell"
# yet --- observed empirically (2026-08-13 smoke test):
# {"error":{"code":"agent_pane_busy","message":"... is not an available
# shell"}} even though the pane has no agent attached. Retry a few times
# with a short settle delay before giving up. NOTE: herdr writes server
# errors as JSON to STDERR (exit status 1), not stdout --- a plain
# `$(cmd)` capture only sees stdout and silently misses the error body, so
# both stdout and stderr are captured here explicitly.
START_ATTEMPTS=4
START_JSON=""
START_RC=1
START_ERR_FILE="$(mktemp)"
for attempt in $(seq 1 "$START_ATTEMPTS"); do
  set +e
  START_JSON="$(herdr agent start "$AGENT_NAME" --kind agy --pane "$PANE_ID" --timeout "$START_TIMEOUT_MS" -- --add-dir "$WORKSPACE" 2>"$START_ERR_FILE")"
  START_RC=$?
  set -e
  if [ "$START_RC" -eq 0 ]; then
    break
  fi
  START_ERR="$(cat "$START_ERR_FILE")"
  ERR_CODE="$(echo "$START_ERR" | jq -r '.error.code // empty' 2>/dev/null || true)"
  if [ "$ERR_CODE" != "agent_pane_busy" ]; then
    START_JSON="$START_ERR"
    break
  fi
  echo "  attempt $attempt/$START_ATTEMPTS: agent_pane_busy (pane not ready yet), retrying in 2s ..." >&2
  sleep 2
  START_JSON="$START_ERR"
done
rm -f "$START_ERR_FILE"
echo "$START_JSON" > "$RECORD_DIR/herdr_agent_start.json"
if [ "$START_RC" -ne 0 ]; then
  echo "ERROR: herdr agent start failed (exit $START_RC). See $RECORD_DIR/herdr_agent_start.json" >&2
  exit 1
fi

echo "Prompting '$AGENT_NAME' and waiting for it to settle (timeout ${TIMEOUT_MS}ms) ..." >&2
# The first prompt right after `agent start` can race the agent's TUI
# becoming actually input-ready even though `interactive_ready: true` is
# already reported --- observed empirically (2026-08-13 smoke test):
# herdr returns {"error":{"code":"agent_prompt_stalled",...}}, status stays
# idle, state_change_seq doesn't move, and the prompt text never lands in
# the pane at all. Retry a few times with a short settle delay before
# giving up --- do NOT treat that error as "nothing to do". NOTE: herdr
# writes server errors as JSON to STDERR (exit status 1), not stdout --- a
# plain `$(cmd)` capture only sees stdout and silently misses the error
# body, so both stdout and stderr are captured here explicitly.
PROMPT_ATTEMPTS=4
PROMPT_JSON=""
PROMPT_RC=1
PROMPT_ERR_FILE="$(mktemp)"
for attempt in $(seq 1 "$PROMPT_ATTEMPTS"); do
  set +e
  PROMPT_JSON="$(herdr agent prompt "$AGENT_NAME" "$FULL_PROMPT" --wait --timeout "$TIMEOUT_MS" 2>"$PROMPT_ERR_FILE")"
  PROMPT_RC=$?
  set -e
  if [ "$PROMPT_RC" -eq 0 ]; then
    break
  fi
  PROMPT_ERR="$(cat "$PROMPT_ERR_FILE")"
  ERR_CODE="$(echo "$PROMPT_ERR" | jq -r '.error.code // empty' 2>/dev/null || true)"
  if [ "$ERR_CODE" != "agent_prompt_stalled" ]; then
    PROMPT_JSON="$PROMPT_ERR"
    break
  fi
  echo "  attempt $attempt/$PROMPT_ATTEMPTS: agent_prompt_stalled (TUI not ready yet), retrying in 3s ..." >&2
  sleep 3
  PROMPT_JSON="$PROMPT_ERR"
done
rm -f "$PROMPT_ERR_FILE"
echo "$PROMPT_JSON" > "$RECORD_DIR/herdr_agent_prompt.json"

# Authoritative status: re-query rather than trust prompt's own response shape.
GET_JSON="$(herdr agent get "$AGENT_NAME" 2>/dev/null || true)"
echo "$GET_JSON" > "$RECORD_DIR/herdr_agent_get.json"
STATUS="$(echo "$GET_JSON" | jq_find agent_status)"
STATUS="${STATUS:-UNKNOWN}"

READ_TEXT="$(herdr agent read "$AGENT_NAME" --source recent-unwrapped --lines 300 2>/dev/null || true)"
printf '%s\n' "$READ_TEXT" > "$RECORD_DIR/agent_output.txt"

# `agent_prompt_stalled` proved unreliable in practice (2026-08-13 smoke
# test): it fired on every one of 4 retry attempts even though the prompt
# HAD landed and the task completed correctly. Trusting the error alone
# would wrongly report failure; trusting a settled `idle` status alone
# would repeat the ORIGINAL false-positive bug (idle because nothing ever
# ran). So require actual delivery evidence: our prompt template always
# starts with the fixed Vietnamese marker below regardless of task
# content --- if it never appears in the pane transcript, the prompt never
# landed, full stop, no matter what any status code says.
#
# Compare with whitespace stripped on both sides: a narrow pane makes agy
# hard-wrap the marker across multiple lines (e.g. "Trong thư mục" / "tuyệt
# đối" on separate lines) even under `--source recent-unwrapped`, which
# only re-joins Herdr's own soft-wrap bookkeeping, not text the app itself
# already wrapped when rendering at that column width. A single-line
# substring/grep match would miss that split and false-negative. Stripping
# only ASCII whitespace bytes (space/tab/CR/LF) is UTF-8-safe: those byte
# values never appear inside a multi-byte UTF-8 sequence, so Vietnamese
# diacritics survive intact.
READ_COMPACT="$(printf '%s' "$READ_TEXT" | tr -d ' \t\n\r')"
if ! printf '%s' "$READ_COMPACT" | grep -qF "Trongthưmụctuyệtđối"; then
  STATUS="no_delivery_confirmed"
fi

{
  echo "# Dispatch — $(basename "$RECORD_DIR")"
  echo
  echo "- **Timestamp:** $TS"
  echo "- **Workspace:** \`$WORKSPACE\`"
  echo "- **Herdr agent name:** \`$AGENT_NAME\`"
  echo "- **Herdr pane:** \`$PANE_ID\`"
  echo "- **agy status after wait:** $STATUS"
  echo "- **prompt exit code:** $PROMPT_RC"
  echo "- **Commands used:**"
  echo '```'
  echo "herdr pane split --current --direction right --cwd \"$WORKSPACE\" --no-focus"
  echo "herdr agent start \"$AGENT_NAME\" --kind agy --pane \"$PANE_ID\" --timeout $START_TIMEOUT_MS -- --add-dir \"$WORKSPACE\""
  echo "herdr agent prompt \"$AGENT_NAME\" \"$FULL_PROMPT\" --wait --timeout $TIMEOUT_MS"
  echo '```'
  echo "- **Raw responses:** \`herdr_pane_split.json\`, \`herdr_agent_start.json\`, \`herdr_agent_prompt.json\`, \`herdr_agent_get.json\`"
  echo "- **Terminal output snapshot:** \`agent_output.txt\`"
} > "$RECORD_DIR/DISPATCH.md"

{
  echo "# Progress — $(basename "$RECORD_DIR")"
  echo
  echo "- [x] Dispatched at $TS"
  echo "- Herdr agent: \`$AGENT_NAME\` in pane \`$PANE_ID\`"
  echo "- agy status: $STATUS (prompt exit code $PROMPT_RC)"
  if [ "$STATUS" = "blocked" ]; then
    echo "- **BLOCKED** — agy is asking something or waiting on approval."
    echo "  Orchestrator must resolve interactively:"
    echo "  \`herdr agent read $AGENT_NAME --source recent-unwrapped --lines 120\`"
    echo "  then \`herdr agent send-keys $AGENT_NAME ...\` or \`herdr agent prompt $AGENT_NAME \"...\" --wait\`."
  elif [ "$STATUS" = "no_delivery_confirmed" ]; then
    echo "- **NO DELIVERY CONFIRMED** — the prompt marker text never showed up"
    echo "  in the pane transcript after $PROMPT_ATTEMPTS attempts. The task was"
    echo "  very likely never received. Inspect \`agent_output.txt\`, and if the"
    echo "  pane is truly still empty, retry manually:"
    echo "  \`herdr agent prompt $AGENT_NAME \"...\" --wait --timeout $TIMEOUT_MS\`."
  fi
  echo "- Reviewer MUST independently verify the actual workspace files — do not trust this status string alone."
  echo "- Pane \`$PANE_ID\` / agent \`$AGENT_NAME\` left alive for follow-up prompts and self-check reads."
} > "$RECORD_DIR/progress.md"

echo "Dispatched. status=$STATUS pane=$PANE_ID agent=$AGENT_NAME" >&2

case "$STATUS" in
  idle|done)
    exit 0
    ;;
  blocked)
    echo "BLOCKED — see progress.md for how to resolve." >&2
    exit 2
    ;;
  *)
    echo "WARNING: unrecognized/unknown status '$STATUS'. Inspect $RECORD_DIR manually." >&2
    exit 1
    ;;
esac
