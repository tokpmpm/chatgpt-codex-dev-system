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
BIN_LINK="$BIN_DIR/ai-dev"
BIN_BACKUP="$PREFIX/.bin-backup-$$"

if [[ -e "$CURRENT" && ! -L "$CURRENT" ]]; then
  echo "refusing to replace non-symlink active path: $CURRENT" >&2
  exit 2
fi

OLD_TARGET=""
[[ -L "$CURRENT" ]] && OLD_TARGET="$(readlink "$CURRENT")"

OLD_BIN_KIND="none"
OLD_BIN_TARGET=""
if [[ -L "$BIN_LINK" ]]; then
  OLD_BIN_KIND="symlink"
  OLD_BIN_TARGET="$(readlink "$BIN_LINK")"
elif [[ -e "$BIN_LINK" ]]; then
  if [[ ! -f "$BIN_LINK" ]]; then
    echo "refusing to replace non-file command path: $BIN_LINK" >&2
    exit 2
  fi
  OLD_BIN_KIND="file"
  cp -p "$BIN_LINK" "$BIN_BACKUP"
fi

cleanup() {
  rm -rf "$STAGE"
  rm -f "$BIN_BACKUP"
}
trap cleanup EXIT

rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$HERE"/. "$STAGE"/
chmod +x "$STAGE/ai-dev" "$STAGE/install.sh" "$STAGE/self-test.sh"

# Validate the staged copy before it can become active.
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
    atomic_link "$OLD_TARGET" "$CURRENT" || true
  else
    rm -f "$CURRENT"
  fi

  case "$OLD_BIN_KIND" in
    symlink)
      atomic_link "$OLD_BIN_TARGET" "$BIN_LINK" || true
      ;;
    file)
      rm -f "$BIN_LINK"
      cp -p "$BIN_BACKUP" "$BIN_LINK" || true
      ;;
    none)
      rm -f "$BIN_LINK"
      ;;
  esac

  rm -rf "$RELEASE"
}

if ! atomic_link "$RELEASE" "$CURRENT"; then
  rollback
  echo "failed to activate runner; previous version restored" >&2
  exit 1
fi
if ! atomic_link "$CURRENT/ai-dev" "$BIN_LINK"; then
  rollback
  echo "failed to activate command link; previous version restored" >&2
  exit 1
fi

# Deterministic fixture hook used only to prove rollback behavior.
if [[ "${AI_DEV_TEST_FORCE_INSTALL_FAILURE:-0}" == "1" ]]; then
  rollback
  echo "forced post-activation install failure; previous version restored" >&2
  exit 1
fi

if ! "$BIN_LINK" self-test; then
  rollback
  echo "installed runner self-test failed; previous version restored" >&2
  exit 1
fi

rm -f "$BIN_BACKUP"
trap - EXIT
printf 'ai-dev installed\n  release: %s\n  command: %s\n' "$RELEASE" "$BIN_LINK"
