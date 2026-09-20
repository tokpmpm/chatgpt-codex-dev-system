#!/bin/bash
set -u

REPO="tokpmpm/life-balance-game"
ISSUE="12"
BRANCH="feature/v8.6.0"
OLD_SHA="159388c7aa04a93d8815194127bfc9188de5d5c2"
NEW_SHA="5447227ce532a5eebbf3cc2ecc3520dbfb3ff8cc"

LABEL="com.meshthings.life-balance-codex-runner"
WORKDIR="$HOME/Antigravity/life-balance-game"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
CONFIG="$HOME/.config/life-balance-codex-runner/config.env"
STATE_DIR="$WORKDIR/.codex-runner/state"
LOG_DIR="$WORKDIR/.codex-runner/logs"
BACKUP="$HOME/.local/state/life-balance-runner-third-final/$(date '+%Y%m%d-%H%M%S')"
REPORT="$BACKUP/report.txt"

mkdir -p "$BACKUP"
touch "$REPORT"

log() {
  echo "$*" | tee -a "$REPORT"
}

post_report() {
  local status="$1"
  local body
  body="$(cat "$REPORT" 2>/dev/null | tail -n 120)"
  gh issue comment "$ISSUE" --repo "$REPO" --body "$(cat <<EOF
<!-- final-legacy-runner-repair -->
## Final legacy Runner repair

STATUS: $status
EXPECTED_HEAD: $NEW_SHA
BACKUP: $BACKUP

```
$body
```
EOF
)" >/dev/null 2>&1 || true
}

fail() {
  log "RESULT=FAIL"
  log "ROOT_CAUSE=$1"
  if [ -f "$LOG_DIR/launchd.err.log" ]; then
    log "=== stderr tail ==="
    tail -n 40 "$LOG_DIR/launchd.err.log" 2>/dev/null | tee -a "$REPORT" >/dev/null
  fi
  if [ -f "$LOG_DIR/launchd.out.log" ]; then
    log "=== stdout tail ==="
    tail -n 40 "$LOG_DIR/launchd.out.log" 2>/dev/null | tee -a "$REPORT" >/dev/null
  fi
  post_report "FAIL"
  exit 20
}

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

GH="$(command -v gh 2>/dev/null || true)"
GIT="$(command -v git 2>/dev/null || true)"
SED="/usr/bin/sed"
GREP="/usr/bin/grep"

[ -n "$GH" ] || { echo "gh-not-found"; exit 20; }
[ -n "$GIT" ] || { echo "git-not-found"; exit 20; }
[ -d "$WORKDIR/.git" ] || fail "workdir-not-git"
[ -f "$PLIST" ] || fail "missing-plist"
[ -f "$CONFIG" ] || fail "missing-config"
"$GH" auth status >/dev/null 2>&1 || fail "gh-auth-failed"

# Read label names from the legacy config without exposing secrets.
. "$CONFIG"
APPROVED="${REPAIR_APPROVED_LABEL:-repair-approved}"
AWAITING="${REPAIR_AWAITING_PLAN_LABEL:-repair-awaiting-plan}"
RUNNING="${RUNNING_LABEL:-codex-running}"

log "START third-final-one-shot"
log "WORKDIR=$WORKDIR"

REMOTE_SHA="$("$GH" api "repos/$REPO/branches/feature%2Fv8.6.0" --jq .commit.sha 2>/dev/null || true)"
[ "$REMOTE_SHA" = "$NEW_SHA" ] || fail "unexpected-remote-head:$REMOTE_SHA"
log "REMOTE_HEAD=$REMOTE_SHA"

# Ensure an approved plan for the composite SHA really exists before mutating local runner state.
PLAN_OK="$("$GH" api "repos/$REPO/issues/$ISSUE/comments?per_page=100" --paginate --jq '.[] | select(.body | contains("STATUS: APPROVED") and contains("TARGET_SHA: 5447227ce532a5eebbf3cc2ecc3520dbfb3ff8cc")) | .id' 2>/dev/null | tail -1)"
[ -n "$PLAN_OK" ] || fail "approved-plan-for-composite-sha-not-found"
log "APPROVED_PLAN_COMMENT=$PLAN_OK"

# Stop the legacy runner so state cannot change underneath us.
/bin/launchctl bootout "gui/$UID/$LABEL" >/dev/null 2>&1 || true
sleep 2
log "RUNNER_STOPPED=yes"

# Back up local runner state and git evidence first.
[ -d "$STATE_DIR" ] && tar -czf "$BACKUP/runner-state-before.tgz" -C "$WORKDIR/.codex-runner" state >/dev/null 2>&1 || true
"$GIT" -C "$WORKDIR" status --porcelain=v1 > "$BACKUP/git-status-before.txt" 2>/dev/null || true
"$GIT" -C "$WORKDIR" rev-parse HEAD > "$BACKUP/git-head-before.txt" 2>/dev/null || true
"$GIT" -C "$WORKDIR" diff > "$BACKUP/git-diff-before.patch" 2>/dev/null || true
"$GIT" -C "$WORKDIR" diff --cached > "$BACKUP/git-index-before.patch" 2>/dev/null || true

# Preserve any current tracked/untracked work in a local stash before aligning the runner checkout.
if [ -n "$("$GIT" -C "$WORKDIR" status --porcelain=v1 2>/dev/null)" ]; then
  "$GIT" -C "$WORKDIR" stash push -u -m "pre-third-final-runner-repair-$(date '+%Y%m%d-%H%M%S')" >/dev/null 2>&1 || fail "git-stash-failed"
  log "LOCAL_DIRTY_WORK_PRESERVED=stash"
else
  log "LOCAL_DIRTY_WORK_PRESERVED=not-needed"
fi

