#!/usr/bin/env bash
set -euo pipefail

required=(
  README.md
  AGENTS.md
  docs/PROJECT_STATE.md
  docs/AI_WORKFLOW.md
  docs/REVIEW_PROTOCOL.md
  docs/ONE_SHOT_DELIVERY_PROTOCOL.md
  docs/REPAIR_PROTOCOL.md
  docs/GITHUB_WORKFLOW.md
  docs/SESSION_HANDOFF.md
  skills/product-planning/SKILL.md
  skills/issue-planning/SKILL.md
  skills/codex-development/SKILL.md
  skills/code-review/SKILL.md
  skills/repair-planning/SKILL.md
  skills/github-operator/SKILL.md
  skills/session-handoff/SKILL.md
  skills/release-gate/SKILL.md
  templates/ISSUE_TEMPLATE.md
  templates/ACCEPTANCE_CRITERIA.md
  templates/REPAIR_PLAN.md
  templates/REVIEW_RESULT.md
  templates/PROJECT_STATE.md
  templates/CODEX_PROMPT.md
  tools/codex-runner/README.md
)

for path in "${required[@]}"; do
  if [[ ! -f "$path" ]]; then
    echo "ERROR: missing required AI development system file: $path" >&2
    exit 1
  fi
done

# This repository is the framework itself. When copied into a product repo,
# replace/extend this script with real project validation before treating CI as a product gate.
product_detected=0
for marker in package.json pyproject.toml Cargo.toml go.mod index.html; do
  [[ -e "$marker" ]] && product_detected=1
done
[[ -d src || -d app ]] && product_detected=1

if [[ "$product_detected" -eq 1 ]]; then
  echo "ERROR: product repository detected, but ci/ai-verify.sh is still the framework-only template." >&2
  echo "Replace/extend it with targeted + real-flow-capable project regression before review." >&2
  exit 1
fi

grep -q "REVIEW_ERROR" docs/REVIEW_PROTOCOL.md
grep -q "Maximum formal product repair rounds: 2" docs/REPAIR_PROTOCOL.md
grep -q "explicit user approval" skills/release-gate/SKILL.md

if [[ -f tests/control-bridge-fixture.sh ]]; then
  bash tests/control-bridge-fixture.sh
fi

echo "Framework contract verification: PASS"
