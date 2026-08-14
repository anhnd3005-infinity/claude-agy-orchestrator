#!/usr/bin/env bash
# Dispatch one task to a CLI agent (any Herdr-supported kind: agy, codex,
# claude, gemini, ...) running INSIDE a Herdr-managed pane, and record a
# DISPATCH.md/progress.md scaffold for a .agents/ file-based orchestration.
#
# The worker lives in a real, persistent Herdr pane, so the orchestrator
# can poll its lifecycle (idle/working/blocked/done), read its terminal
# output, and send follow-up prompts without relaunching anything.
#
# Usage:
#   dispatch-herdr-worker.sh <workspace_abs_path> <agent_record_dir> <prompt> <agent_name> <kind> [timeout_ms]
#
#   workspace_abs_path   Absolute path the worker is allowed to read/write.
#                         Passed to `herdr pane split --cwd` AND repeated
#                         inside the prompt. Some kinds ALSO need a native
#                         workspace-scoping flag on top of cwd (see the
#                         KIND_NATIVE_ARGS table below) --- e.g. agy does
#                         not reliably use its launching cwd as its
#                         workspace without an explicit --add-dir, and will
#                         silently write into its own scratch dir while
#                         still reporting success if you skip it. Not every
#                         kind has this quirk; codex has none known so far.
#   agent_record_dir      Where to write DISPATCH.md, progress.md, and the
#                         raw herdr JSON responses (e.g. .agents/worker_agy_2/).
#   prompt                Task text. The workspace path is prefixed automatically.
#   agent_name            Unique Herdr agent name for this worker
#                         (must match [a-z][a-z0-9_-]{0,31}, unique among
#                         live agents). Used to target every later
#                         `herdr agent ...` call (read/send-keys/prompt/wait).
#   kind                  Herdr agent kind: agy, codex, claude, gemini, ...
#                         (run `herdr agent` to see the full supported list).
#                         Only `agy` and `codex` have been exercised against
#                         this script so far --- see KIND_NATIVE_ARGS below.
#                         Any other kind runs with no extra native args
#                         (cwd-only) until it earns its own case here.
#   timeout_ms            Optional, default 300000 (5m). Passed to
#                         `herdr agent prompt --timeout`.
#
# Requires: HERDR_ENV=1 (this must run from inside a Herdr-managed pane),
# `herdr` on PATH, `jq` on PATH, and the requested kind's own CLI installed
# and present in `herdr agent`'s supported kind list.
#
# This script only does the deterministic happy path: split pane, start
# agent, send the first prompt, wait for it to settle, read the result. If
# the worker ends up `blocked` (a question, an approval prompt, etc.), this
# script does NOT try to resolve that --- it reports the blocked status and
# exits 2. The orchestrator must then take over interactively via
# `herdr agent read/send-keys/prompt <agent_name>`.

set -euo pipefail

WORKSPACE_ARG="$1"
RECORD_DIR="$2"
TASK="$3"
AGENT_NAME="$4"
KIND="$5"
TIMEOUT_MS="${6:-300000}"
START_TIMEOUT_MS="${HERDR_START_TIMEOUT_MS:-30000}"

if [ "${HERDR_ENV:-}" != "1" ]; then
  echo "ERROR: HERDR_ENV != 1. This script must run inside a Herdr-managed pane." >&2
  exit 1
fi

# Per https://herdr.dev/docs/agent-automation/: any herdr --timeout value
# must be > 3000ms and <= 300000ms (5 min) --- values outside that range
# are rejected by herdr itself, not silently clamped. Validate here with a
# clear message instead of letting herdr fail cryptically mid-dispatch. For
# tasks genuinely expected to run longer than 5 minutes, this single-call
# ceiling means you cannot just pass a bigger number --- poll instead:
# repeat `herdr agent wait <agent_name> --timeout 300000` in a loop (each
# call still capped at 5 min, but you can call it as many times as needed).
HERDR_TIMEOUT_MIN=3000
HERDR_TIMEOUT_MAX=300000
for _pair in "TIMEOUT_MS:$TIMEOUT_MS" "START_TIMEOUT_MS:$START_TIMEOUT_MS"; do
  _name="${_pair%%:*}"
  _val="${_pair#*:}"
  if [ "$_val" -le "$HERDR_TIMEOUT_MIN" ] || [ "$_val" -gt "$HERDR_TIMEOUT_MAX" ]; then
    echo "ERROR: $_name=$_val ms is outside herdr's allowed --timeout range" >&2
    echo "  ($HERDR_TIMEOUT_MIN, $HERDR_TIMEOUT_MAX] ms. For work expected to take" >&2
    echo "  longer, don't raise this value further --- loop 'herdr agent wait" >&2
    echo "  $AGENT_NAME --timeout $HERDR_TIMEOUT_MAX' instead once the worker is dispatched." >&2
    exit 1
  fi