# Align legacy runner checkout exactly to the already-approved composite HEAD.
"$GIT" -C "$WORKDIR" fetch origin "$BRANCH" >/dev/null 2>&1 || fail "git-fetch-failed"
"$GIT" -C "$WORKDIR" checkout -B "$BRANCH" "origin/$BRANCH" >/dev/null 2>&1 || fail "git-checkout-align-failed"
"$GIT" -C "$WORKDIR" reset --hard "$NEW_SHA" >/dev/null 2>&1 || fail "git-reset-align-failed"

LOCAL_SHA="$("$GIT" -C "$WORKDIR" rev-parse HEAD 2>/dev/null || true)"
[ "$LOCAL_SHA" = "$NEW_SHA" ] || fail "local-head-mismatch:$LOCAL_SHA"
[ -z "$("$GIT" -C "$WORKDIR" status --porcelain=v1 2>/dev/null)" ] || fail "worktree-still-dirty"
log "LOCAL_HEAD=$LOCAL_SHA"
log "WORKTREE_CLEAN=yes"

# Replace stale exact SHA references using streaming sed, not Python/JSON loading.
# Only runner state is touched; logs/review evidence are deliberately left unchanged.
STATE_FILES=0
if [ -d "$STATE_DIR" ]; then
  while IFS= read -r -d '' file; do
    if LC_ALL=C "$GREP" -q "$OLD_SHA" "$file" 2>/dev/null; then
      cp "$file" "$BACKUP/$(basename "$file").before" 2>/dev/null || true
      LC_ALL=C "$SED" -i '' "s/$OLD_SHA/$NEW_SHA/g" "$file" || fail "state-sed-failed:$file"
      STATE_FILES=$((STATE_FILES + 1))
      log "STATE_UPDATED=$file"
    fi
  done < <(find "$STATE_DIR" -type f -print0 2>/dev/null)

  if LC_ALL=C "$GREP" -RIl "$OLD_SHA" "$STATE_DIR" >/dev/null 2>&1; then
    fail "old-sha-still-present-in-runner-state"
  fi
fi
log "STATE_FILES_UPDATED=$STATE_FILES"

# The runner may have returned the issue to awaiting-plan after the failed validation.
# Re-arm exactly the approved repair trigger without touching the issue body or plan comments.
"$GH" issue edit "$ISSUE" --repo "$REPO" --remove-label "$AWAITING" >/dev/null 2>&1 || true
"$GH" issue edit "$ISSUE" --repo "$REPO" --remove-label "$APPROVED" >/dev/null 2>&1 || true
sleep 2
"$GH" issue edit "$ISSUE" --repo "$REPO" --add-label "$APPROVED" >/dev/null 2>&1 || fail "rearm-repair-approved-failed"
log "REPAIR_TRIGGER_REARMED=$APPROVED"

# Start runner cleanly.
/bin/launchctl bootstrap "gui/$UID" "$PLIST" >/dev/null 2>&1 || fail "launchctl-bootstrap-failed"
/bin/launchctl kickstart -k "gui/$UID/$LABEL" >/dev/null 2>&1 || fail "launchctl-kickstart-failed"
log "RUNNER_RESTARTED=yes"

# Wait up to 3 minutes for a real transition. Success means actual running state,
# not merely that repair-approved disappeared.
for n in $(seq 1 36); do
  sleep 5
  LABELS_NOW="$("$GH" api "repos/$REPO/issues/$ISSUE" --jq '[.labels[].name] | join(",")' 2>/dev/null || true)"

  case ",$LABELS_NOW," in
    *",$RUNNING,"*|*,repair-running,*)
      log "RESULT=PASS"
      log "STATE=RUNNING"
      log "LABELS=$LABELS_NOW"
      post_report "PASS"
      exit 0
      ;;
  esac

  # If the runner rejects the plan again, attempt one internal self-heal in this same invocation.
  if [ "$n" -eq 12 ]; then
    STATUS_BODY="$("$GH" api "repos/$REPO/issues/$ISSUE/comments?per_page=100" --paginate --jq '.[] | select(.body | contains("<!-- local-codex-status -->")) | .body' 2>/dev/null | tail -1)"
    if printf '%s' "$STATUS_BODY" | "$GREP" -q 'pending target SHA is not feature branch HEAD'; then
      log "SELF_HEAL=retry-after-stale-target-rejection"
      /bin/launchctl bootout "gui/$UID/$LABEL" >/dev/null 2>&1 || true
      sleep 1
      if [ -d "$STATE_DIR" ]; then
        while IFS= read -r -d '' file; do
          LC_ALL=C "$SED" -i '' "s/$OLD_SHA/$NEW_SHA/g" "$file" 2>/dev/null || true
        done < <(find "$STATE_DIR" -type f -print0 2>/dev/null)
      fi
      "$GH" issue edit "$ISSUE" --repo "$REPO" --remove-label "$AWAITING" >/dev/null 2>&1 || true
      "$GH" issue edit "$ISSUE" --repo "$REPO" --remove-label "$APPROVED" >/dev/null 2>&1 || true
      sleep 1
      "$GH" issue edit "$ISSUE" --repo "$REPO" --add-label "$APPROVED" >/dev/null 2>&1 || true
      /bin/launchctl bootstrap "gui/$UID" "$PLIST" >/dev/null 2>&1 || true
      /bin/launchctl kickstart -k "gui/$UID/$LABEL" >/dev/null 2>&1 || true
    fi
  fi
done

FINAL_LABELS="$("$GH" api "repos/$REPO/issues/$ISSUE" --jq '[.labels[].name] | join(",")' 2>/dev/null || true)"
log "FINAL_LABELS=$FINAL_LABELS"
fail "runner-did-not-enter-running-state-within-180s"
