#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/tools/ai-dev/ai-dev"
BRIDGE_SRC="$ROOT/bootstrap/ai-dev-control-bridge.sh"
VERSION_SHA="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || date +%s)"
BASE="$HOME/.local/lib/ai-dev"
VERSIONS="$BASE/versions"
TARGET="$VERSIONS/$VERSION_SHA"
ACTIVE="$BASE/active"
BIN_DIR="$HOME/.local/bin"
BIN="$BIN_DIR/ai-dev"
BRIDGE_DIR="$HOME/.local/lib/ai-dev-control-bridge"
BRIDGE="$BRIDGE_DIR/bridge.sh"
PLIST="$HOME/Library/LaunchAgents/com.meshthings.ai-dev-control-bridge.plist"
OLD_ACTIVE=""

[ -f "$SRC" ] || { echo "missing $SRC"; exit 2; }
mkdir -p "$VERSIONS" "$TARGET" "$BIN_DIR" "$BRIDGE_DIR"

if [ -L "$ACTIVE" ]; then
  OLD_ACTIVE="$(readlink "$ACTIVE" || true)"
fi

cp "$SRC" "$TARGET/ai-dev"
chmod 700 "$TARGET/ai-dev"

echo "== source self-test =="
bash "$SRC" self-test

echo "== staged self-test =="
"$TARGET/ai-dev" self-test

ln -sfn "$TARGET" "$ACTIVE"
ln -sfn "$ACTIVE/ai-dev" "$BIN"

if [ -f "$BRIDGE_SRC" ]; then
  cp "$BRIDGE_SRC" "$BRIDGE.tmp"
  chmod 700 "$BRIDGE.tmp"
  mv "$BRIDGE.tmp" "$BRIDGE"
fi

set +e
"$BIN" doctor --repair
DOCTOR_RC=$?
set -e
if [ "$DOCTOR_RC" -ne 0 ]; then
  echo "doctor failed; rolling back"
  if [ -n "$OLD_ACTIVE" ]; then
    ln -sfn "$OLD_ACTIVE" "$ACTIVE"
    ln -sfn "$ACTIVE/ai-dev" "$BIN"
  else
    rm -f "$ACTIVE" "$BIN"
  fi
  exit "$DOCTOR_RC"
fi

if [ -f "$PLIST" ]; then
  launchctl bootout "gui/$UID/com.meshthings.ai-dev-control-bridge" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$UID" "$PLIST" >/dev/null 2>&1 || true
  launchctl kickstart -k "gui/$UID/com.meshthings.ai-dev-control-bridge" >/dev/null 2>&1 || true
fi

echo "AI Dev installed"
echo "version_sha=$VERSION_SHA"
echo "binary=$BIN"