done

if ! command -v herdr >/dev/null 2>&1; then
  echo "ERROR: herdr not found on PATH." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq not found on PATH (required to parse herdr's JSON output)." >&2
  exit 1
fi

WORKSPACE="$(cd "$WORKSPACE_ARG" && pwd)"
mkdir -p "$RECORD_DIR"
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Per-kind workspace-scoping quirks. Default: nothing extra --- `pane split
# --cwd` is assumed sufficient. Add a case here only once you've actually
# verified a kind needs more (same discipline as the agy `--add-dir`
# finding: verified against real files, not assumed).
NATIVE_ARGS=()
case "$KIND" in
  agy)
    NATIVE_ARGS=(--add-dir "$WORKSPACE")
    ;;
  codex)
    NATIVE_ARGS=()
    ;;
  *)
    echo "NOTE: kind '$KIND' has no known workspace-scoping quirk yet --- relying on" >&2
    echo "  --cwd from pane split alone. If this kind silently writes to the wrong" >&2
    echo "  place, add a case for it in KIND_NATIVE_ARGS (see script header)." >&2
    ;;
esac

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

echo "Starting '$KIND' agent '$AGENT_NAME' in pane $PANE_ID ..." >&2
# A pane fresh out of `pane split` can briefly not be "an available shell"
# yet --- observed empirically (2026-08-13 smoke test, agy):
# {"error":{"code":"agent_pane_busy","message":"... is not an available
# shell"}} even though the pane has no agent attached. This is a Herdr-level
# pane-lifecycle race, not specific to any one kind --- retry a few times
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
  START_JSON="$(herdr agent start "$AGENT_NAME" --kind "$KIND" --pane "$PANE_ID" --timeout "$START_TIMEOUT_MS" -- "${NATIVE_ARGS[@]}" 2>"$START_ERR_FILE")"
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
# already reported --- observed empirically (2026-08-13 smoke test, agy):
# herdr returns {"error":{"code":"agent_prompt_stalled",...}}, status stays
# idle, state_change_seq doesn't move, and the prompt text never lands in
# the pane at all. This is a Herdr TUI-readiness race, not agy-specific ---
# retry a few times with a short settle delay before giving up --- do NOT
# treat that error as "nothing to do". NOTE: herdr writes server errors as
# JSON to STDERR (exit status 1), not stdout --- both streams captured
# explicitly here.
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
# test, agy): it fired on every one of 4 retry attempts even though the
# prompt HAD landed and the task completed correctly. Trusting the error
# alone would wrongly report failure; trusting a settled `idle` status
# alone would repeat the ORIGINAL false-positive bug (idle because nothing
# ever ran). So require actual delivery evidence: our prompt template
# always starts with the fixed Vietnamese marker below regardless of task
# content or kind --- if it never appears in the pane transcript, the
# prompt never landed, full stop, no matter what any status code says.
#
# Compare with whitespace stripped on both sides: a narrow pane makes the
# agent's TUI hard-wrap the marker across multiple lines (e.g. "Trong thư
# mục" / "tuyệt đối" on separate lines) even under `--source
# recent-unwrapped`, which only re-joins Herdr's own soft-wrap bookkeeping,
# not text the app itself already wrapped when rendering at that column
# width. A single-line substring/grep match would miss that split and
# false-negative. Stripping only ASCII whitespace bytes (space/tab/CR/LF)
# is UTF-8-safe: those byte values never appear inside a multi-byte UTF-8
# sequence, so Vietnamese diacritics survive intact.
#
# Only override when STATUS is `idle` or `done` --- herdr's own docs
# define `done` as "the same underlying idle state after unseen background
# work finishes", i.e. a settled state, same as idle. (2026-08-14 smoke
# test found the exact original bug recurring under `done` specifically:
# `agent prompt --wait` returned success with a bumped state_change_seq and
# no error at all, `agent get` reported `done`, yet the pane was
# completely empty --- scoping the marker-check to `idle` only, as an
# earlier version of this fix did, let that false positive straight
# through. Don't narrow this again without re-testing both states.) Per
# https://herdr.dev/docs/agent-automation/, an explicit `agent read` can
# return `agent_not_idle` / incomplete alternate-screen history while the
# agent is genuinely `working` --- so a missing marker while `working` may
# just mean the read caught it mid-render, not that delivery failed.
# Forcing `no_delivery_confirmed` in that case would mislabel a legitimately
# slow, still-running task as a failure. `blocked` is already handled on
# its own below regardless of the marker.
READ_COMPACT="$(printf '%s' "$READ_TEXT" | tr -d ' \t\n\r')"
case "$STATUS" in
  idle|done)
    if ! printf '%s' "$READ_COMPACT" | grep -qF "Trongthưmụctuyệtđối"; then
      STATUS="no_delivery_confirmed"
    fi
    ;;
