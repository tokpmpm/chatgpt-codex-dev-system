#!/bin/bash
set -uo pipefail

LIB_DIR="$HOME/.local/lib/ai-dev-control-bridge"
CONFIG="$LIB_DIR/config.env"
STATE_DIR="$HOME/.local/state/ai-dev-control-bridge"
LOG_DIR="$HOME/Library/Logs/ai-dev-control-bridge"
PROCESSED="$STATE_DIR/processed-command-ids"
LOCKDIR="$STATE_DIR/lock"
FRAMEWORK_DIR="$HOME/.local/share/ai-dev/framework"
ACTIVE_AI_DEV="$HOME/.local/bin/ai-dev"

mkdir -p "$STATE_DIR" "$LOG_DIR"
touch "$PROCESSED"

if [ ! -f "$CONFIG" ]; then
  echo "missing config: $CONFIG" >&2
  exit 2
fi

. "$CONFIG"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

if ! mkdir "$LOCKDIR" 2>/dev/null; then
  if [ -f "$LOCKDIR/pid" ]; then
    OLD_PID="$(cat "$LOCKDIR/pid" 2>/dev/null || true)"
    if [ -n "$OLD_PID" ] && ! kill -0 "$OLD_PID" 2>/dev/null; then
      rm -rf "$LOCKDIR"
      mkdir "$LOCKDIR" 2>/dev/null || exit 0
    else
      exit 0
    fi
  else
    rm -rf "$LOCKDIR"
    mkdir "$LOCKDIR" 2>/dev/null || exit 0
  fi
fi
printf '%s\n' "$" > "$LOCKDIR/pid"
trap 'rm -rf "$LOCKDIR" >/dev/null 2>&1 || true' EXIT

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$LOG_DIR/bridge.log"
}

is_processed() {
  local command_id="$1"
  grep -Fxq "$command_id" "$PROCESSED" 2>/dev/null
}

mark_processed() {
  local command_id="$1"
  printf '%s\n' "$command_id" >> "$PROCESSED"
}

ack() {
  local command_id="$1"
  local status="$2"
  local detail="$3"
  local body
  body="AI_DEV_COMMAND_RESULT
COMMAND_ID: $command_id
STATUS: $status
DETAIL: $detail"
  "$GH_BIN" api --method PATCH "repos/$REPO/issues/$INBOX_ISSUE" -f body="$body" >/dev/null 2>&1 || true
}

valid_sha() {
  case "$1" in
    [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]*) [ "${#1}" -eq 40 ] ;;
    *) return 1 ;;
  esac
}

fetch_repo_commit() {
  local commit="$1"
  if [ ! -d "$FRAMEWORK_DIR/.git" ]; then
    mkdir -p "$(dirname "$FRAMEWORK_DIR")"
    "$GH_BIN" repo clone "$REPO" "$FRAMEWORK_DIR" >/dev/null 2>&1
  fi
  git -C "$FRAMEWORK_DIR" fetch --quiet origin "$commit"
  git -C "$FRAMEWORK_DIR" cat-file -e "$commit^{commit}"
}

do_ping() { echo "bridge-ok"; }

do_doctor() {
  [ -x "$ACTIVE_AI_DEV" ] || { echo "ai-dev-not-installed"; return 4; }
  "$ACTIVE_AI_DEV" doctor 2>&1 | tail -n 40
}

do_doctor_repair() {
  [ -x "$ACTIVE_AI_DEV" ] || { echo "ai-dev-not-installed"; return 4; }
  "$ACTIVE_AI_DEV" doctor --repair 2>&1 | tail -n 60
}

do_bridge_update() {
  local commit="$1"
  valid_sha "$commit" || { echo "invalid-commit"; return 5; }
  "$GH_BIN" api "repos/$REPO/commits/$commit" >/dev/null 2>&1 || { echo "commit-not-found"; return 6; }
  local tmp="$LIB_DIR/bridge.sh.tmp.$$"
  "$GH_BIN" api "repos/$REPO/contents/bootstrap/ai-dev-control-bridge.sh?ref=$commit" --jq .content \
    | tr -d '\n' \
    | base64 -D > "$tmp" || return 7
  chmod 700 "$tmp"
  mv "$tmp" "$LIB_DIR/bridge.sh"
  echo "bridge-updated:$commit"
}

do_sync_install() {
  local commit="$1"
  valid_sha "$commit" || { echo "invalid-commit"; return 5; }
  fetch_repo_commit "$commit" || { echo "fetch-failed"; return 6; }
  git -C "$FRAMEWORK_DIR" reset --hard >/dev/null 2>&1 || true
  git -C "$FRAMEWORK_DIR" clean -fd >/dev/null 2>&1 || true
  git -C "$FRAMEWORK_DIR" checkout --detach --quiet "$commit"

  local installer=""
  if [ -f "$FRAMEWORK_DIR/bootstrap/install-ai-dev.sh" ]; then
    installer="$FRAMEWORK_DIR/bootstrap/install-ai-dev.sh"
  elif [ -f "$FRAMEWORK_DIR/tools/codex-runner/install.sh" ]; then
    installer="$FRAMEWORK_DIR/tools/codex-runner/install.sh"
  else
    echo "installer-not-found"
    return 8
  fi

  bash "$installer" 2>&1 | tail -n 80
}

