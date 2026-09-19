#!/bin/bash
set -euo pipefail

REPO="tokpmpm/chatgpt-codex-dev-system"
BOOTSTRAP_REF="${AI_DEV_BOOTSTRAP_REF:-chore/remote-control-bridge}"
INBOX_ISSUE="3"
LABEL="com.meshthings.ai-dev-control-bridge"
LIB_DIR="$HOME/.local/lib/ai-dev-control-bridge"
STATE_DIR="$HOME/.local/state/ai-dev-control-bridge"
LOG_DIR="$HOME/Library/Logs/ai-dev-control-bridge"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
BRIDGE="$LIB_DIR/bridge.sh"
WORKER="$LIB_DIR/worker.sh"
CONFIG="$LIB_DIR/config.env"

find_cmd() {
  local name="$1"
  command -v "$name" 2>/dev/null || true
}

GH_BIN="$(find_cmd gh)"
if [ -z "$GH_BIN" ]; then
  for p in /opt/homebrew/bin/gh /usr/local/bin/gh /usr/bin/gh; do
    if [ -x "$p" ]; then GH_BIN="$p"; break; fi
  done
fi

if [ -z "$GH_BIN" ] || [ ! -x "$GH_BIN" ]; then
  echo "ERROR: gh not found"
  exit 2
fi

if ! "$GH_BIN" auth status >/dev/null 2>&1; then
  echo "ERROR: gh is not authenticated"
  exit 3
fi

mkdir -p "$LIB_DIR" "$STATE_DIR" "$LOG_DIR" "$HOME/Library/LaunchAgents"

TMP="$BRIDGE.tmp.$$"
"$GH_BIN" api "repos/$REPO/contents/bootstrap/ai-dev-control-bridge.sh?ref=$BOOTSTRAP_REF" --jq .content \
  | tr -d '\n' \
  | base64 -D > "$TMP"
chmod 700 "$TMP"
mv "$TMP" "$BRIDGE"

TMP_WORKER="$WORKER.tmp.$"
"$GH_BIN" api "repos/$REPO/contents/bootstrap/ai-dev-control-worker.sh?ref=$BOOTSTRAP_REF" --jq .content   | tr -d '\n'   | base64 -D > "$TMP_WORKER"
chmod 700 "$TMP_WORKER"
mv "$TMP_WORKER" "$WORKER"

cat > "$CONFIG" <<EOF
REPO="$REPO"
INBOX_ISSUE="$INBOX_ISSUE"
GH_BIN="$GH_BIN"
LABEL="$LABEL"
EOF
chmod 600 "$CONFIG"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BRIDGE</string>
    <string>--daemon</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>10</integer>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/stdout.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/stderr.log</string>
  <key>ProcessType</key>
  <string>Background</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$UID/$LABEL" >/dev/null 2>&1 || true
rm -rf "$STATE_DIR/lock"
launchctl bootstrap "gui/$UID" "$PLIST"
launchctl kickstart -k "gui/$UID/$LABEL"

sleep 2
if ! launchctl print "gui/$UID/$LABEL" >/dev/null 2>&1; then
  echo "ERROR: control bridge service failed to load"
  exit 4
fi

if [ ! -f "$STATE_DIR/heartbeat" ]; then
  echo "ERROR: control bridge heartbeat missing"
  exit 5
fi

echo "AI Dev control bridge installed."
echo "Inbox: https://github.com/$REPO/issues/$INBOX_ISSUE"
echo "Service: $LABEL"
