#!/bin/bash
set -u

LABEL="com.meshthings.life-balance-codex-runner"
RUNNER="$HOME/.local/lib/life-balance-codex-runner/runner.sh"
CONFIG="$HOME/.config/life-balance-codex-runner/config.env"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
BACKUP="$HOME/.local/state/life-balance-runner-repair/$(date '+%Y%m%d-%H%M%S')"
ONELOG="$BACKUP/repair.log"

mkdir -p "$BACKUP"
exec > >(tee "$ONELOG") 2>&1

echo "=== Life Balance Runner one-shot repair ==="

fail() {
  echo "RESULT=NEEDS_SECOND_STEP"
  echo "ROOT_CAUSE=$1"
  exit 20
}

for file in "$RUNNER" "$CONFIG" "$PLIST"; do
  [ -f "$file" ] || fail "missing:$file"
done

cp "$RUNNER" "$BACKUP/runner.sh"
cp "$CONFIG" "$BACKUP/config.env"
cp "$PLIST" "$BACKUP/runner.plist"

bash -n "$RUNNER" >/dev/null 2>&1 || fail "runner-shell-syntax"
plutil -lint "$PLIST" >/dev/null 2>&1 || fail "invalid-launchagent-plist"

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

GH_REAL="$(command -v gh 2>/dev/null || true)"
CODEX_REAL="$(command -v codex 2>/dev/null || true)"
GIT_REAL="$(command -v git 2>/dev/null || true)"

[ -n "$GH_REAL" ] || fail "gh-not-found"
[ -n "$CODEX_REAL" ] || fail "codex-not-found"
[ -n "$GIT_REAL" ] || fail "git-not-found"

"$GH_REAL" auth status >/dev/null 2>&1 || fail "gh-auth-failed"

replace_path_if_stale() {
  local key="$1" value="$2" current
  current="$(sed -n "s/^${key}=//p" "$CONFIG" | tail -1 | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")"
  if [ -n "$current" ] && [ ! -x "$current" ]; then
    python3 - "$CONFIG" "$key" "$value" <<'PY'
import pathlib, re, sys
p=pathlib.Path(sys.argv[1]); key=sys.argv[2]; value=sys.argv[3]
s=p.read_text()
pat=re.compile(rf'^{re.escape(key)}=.*$', re.M)
line=f'{key}="{value}"'
if pat.search(s): s=pat.sub(line,s)
else: s += ('\n' if s and not s.endswith('\n') else '') + line + '\n'
p.write_text(s)
PY
    echo "REPAIRED_PATH $key -> $value"
  fi
}

replace_path_if_stale GH_BIN "$GH_REAL"
replace_path_if_stale CODEX_BIN "$CODEX_REAL"
replace_path_if_stale REVIEW_CODEX_BIN "$CODEX_REAL"
replace_path_if_stale GIT_BIN "$GIT_REAL"

. "$CONFIG"

REPO="${REPO:-tokpmpm/life-balance-game}"
APPROVED="${REPAIR_APPROVED_LABEL:-repair-approved}"
RUNNING="${RUNNING_LABEL:-codex-running}"
TARGET_ISSUE="12"

case "$REPO" in
  tokpmpm/life-balance-game) ;;
  *) fail "unexpected-repo:$REPO" ;;
esac

feature_sha="$("$GH_REAL" api "repos/$REPO/branches/feature%2Fv8.6.0" --jq .commit.sha 2>/dev/null || true)"
[ "$feature_sha" = "5447227ce532a5eebbf3cc2ecc3520dbfb3ff8cc" ] || fail "unexpected-feature-head:$feature_sha"

labels_before="$("$GH_REAL" api "repos/$REPO/issues/$TARGET_ISSUE" --jq '[.labels[].name] | join(",")' 2>/dev/null || true)"
case ",$labels_before," in
  *",$APPROVED,"*) ;;
  *) fail "repair-approved-label-missing:$labels_before" ;;
esac

stdout_path="$(/usr/libexec/PlistBuddy -c 'Print :StandardOutPath' "$PLIST" 2>/dev/null || true)"
stderr_path="$(/usr/libexec/PlistBuddy -c 'Print :StandardErrorPath' "$PLIST" 2>/dev/null || true)"
[ -n "$stdout_path" ] && mkdir -p "$(dirname "$stdout_path")"
[ -n "$stderr_path" ] && mkdir -p "$(dirname "$stderr_path")"

/bin/launchctl bootout "gui/$UID/$LABEL" >/dev/null 2>&1 || true
sleep 1
/bin/launchctl bootstrap "gui/$UID" "$PLIST" >/dev/null 2>&1 || fail "launchctl-bootstrap-failed"
/bin/launchctl kickstart -k "gui/$UID/$LABEL" >/dev/null 2>&1 || fail "launchctl-kickstart-failed"

echo "LAUNCHAGENT_RELOADED=yes"
echo "WAITING_FOR_RUNNER_TRANSITION=yes"

transition=""
for _ in $(seq 1 12); do
  sleep 5
  labels_now="$("$GH_REAL" api "repos/$REPO/issues/$TARGET_ISSUE" --jq '[.labels[].name] | join(",")' 2>/dev/null || true)"
  case ",$labels_now," in
    *",$RUNNING,"*) transition="running-label:$RUNNING"; break ;;
  esac
  case ",$labels_now," in
    *",$APPROVED,"*) ;;
    *) transition="approved-label-consumed:$labels_now"; break ;;
  esac
done

if [ -n "$transition" ]; then
  echo "RESULT=PASS"
  echo "TRANSITION=$transition"
  echo "FEATURE_SHA=$feature_sha"
  echo "BACKUP=$BACKUP"
  exit 0
fi

echo "=== launchctl ==="
/bin/launchctl print "gui/$UID/$LABEL" 2>&1 | egrep 'state =|pid =|last exit code =|program =|stdout path =|stderr path =' || true

echo "=== stdout tail ==="
if [ -n "$stdout_path" ] && [ -f "$stdout_path" ]; then
  tail -n 100 "$stdout_path"
else
  echo "stdout-unavailable:$stdout_path"
fi

echo "=== stderr tail ==="
if [ -n "$stderr_path" ] && [ -f "$stderr_path" ]; then
  tail -n 100 "$stderr_path"
else
  echo "stderr-unavailable:$stderr_path"
fi

runtime="${RUNTIME_DIR:-}"
if [ -n "$runtime" ] && [ -d "$runtime" ]; then
  echo "=== runtime recent files ==="
  find "$runtime" -maxdepth 2 -type f -mmin -180 -print 2>/dev/null | head -n 50
  echo "=== stale target references ==="
  grep -RIl '159388c7aa04a93d8815194127bfc9188de5d5c2\|pending target SHA' "$runtime" 2>/dev/null | head -n 30 || true
fi

echo "RESULT=NEEDS_SECOND_STEP"
echo "ROOT_CAUSE=runner-did-not-consume-approved-trigger"
echo "FEATURE_SHA=$feature_sha"
echo "BACKUP=$BACKUP"
exit 21
