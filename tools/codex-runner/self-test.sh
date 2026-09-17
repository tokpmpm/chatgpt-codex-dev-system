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

printf '== transactional rollback ==\n'
ROLL_PREFIX="$TMP/rollback-prefix"
ROLL_BIN="$TMP/rollback-bin"
OLD_RELEASE="$ROLL_PREFIX/releases/old"
mkdir -p "$OLD_RELEASE" "$ROLL_BIN"
cat > "$OLD_RELEASE/ai-dev" <<'EOF'
#!/usr/bin/env bash
echo OLD_RUNNER
EOF
chmod +x "$OLD_RELEASE/ai-dev"
ln -s "$OLD_RELEASE" "$ROLL_PREFIX/current"
ln -s "$ROLL_PREFIX/current/ai-dev" "$ROLL_BIN/ai-dev"
OLD_CURRENT_LINK="$(readlink "$ROLL_PREFIX/current")"
OLD_BIN_LINK="$(readlink "$ROLL_BIN/ai-dev")"

if AI_DEV_TEST_FORCE_INSTALL_FAILURE=1 AI_DEV_PREFIX="$ROLL_PREFIX" AI_DEV_BIN_DIR="$ROLL_BIN" \
  bash "$HERE/install.sh" --prefix "$ROLL_PREFIX" --bin-dir "$ROLL_BIN" --version forced-failure; then
  echo "ERROR: forced install failure unexpectedly succeeded" >&2
  exit 1
fi

[[ "$(readlink "$ROLL_PREFIX/current")" == "$OLD_CURRENT_LINK" ]]
[[ "$(readlink "$ROLL_BIN/ai-dev")" == "$OLD_BIN_LINK" ]]
[[ "$("$ROLL_BIN/ai-dev")" == "OLD_RUNNER" ]]
[[ ! -e "$ROLL_PREFIX/releases/forced-failure" ]]

printf 'Runner source/staged/installed/rollback self-test: PASS\n'
