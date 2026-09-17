# REPAIR PROTOCOL

## Trigger

Use only after a valid Independent Reviewer `REQUEST_CHANGES` verdict.

## Flow

```text
Reviewer REQUEST_CHANGES
  → ChatGPT analyzes blockers
  → ChatGPT creates minimal Repair Plan
  → user explicitly approves plan
  → Codex executes only that plan
  → targeted validation + regression
  → new commit + push
  → exact new-SHA CI PASS
  → fresh Reviewer DELTA REVIEW
```

Codex must not choose the repair strategy on its own before plan approval.

## Repair Plan contract

Every plan contains:

```text
PLAN_ID:
STATUS: DRAFT|APPROVED|EXECUTED
ISSUE:
TARGET_SHA:
REPAIR_ROUND:

ROOT_CAUSE:

CHANGES:

DO_NOT_CHANGE:

VALIDATION:
```

The plan should be the smallest change that resolves the documented blockers without broad refactoring.

## Round safety

- Maximum formal product repair rounds: 2.
- Round count increases only when an approved product Repair Plan is executed after `REQUEST_CHANGES`.
- Runner/infrastructure fixes do not consume product repair rounds.
- Reviewer execution errors do not consume product repair rounds.
- After two failed formal rounds, stop automation and mark `codex-needs-human`.
- A third attempt is allowed only as a separately recorded `human-approved exceptional repair`; never change the normal maximum from 2 to 3 behind the scenes.

## Review-only recovery

When product SHA is unchanged and exact-SHA CI already passed, an explicit recovery may retry only the Reviewer. It must not call Codex/Developer, rerun regression, rerun CI, create a product commit, push product changes, merge, or deploy.
