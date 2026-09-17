# AGENTS.md

This file is the mandatory entrypoint for every ChatGPT, Codex, and Independent Reviewer session using this repository.

## Source of truth

Do not assume a previous chat/session is correct or complete. Durable truth comes from:

1. the current GitHub Issue / approved Repair Plan,
2. the exact repository commit and diff,
3. tests and real-flow evidence,
4. GitHub CI/review state,
5. `docs/PROJECT_STATE.md` for stable context and checkpoints.

Dynamic PR, Actions, and review status must be queried from GitHub when needed; do not hard-code them into `PROJECT_STATE.md`.

## Mandatory startup

Before doing work:

1. Read `AGENTS.md`.
2. Read `docs/PROJECT_STATE.md`.
3. Read `docs/AI_WORKFLOW.md`.
4. Read `docs/REVIEW_PROTOCOL.md`.
5. Read the current Issue and its Acceptance Criteria; read the current PR/Repair Plan when applicable.
6. Verify current branch, exact `HEAD`, and working-tree status.
7. If the tree is dirty, identify whether changes are user-owned or task-owned before touching them.
8. Query GitHub for the latest relevant PR, exact-SHA CI, and review state instead of relying on remembered state.

## Hard safety rules

- Never discard, reset, overwrite, or hide unconfirmed user changes.
- Never silently expand scope beyond the current Issue / approved Repair Plan.
- Never weaken, delete, bypass, or rewrite tests merely to make CI pass.
- Never modify a golden baseline/snapshot solely to hide a regression; baseline changes require explicit requirement/evidence.
- Reviewers are read-only: no code edits, commits, pushes, merge, deploy, or reimplementation.
- Review only the exact commit SHA that was pushed and passed CI.
- `REQUEST_CHANGES` and `REVIEW_ERROR` are different states. Infrastructure/provider errors are not product rejection.
- Product repair rounds and runner-infrastructure repairs are tracked separately.
- Formal product repair is capped at 2 rounds unless the user explicitly authorizes a separately recorded exceptional repair.
- Review-only recovery keeps the same product SHA and must not call Developer/Codex, rerun regression, rerun CI, commit, push, merge, or deploy.
- Do not merge into `main` or deploy/mutate production without the user's explicit approval for that specific action.

## Scope discipline

Every implementation must respect:

- `Scope`
- `Must Not Change`
- Acceptance Criteria
- Regression Requirements
- approved Repair Plan, if any

If a discovered problem is outside scope and is not required to satisfy an Acceptance Criterion, record it as `Deferred` or a separate Issue rather than fixing it opportunistically.

## Validation discipline

A green synthetic/fixture test does not replace a required real user flow. For stateful features, trace the real chain where applicable:

`user action → writer → state → persistence → reader → UI result`

Medium/high-risk work follows `docs/ONE_SHOT_DELIVERY_PROTOCOL.md` before reporting `READY FOR REVIEW`.

## Session completion

Before handing off, record stable decisions/checkpoints in `docs/PROJECT_STATE.md` when they materially changed. Do not copy volatile Actions/PR status into that file. Ensure GitHub contains enough Issue/PR/commit/test/review evidence for a fresh session to reconstruct the current stage.
