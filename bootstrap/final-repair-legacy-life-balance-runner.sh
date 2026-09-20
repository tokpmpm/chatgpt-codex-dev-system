#!/bin/bash
set -u

LABEL="com.meshthings.life-balance-codex-runner"
WORKDIR="$HOME/Antigravity/life-balance-game"
CONFIG="$HOME/.config/life-balance-codex-runner/config.env"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
STATE="$WORKDIR/.codex-runner/state/repair/issue-12.json"
OLD_SHA="159388c7aa04a93d8815194127bfc9188de5d5c2"
NEW_SHA="5447227ce532a5eebbf3cc2ecc3520dbfb3ff8cc"
BRANCH="feature/v8.6.0"
BACKUP="$HOME/.local/state/life-balance-runner-final-repair/$(date '+%Y%m%d-%H%M%S')"

mkdir -p "$BACKUP"

fail() {
  echo "RESULT=FAIL"
  echo "ROOT_CAUSE=$1"
  echo "BACKUP=$BACKUP"
  exit 20
}

[ -d "$WORKDIR/.git" ] || fail "workdir-not-git-repo"
[ -f "$CONFIG" ] || fail "missing-config"
[ -f "$PLIST" ] || fail "missing-plist"

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
GH="$(command -v gh 2>/dev/null || true)"
GIT="$(command -v git 2>/dev/null || true)"
[ -n "$GH" ] || fail "gh-not-found"
[ -n "$GIT" ] || fail "git-not-found"
"$GH" auth status >/dev/null 2>&1 || fail "gh-auth-failed"

REMOTE_SHA="$("$GH" api "repos/tokpmpm/life-balance-game/branches/feature%2Fv8.6.0" --jq .commit.sha 2>/dev/null || true)"
[ "$REMOTE_SHA" = "$NEW_SHA" ] || fail "unexpected-remote-head:$REMOTE_SHA"

# 1) Stop runner before touching its checkout/state.
/bin/launchctl bootout "gui/$UID/$LABEL" >/dev/null 2>&1 || true
sleep 2

# 2) Preserve all useful local evidence before reset.
"$GIT" -C "$WORKDIR" status --porcelain=v1 > "$BACKUP/status-before.txt" 2>/dev/null || true
"$GIT" -C "$WORKDIR" rev-parse HEAD > "$BACKUP/head-before.txt" 2>/dev/null || true
"$GIT" -C "$WORKDIR" branch --show-current > "$BACKUP/branch-before.txt" 2>/dev/null || true
"$GIT" -C "$WORKDIR" diff > "$BACKUP/tracked-working.diff" 2>/dev/null || true
"$GIT" -C "$WORKDIR" diff --cached > "$BACKUP/tracked-index.diff" 2>/dev/null || true
"$GIT" -C "$WORKDIR" ls-files --others --exclude-standard > "$BACKUP/untracked-files.txt" 2>/dev/null || true
[ -f "$STATE" ] && cp "$STATE" "$BACKUP/issue-12.json.before"

# Keep a local pointer to the old checkout commit if it exists.
OLD_HEAD="$("$GIT" -C "$WORKDIR" rev-parse HEAD 2>/dev/null || true)"
if [ -n "$OLD_HEAD" ]; then
  "$GIT" -C "$WORKDIR" branch -f "backup/pre-final-runner-repair-$(date '+%Y%m%d-%H%M%S')" "$OLD_HEAD" >/dev/null 2>&1 || true
fi

# 3) Make runner checkout exactly match the approved composite remote head.
"$GIT" -C "$WORKDIR" fetch origin "$BRANCH" >/dev/null 2>&1 || fail "git-fetch-failed"
"$GIT" -C "$WORKDIR" checkout -B "$BRANCH" "origin/$BRANCH" >/dev/null 2>&1 || fail "checkout-reset-failed"
"$GIT" -C "$WORKDIR" reset --hard "$NEW_SHA" >/dev/null 2>&1 || fail "hard-reset-failed"

ACTUAL="$("$GIT" -C "$WORKDIR" rev-parse HEAD)"
[ "$ACTUAL" = "$NEW_SHA" ] || fail "local-head-mismatch:$ACTUAL"

# 4) Repair only Issue #12 stale SHA references in its runner state.
if [ -f "$STATE" ]; then
  python3 - "$STATE" "$OLD_SHA" "$NEW_SHA" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); old=sys.argv[2]; new=sys.argv[3]
data=json.loads(p.read_text())
def walk(v):
    if isinstance(v, dict):
        return {k: walk(x) for k,x in v.items()}
    if isinstance(v, list):
        return [walk(x) for x in v]
    if isinstance(v, str):
        return new if v == old else v.replace(old, new)
    return v
data=walk(data)
p.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
PY
  cp "$STATE" "$BACKUP/issue-12.json.after"
fi

# 5) Re-confirm the approved trigger still exists.
LABELS="$("$GH" api "repos/tokpmpm/life-balance-game/issues/12" --jq '[.labels[].name] | join(",")' 2>/dev/null || true)"
case ",$LABELS," in
  *,repair-approved,*) ;;
  *) fail "repair-approved-label-missing:$LABELS" ;;
esac

# 6) Restart old runner cleanly.
/bin/launchctl bootstrap "gui/$UID" "$PLIST" >/dev/null 2>&1 || fail "launchctl-bootstrap-failed"
/bin/launchctl kickstart -k "gui/$UID/$LABEL" >/dev/null 2>&1 || fail "launchctl-kickstart-failed"

# 7) Wait up to 90s for actual workflow transition.
for _ in $(seq 1 18); do
  sleep 5
  LABELS_NOW="$("$GH" api "repos/tokpmpm/life-balance-game/issues/12" --jq '[.labels[].name] | join(",")' 2>/dev/null || true)"
  case ",$LABELS_NOW," in
    *,codex-running,*|*,repair-running,*)
      echo "RESULT=PASS"
      echo "STATE=RUNNING"
      echo "LOCAL_HEAD=$ACTUAL"
      echo "LABELS=$LABELS_NOW"
      echo "BACKUP=$BACKUP"
      exit 0
      ;;
  esac
  case ",$LABELS_NOW," in
    *,repair-approved,*) ;;
    *)
      echo "RESULT=PASS"
      echo "STATE=TRIGGER_CONSUMED"
      echo "LOCAL_HEAD=$ACTUAL"
      echo "LABELS=$LABELS_NOW"
      echo "BACKUP=$BACKUP"
      exit 0
      ;;
  esac
done

# 8) Final diagnosis in the same run. No third blind test.
echo "RESULT=FAIL"
echo "ROOT_CAUSE=runner-still-did-not-transition"
echo "LOCAL_HEAD=$ACTUAL"
echo "LABELS=$LABELS"
echo "=== launchctl ==="
/bin/launchctl print "gui/$UID/$LABEL" 2>&1 | egrep 'state =|pid =|last exit code =|program =|stdout path =|stderr path =' || true
echo "=== recent stderr ==="
tail -n 80 "$WORKDIR/.codex-runner/logs/launchd.err.log" 2>/dev/null || true
echo "=== recent stdout ==="
tail -n 80 "$WORKDIR/.codex-runner/logs/launchd.out.log" 2>/dev/null || true
echo "BACKUP=$BACKUP"
exit 21
