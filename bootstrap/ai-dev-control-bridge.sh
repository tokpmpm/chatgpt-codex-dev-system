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
WORKER="$LIB_DIR/worker.sh"
ACTIVE_WORKER="$STATE_DIR/active-worker"

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

start_async_ai_dev() {
  local command_id="$1" action="$2" target_repo="$3" target_issue="$4"
  [ -x "$WORKER" ] || { echo "worker-missing"; return 16; }

  if [ -f "$ACTIVE_WORKER" ]; then
    local existing_pid
    existing_pid="$(sed -n 's/^PID=//p' "$ACTIVE_WORKER" | head -1)"
    if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
      echo "worker-busy pid=$existing_pid"
      return 17
    fi
    rm -f "$ACTIVE_WORKER"
  fi

  nohup "$WORKER" "$command_id" "$action" "$target_repo" "$target_issue"     > "$LOG_DIR/worker-dispatch-$command_id.log" 2>&1 &
  local pid=$!
  echo "STARTED pid=$pid action=$action"
}

do_disable_legacy_runner() {
  local legacy_label="com.meshthings.life-balance-codex-runner"
  if launchctl print "gui/$UID/$legacy_label" >/dev/null 2>&1; then
    launchctl bootout "gui/$UID/$legacy_label" >/dev/null 2>&1 || return 12
  fi
  if launchctl print "gui/$UID/$legacy_label" >/dev/null 2>&1; then
    echo "legacy-runner-still-loaded"
    return 13
  fi
  echo "legacy-runner-disabled"
}

do_legacy_inspect() {
  local runner="$HOME/.local/lib/life-balance-codex-runner/runner.sh"
  local plist="$HOME/Library/LaunchAgents/com.meshthings.life-balance-codex-runner.plist"
  local config="$HOME/.config/life-balance-codex-runner/config.env"
  printf 'runner_exists=%s ' "$([ -f "$runner" ] && echo yes || echo no)"
  if [ -f "$runner" ]; then
    printf 'runner_sha256=%s ' "$(shasum -a 256 "$runner" | awk '{print $1}')"
  fi
  printf 'plist_exists=%s ' "$([ -f "$plist" ] && echo yes || echo no)"
  printf 'config_exists=%s ' "$([ -f "$config" ] && echo yes || echo no)"
  printf 'loaded=%s ' "$(launchctl print "gui/$UID/com.meshthings.life-balance-codex-runner" >/dev/null 2>&1 && echo yes || echo no)"
  if [ -f "$config" ]; then
    printf 'config_keys='
    grep -E '^[A-Z0-9_]+=' "$config" | sed -E 's/=.*$/=<set>/' | tr '\n' ',' | head -c 1200
  fi
}

kill_tree() {
  local pid="$1" child
  [ -n "$pid" ] || return 0
  for child in $(/usr/bin/pgrep -P "$pid" 2>/dev/null || true); do
    kill_tree "$child"
  done
  kill -TERM "$pid" >/dev/null 2>&1 || true
}

