#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

printf '== source runner ==\n'
python3 "$HERE/entrypoint.py" self-test

printf '== staged runner ==\n'
mkdir -p "$TMP/staged"
cp -R "$HERE"/. "$TMP/staged"/
chmod +x "$TMP/staged/ai-dev" "$TMP/staged/install.sh" "$TMP/staged/self-test.sh"
python3 "$TMP/staged/entrypoint.py" self-test

printf '== installed runner ==\n'
AI_DEV_PREFIX="$TMP/prefix" AI_DEV_BIN_DIR="$TMP/bin" \
  bash "$HERE/install.sh" --prefix "$TMP/prefix" --bin-dir "$TMP/bin" --version fixture
"$TMP/bin/ai-dev" self-test

printf 'Runner source/staged/installed self-test: PASS\n'