main_once() {
  "$GH_BIN" auth status >/dev/null 2>&1 || { log "gh auth unavailable"; return 0; }

  local body command_id action commit target_repo target_issue target_branch review_sha support_commit support_path repair_round
  body="$("$GH_BIN" api "repos/$REPO/issues/$INBOX_ISSUE" --jq .body 2>/dev/null)" || {
    log "failed to fetch inbox"
    return 0
  }

  printf '%s\n' "$body" | grep -q '^AI_DEV_COMMAND_BEGIN$' || return 0

  command_id="$(printf '%s\n' "$body" | sed -n 's/^COMMAND_ID:[[:space:]]*//p' | head -1)"
  action="$(printf '%s\n' "$body" | sed -n 's/^ACTION:[[:space:]]*//p' | head -1)"
  commit="$(printf '%s\n' "$body" | sed -n 's/^COMMIT:[[:space:]]*//p' | head -1)"
  target_repo="$(printf '%s\n' "$body" | sed -n 's/^TARGET_REPO:[[:space:]]*//p' | head -1)"
  target_issue="$(printf '%s\n' "$body" | sed -n 's/^TARGET_ISSUE:[[:space:]]*//p' | head -1)"
  target_branch="$(printf '%s\n' "$body" | sed -n 's/^TARGET_BRANCH:[[:space:]]*//p' | head -1)"
  review_sha="$(printf '%s\n' "$body" | sed -n 's/^REVIEW_SHA:[[:space:]]*//p' | head -1)"
  support_commit="$(printf '%s\n' "$body" | sed -n 's/^SUPPORT_COMMIT:[[:space:]]*//p' | head -1)"
  support_path="$(printf '%s\n' "$body" | sed -n 's/^SUPPORT_PATH:[[:space:]]*//p' | head -1)"
  repair_round="$(printf '%s\n' "$body" | sed -n 's/^REPAIR_ROUND:[[:space:]]*//p' | head -1)"

  [ -n "$command_id" ] || return 0
  [ -n "$action" ] || return 0
  is_processed "$command_id" && return 0

  log "COMMAND $command_id $action START"

  local output rc=0
  case "$action" in
    PING) output="$(do_ping 2>&1)" || rc=$? ;;
    DOCTOR) output="$(do_doctor 2>&1)" || rc=$? ;;
    DOCTOR_REPAIR) output="$(do_doctor_repair 2>&1)" || rc=$? ;;
    BRIDGE_UPDATE) output="$(do_bridge_update "$commit" 2>&1)" || rc=$? ;;
    SYNC_INSTALL) output="$(do_sync_install "$commit" 2>&1)" || rc=$? ;;
    AI_DEV_STATUS)
      output="$("$ACTIVE_AI_DEV" status --repo "$target_repo" --issue "$target_issue" 2>&1)" || rc=$?
      ;;
    AI_DEV_IMPORT_REPAIR)
      [ -n "$repair_round" ] || repair_round="1"
      output="$("$ACTIVE_AI_DEV" import-repair --repo "$target_repo" --issue "$target_issue" --branch "$target_branch" --review-sha "$review_sha" --support-commit "$support_commit" --support-path "$support_path" --round "$repair_round" 2>&1)" || rc=$?
      ;;
    AI_DEV_REPAIR_DRY_RUN)
      output="$("$ACTIVE_AI_DEV" repair --repo "$target_repo" --issue "$target_issue" --dry-run 2>&1)" || rc=$?
      ;;
    AI_DEV_REPAIR)
      output="$("$ACTIVE_AI_DEV" repair --repo "$target_repo" --issue "$target_issue" 2>&1)" || rc=$?
      ;;
    AI_DEV_RECOVER_REVIEW)
      output="$("$ACTIVE_AI_DEV" recover-review --repo "$target_repo" --issue "$target_issue" 2>&1)" || rc=$?
      ;;
    *) output="unsupported-action:$action"; rc=9 ;;
  esac

  output="$(printf '%s' "$output" | tail -c 3500 | tr '\n' ' ')"
  if [ "$rc" -eq 0 ]; then
    ack "$command_id" "PASS" "$output"
    mark_processed "$command_id"
    log "COMMAND $command_id $action PASS"
  else
    ack "$command_id" "FAIL" "rc=$rc $output"
    mark_processed "$command_id"
    log "COMMAND $command_id $action FAIL rc=$rc"
  fi
}

main_once
