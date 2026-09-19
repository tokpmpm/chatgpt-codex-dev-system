#!/bin/bash
set -uo pipefail

LIB_DIR="$HOME/.local/lib/ai-dev-control-bridge"
CONFIG="$LIB_DIR/config.env"
STATE_DIR="$HOME/.local/state/ai-dev-control-bridge"
LOG_DIR="$HOME/Library/Logs/ai-dev-control-bridge"
ACTIVE_AI_DEV="$HOME/.local/bin/ai-dev"
ACTIVE_WORKER="$STATE_DIR/active-worker"

[ -f "$CONFIG" ] || exit 2
. "$CONFIG"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

command_id="${1:-}"
action="${2:-}"
target_repo="${3:-}"
target_issue="${4:-}"

[ -n "$command_id" ] && [ -n "$action" ] && [ -n "$target_repo" ] && [ -n "$target_issue" ] || exit 3

run_log="$LOG_DIR/worker-$command_id.log"
mkdir -p "$LOG_DIR" "$STATE_DIR"

patch_issue() {
  local body="$1"
  "$GH_BIN" api --method PATCH "repos/$REPO/issues/$INBOX_ISSUE" -f body="$body" >/dev/null 2>&1 || true
}

case "$action" in
  AI_DEV_REPAIR)
    cmd=("$ACTIVE_AI_DEV" repair --repo "$target_repo" --issue "$target_issue")
    ;;
  AI_DEV_RESUME)
    cmd=("$ACTIVE_AI_DEV" resume --repo "$target_repo" --issue "$target_issue")
    ;;
  *)
    patch_issue "AI_DEV_COMMAND_RESULT
COMMAND_ID: $command_id
STATUS: FAIL
DETAIL: unsupported-worker-action:$action"
    rm -f "$ACTIVE_WORKER"
    exit 9
    ;;
esac

printf 'COMMAND_ID=%s\nACTION=%s\nPID=%s\nSTARTED_AT=%s\n' "$command_id" "$action" "$$" "$(date '+%Y-%m-%dT%H:%M:%S%z')" > "$ACTIVE_WORKER"

"${cmd[@]}" > "$run_log" 2>&1 &
child=$!

while kill -0 "$child" 2>/dev/null; do
  state="$("$ACTIVE_AI_DEV" status --repo "$target_repo" --issue "$target_issue" 2>&1 | tr '\n' ' ' | tail -c 2200)"
  tail_log="$(tail -c 1200 "$run_log" 2>/dev/null | tr '\n' ' ')"
  patch_issue "AI_DEV_COMMAND_PROGRESS
COMMAND_ID: $command_id
ACTION: $action
STATUS: RUNNING
DETAIL: $state
LOG_TAIL: $tail_log"
  sleep 45
done

wait "$child"
rc=$?
detail="$(tail -c 3500 "$run_log" 2>/dev/null | tr '\n' ' ')"
if [ "$rc" -eq 0 ]; then
  status="PASS"
else
  status="FAIL"
fi
patch_issue "AI_DEV_COMMAND_RESULT
COMMAND_ID: $command_id
STATUS: $status
DETAIL: rc=$rc $detail"
rm -f "$ACTIVE_WORKER"
exit "$rc"
