#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRIDGE="$ROOT/bootstrap/ai-dev-control-bridge.sh"

bash -n "$ROOT/bootstrap/install-control-bridge.sh"
bash -n "$ROOT/bootstrap/ai-dev-control-bridge.sh"
bash -n "$ROOT/bootstrap/install-ai-dev.sh"
bash -n "$ROOT/tools/ai-dev/ai-dev"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME/.local/lib/ai-dev-control-bridge" \
         "$HOME/.local/state/ai-dev-control-bridge" \
         "$HOME/Library/Logs/ai-dev-control-bridge" \
         "$TMP/bin"

ISSUE_BODY="$TMP/issue-body"
PATCH_BODY="$TMP/patch-body"
CALL_LOG="$TMP/calls.log"

cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${ISSUE_BODY:?}"
: "${PATCH_BODY:?}"
: "${CALL_LOG:?}"
printf '%s\n' "$*" >> "$CALL_LOG"

if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  exit 0
fi

if [[ "${1:-}" == "api" ]]; then
  shift
  if [[ "${1:-}" == "--method" && "${2:-}" == "PATCH" ]]; then
    shift 2
    shift
    for arg in "$@"; do
      case "$arg" in
        body=*) printf '%s' "${arg#body=}" > "$PATCH_BODY" ;;
      esac
    done
    exit 0
  fi

  endpoint="${1:-}"
  shift || true
  if [[ "$endpoint" == "repos/tokpmpm/chatgpt-codex-dev-system/issues/3" ]]; then
    if [[ "${1:-}" == "--jq" && "${2:-}" == ".body" ]]; then
      cat "$ISSUE_BODY"
      exit 0
    fi
  fi
fi

echo "unsupported fake gh call: $*" >&2
exit 9
EOF
chmod +x "$TMP/bin/gh"

export ISSUE_BODY PATCH_BODY CALL_LOG
cat > "$HOME/.local/lib/ai-dev-control-bridge/config.env" <<EOF
REPO="tokpmpm/chatgpt-codex-dev-system"
INBOX_ISSUE="3"
GH_BIN="$TMP/bin/gh"
LABEL="com.meshthings.ai-dev-control-bridge"
EOF

write_ping() {
  cat > "$ISSUE_BODY" <<EOF
AI_DEV_COMMAND_BEGIN
COMMAND_ID: $1
ACTION: PING
AI_DEV_COMMAND_END
EOF
}

assert_pass_for() {
  local id="$1"
  grep -Fq "COMMAND_ID: $id" "$PATCH_BODY"
  grep -Fq "STATUS: PASS" "$PATCH_BODY"
  grep -Fq "DETAIL: bridge-ok" "$PATCH_BODY"
}

# 1) stale lock is self-healed.
mkdir -p "$HOME/.local/state/ai-dev-control-bridge/lock"
printf '999999\n' > "$HOME/.local/state/ai-dev-control-bridge/lock/pid"
write_ping "fixture-ping-1"
bash "$BRIDGE"
assert_pass_for "fixture-ping-1"
[[ ! -d "$HOME/.local/state/ai-dev-control-bridge/lock" ]]

# 2) a second independent invocation still works.
: > "$PATCH_BODY"
write_ping "fixture-ping-2"
bash "$BRIDGE"
assert_pass_for "fixture-ping-2"
[[ ! -d "$HOME/.local/state/ai-dev-control-bridge/lock" ]]

# 3) duplicate COMMAND_ID is ignored.
calls_before="$(wc -l < "$CALL_LOG" | tr -d ' ')"
: > "$PATCH_BODY"
bash "$BRIDGE"
calls_after="$(wc -l < "$CALL_LOG" | tr -d ' ')"
[[ ! -s "$PATCH_BODY" ]]
[[ "$calls_after" -gt "$calls_before" ]]

# 4) syntax + ai-dev self-test.
bash "$ROOT/tools/ai-dev/ai-dev" self-test | grep -Fq "PASS branch-lease"

echo "Control bridge fixture: PASS"