esac

{
  echo "# Dispatch — $(basename "$RECORD_DIR")"
  echo
  echo "- **Timestamp:** $TS"
  echo "- **Workspace:** \`$WORKSPACE\`"
  echo "- **Kind:** \`$KIND\`"
  echo "- **Herdr agent name:** \`$AGENT_NAME\`"
  echo "- **Herdr pane:** \`$PANE_ID\`"
  echo "- **Status after wait:** $STATUS"
  echo "- **prompt exit code:** $PROMPT_RC"
  echo "- **Commands used:**"
  echo '```'
  echo "herdr pane split --current --direction right --cwd \"$WORKSPACE\" --no-focus"
  echo "herdr agent start \"$AGENT_NAME\" --kind $KIND --pane \"$PANE_ID\" --timeout $START_TIMEOUT_MS -- ${NATIVE_ARGS[*]}"
  echo "herdr agent prompt \"$AGENT_NAME\" \"$FULL_PROMPT\" --wait --timeout $TIMEOUT_MS"
  echo '```'
  echo "- **Raw responses:** \`herdr_pane_split.json\`, \`herdr_agent_start.json\`, \`herdr_agent_prompt.json\`, \`herdr_agent_get.json\`"
  echo "- **Terminal output snapshot:** \`agent_output.txt\`"
} > "$RECORD_DIR/DISPATCH.md"

{
  echo "# Progress — $(basename "$RECORD_DIR")"
  echo
  echo "- [x] Dispatched at $TS"
  echo "- Herdr agent: \`$AGENT_NAME\` (kind \`$KIND\`) in pane \`$PANE_ID\`"
  echo "- Status: $STATUS (prompt exit code $PROMPT_RC)"
  if [ "$STATUS" = "blocked" ]; then
    echo "- **BLOCKED** — agent is asking something or waiting on approval."
    echo "  Orchestrator must resolve interactively:"
    echo "  \`herdr agent read $AGENT_NAME --source recent-unwrapped --lines 120\`"
    echo "  then \`herdr agent send-keys $AGENT_NAME ...\` or \`herdr agent prompt $AGENT_NAME \"...\" --wait\`."
  elif [ "$STATUS" = "no_delivery_confirmed" ]; then
    echo "- **NO DELIVERY CONFIRMED** — the prompt marker text never showed up"
    echo "  in the pane transcript after $PROMPT_ATTEMPTS attempts. The task was"
    echo "  very likely never received. Inspect \`agent_output.txt\`, and if the"
    echo "  pane is truly still empty, retry manually:"
    echo "  \`herdr agent prompt $AGENT_NAME \"...\" --wait --timeout $TIMEOUT_MS\`."
  elif [ "$STATUS" = "working" ]; then
    echo "- **STILL WORKING** — not a failure. The task is legitimately taking"
    echo "  longer than $TIMEOUT_MS ms (herdr caps a single --timeout at"
    echo "  $HERDR_TIMEOUT_MAX ms). Poll further, don't re-dispatch:"
    echo "  \`herdr agent wait $AGENT_NAME --timeout $HERDR_TIMEOUT_MAX\` (repeat as needed)."
    echo "  Also possible: this agent was already busy with an unrelated prompt"
    echo "  when dispatched (e.g. a reused agent name) and this task is still"
    echo "  queued behind it — check \`agent_output.txt\` for a \`▸ ...\` queued"
    echo "  line above the current output."
  fi
  echo "- Reviewer MUST independently verify the actual workspace files — do not trust this status string alone."
  echo "- Pane \`$PANE_ID\` / agent \`$AGENT_NAME\` left alive for follow-up prompts and self-check reads."
} > "$RECORD_DIR/progress.md"

echo "Dispatched. status=$STATUS kind=$KIND pane=$PANE_ID agent=$AGENT_NAME" >&2

case "$STATUS" in
  idle|done)
    exit 0
    ;;
  blocked)
    echo "BLOCKED — see progress.md for how to resolve." >&2
    exit 2
    ;;
  no_delivery_confirmed)
    echo "NO DELIVERY CONFIRMED — see progress.md for how to resolve." >&2
    exit 1
    ;;
  working)
    echo "STILL WORKING past timeout — not a failure, see progress.md to poll further." >&2
    exit 3
    ;;
  *)
    echo "WARNING: unrecognized/unknown status '$STATUS'. Inspect $RECORD_DIR manually." >&2
    exit 1
    ;;
esac