do_snapshot_stop_active() {
  local target_repo="$1" target_issue="$2"
  local worker_pid="" state_file worktree recovery_branch snapshot_sha dirty current_branch large_files path
  if [ -f "$ACTIVE_WORKER" ]; then
    worker_pid="$(sed -n 's/^PID=//p' "$ACTIVE_WORKER" | head -1)"
  fi
  if [ -n "$worker_pid" ] && kill -0 "$worker_pid" 2>/dev/null; then
    kill_tree "$worker_pid"
    sleep 3
    if kill -0 "$worker_pid" 2>/dev/null; then
      kill -KILL "$worker_pid" >/dev/null 2>&1 || true
    fi
  fi

  state_file="$HOME/.local/state/ai-dev/tasks/$(printf '%s' "$target_repo" | tr '/: .' '____')--$target_issue.env"
  [ -f "$state_file" ] || { echo "state-file-missing:$state_file"; return 18; }
  . "$state_file"
  worktree="${CURRENT_WORKTREE:-}"
  [ -n "$worktree" ] && [ -d "$worktree" ] || { echo "worktree-missing:$worktree"; return 19; }
  [ -n "${EXECUTION_BASE_SHA:-}" ] || { echo "execution-base-missing"; return 28; }

  # A previous snapshot attempt may have created a local WIP commit containing
  # generated files. Reset to the guarded execution base while preserving all
  # file changes in the worktree.
  git -C "$worktree" reset --mixed "$EXECUTION_BASE_SHA" >/dev/null || return 29

  recovery_branch="recovery/issue-${target_issue}-new-runner-wip-$(date '+%Y%m%d-%H%M%S')"
  current_branch="$(git -C "$worktree" branch --show-current)"
  if [ -n "$current_branch" ]; then
    git -C "$worktree" branch -m "$recovery_branch" >/dev/null || return 20
  else
    git -C "$worktree" checkout -b "$recovery_branch" >/dev/null || return 20
  fi

  # Preserve source/design changes only. Never snapshot generated runtime
  # dependencies, browser output, built sites, or runner prompt files.
  git -C "$worktree" add -u -- .     ':(exclude)node_modules/**'     ':(exclude)output/**'     ':(exclude)site/**'     ':(exclude)site-staging/**' >/dev/null 2>&1 || true

  while IFS= read -r -d '' path; do
    case "$path" in
      node_modules/*|output/*|site/*|site-staging/*|.ai-dev-*) continue ;;
      *) git -C "$worktree" add -- "$path" ;;
    esac
  done < <(git -C "$worktree" ls-files --others --exclude-standard -z)

  dirty="$(git -C "$worktree" diff --cached --name-only)"
  if [ -z "$dirty" ]; then
    echo "no-source-changes-to-snapshot"
    rm -f "$ACTIVE_WORKER"
    return 0
  fi

  git -C "$worktree" -c user.name="AI Dev Rollback" -c user.email="ai-dev@local"     commit -m "wip: preserve issue #$target_issue before legacy runner rollback" >/dev/null || return 21

  large_files="$(git -C "$worktree" ls-tree -r -l HEAD | awk '$4 ~ /^[0-9]+$/ && $4 > 90000000 {print $5 ":" $4}')"
  if [ -n "$large_files" ]; then
    echo "snapshot-large-files-blocked:$large_files"
    return 30
  fi

  snapshot_sha="$(git -C "$worktree" rev-parse HEAD)"
  git -C "$worktree" push origin "HEAD:refs/heads/$recovery_branch" >/dev/null || return 22
  rm -f "$ACTIVE_WORKER"
  echo "snapshot_saved branch=$recovery_branch sha=$snapshot_sha worktree=$worktree"
}

do_restore_legacy_runner() {
  local runner="$HOME/.local/lib/life-balance-codex-runner/runner.sh"
  local plist="$HOME/Library/LaunchAgents/com.meshthings.life-balance-codex-runner.plist"
  local legacy_label="com.meshthings.life-balance-codex-runner"
  [ -f "$runner" ] || { echo "legacy-runner-missing"; return 23; }
  [ -f "$plist" ] || { echo "legacy-plist-missing"; return 24; }

  launchctl bootout "gui/$UID/$legacy_label" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$UID" "$plist" >/dev/null 2>&1 || return 25
  launchctl kickstart -k "gui/$UID/$legacy_label" >/dev/null 2>&1 || return 26
  launchctl print "gui/$UID/$legacy_label" >/dev/null 2>&1 || return 27

  nohup /bin/sh -c "sleep 5; /bin/launchctl bootout gui/$UID/com.meshthings.ai-dev-control-bridge" \
    > "$LOG_DIR/rollback-shutdown.log" 2>&1 &
  echo "legacy-runner-restored; new-control-bridge-shutdown-scheduled"
}

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
      output="$(start_async_ai_dev "$command_id" "$action" "$target_repo" "$target_issue" 2>&1)" || rc=$?
      ;;
    AI_DEV_RESUME)
      output="$(start_async_ai_dev "$command_id" "$action" "$target_repo" "$target_issue" 2>&1)" || rc=$?
      ;;
    AI_DEV_RECOVER_REVIEW)
      output="$("$ACTIVE_AI_DEV" recover-review --repo "$target_repo" --issue "$target_issue" 2>&1)" || rc=$?
      ;;
    DISABLE_LEGACY_LIFE_BALANCE_RUNNER)
      output="$(do_disable_legacy_runner 2>&1)" || rc=$?
      ;;
    LEGACY_INSPECT)
      output="$(do_legacy_inspect 2>&1)" || rc=$?
      ;;
    SNAPSHOT_STOP_ACTIVE)
      output="$(do_snapshot_stop_active "$target_repo" "$target_issue" 2>&1)" || rc=$?
      ;;
    RESTORE_LEGACY_RUNNER)
      output="$(do_restore_legacy_runner 2>&1)" || rc=$?
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


heartbeat() {
  printf 'pid=%s updated_at=%s\n' "$$" "$(date '+%Y-%m-%dT%H:%M:%S%z')" > "$STATE_DIR/heartbeat"
}

run_daemon() {
  local loops=0 max_loops="${AI_DEV_DAEMON_MAX_LOOPS:-0}" interval="${AI_DEV_POLL_SECONDS:-30}"
  while true; do
    heartbeat
    main_once
    loops=$((loops + 1))
    if [ "$max_loops" -gt 0 ] && [ "$loops" -ge "$max_loops" ]; then
      return 0
    fi
    sleep "$interval"
  done
}

case "${1:---once}" in
  --once)
    heartbeat
    main_once
    ;;
  --daemon)
    run_daemon
    ;;
  *)
    echo "usage: $0 [--once|--daemon]" >&2
    exit 2
    ;;
esac
