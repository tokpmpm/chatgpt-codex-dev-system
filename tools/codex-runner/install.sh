#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${AI_DEV_PREFIX:-$HOME/.local/share/ai-dev}"
BIN_DIR="${AI_DEV_BIN_DIR:-$HOME/.local/bin}"
VERSION="${AI_DEV_VERSION:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --bin-dir) BIN_DIR="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  VERSION="$(git -C "$HERE" rev-parse --short HEAD 2>/dev/null || date +%Y%m%d%H%M%S)"
fi

mkdir -p "$PREFIX/releases" "$BIN_DIR"
STAGE="$PREFIX/.staging-$VERSION-$$"
RELEASE="$PREFIX/releases/$VERSION"
CURRENT="$PREFIX/current"
OLD_TARGET=""
[[ -L "$CURRENT" ]] && OLD_TARGET="$(readlink "$CURRENT")"

cleanup() {
  rm -rf "$STAGE"
}
trap cleanup EXIT

rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$HERE"/. "$STAGE"/
chmod +x "$STAGE/ai-dev" "$STAGE/install.sh" "$STAGE/self-test.sh"

python3 "$STAGE/entrypoint.py" self-test

if [[ -e "$RELEASE" ]]; then
  RELEASE="$PREFIX/releases/${VERSION}-$(date +%s)-$$"
fi
mv "$STAGE" "$RELEASE"

atomic_link() {
  local target="$1"
  local link="$2"
  python3 - "$target" "$link" <<'PY'
import os, sys

target, link = sys.argv[1], sys.argv[2]
tmp = f"{link}.new.{os.getpid()}"
try:
    os.unlink(tmp)
except FileNotFoundError:
    pass
os.symlink(target, tmp)
os.replace(tmp, link)
PY
}

rollback() {
  if [[ -n "$OLD_TARGET" ]]; then
    atomic_link "$OLD_TARGET" "$CURRENT"
  else
    rm -f "$CURRENT"
  fi
}

atomic_link "$RELEASE" "$CURRENT"
atomic_link "$CURRENT/ai-dev" "$BIN_DIR/ai-dev"

if ! "$BIN_DIR/ai-dev" self-test; then
  rollback
  echo "installed runner self-test failed; previous active version restored" >&2
  exit 1
fi

trap - EXIT
printf 'ai-dev installed\n  release: %s\n  command: %s\n' "$RELEASE" "$BIN_DIR/ai-dev"
