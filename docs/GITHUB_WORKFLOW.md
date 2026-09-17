# GITHUB WORKFLOW

GitHub is the durable operational source of truth.

## Issue as unit of work

Each development Issue contains:

- Goal
- User Value
- Risk
- Scope
- Must Not Change
- Implementation Requirements
- Real Flow Validation
- Negative / Failure Cases
- Acceptance Criteria
- Regression Requirements
- Delivery Requirements

Acceptance Criteria must be observable and verifiable. `功能正常` / `works correctly` is not sufficient.

For stateful flows, describe the real path where applicable: `user action → writer → state → persistence → reader → UI result`.

## Branch and PR

- Product work: `feature/<issue>-<slug>` or `fix/<issue>-<slug>`.
- Runner infrastructure: `chore/local-codex-runner` or a dedicated `chore/runner-*` branch.
- Product and Runner changes must not be mixed in one repair round.
- Push the candidate commit before review.
- Reviewer inspects the exact pushed SHA, not a dirty tree or a different commit.

## CI

The candidate SHA must pass GitHub CI before Independent Review starts. `.github/workflows/review.yml` verifies checkout SHA and framework integrity. In a real product repo with a recognized product marker, provide executable `ci/ai-verify.sh`; that script is the project's single CI validation entrypoint.

## Labels

Recommended state labels:

- `codex-ready` — approved Issue ready for implementation
- `codex-running` — implementation/repair in progress
- `reviewing` — exact-SHA CI passed; reviewer active
- `review-approved` — reviewer returned APPROVE
- `review-error` — reviewer infrastructure/execution failed
- `repair-awaiting-plan` — valid blocker exists; no approved repair yet
- `repair-approved` — user approved a specific Repair Plan
- `codex-needs-human` — automation stopped after repair limit or unresolved infrastructure problem
- `blocked` — external dependency prevents progress

Avoid multiple contradictory stage labels. Transition the operational label instead of accumulating stale states.

## Durable vs live state

Store stable architecture, decisions, checkpoints, known limitations, and next recommended step in `docs/PROJECT_STATE.md`. Query GitHub live for open Issues/PRs, branch/SHA, Actions, and current reviews.

## Evidence

PR/Issue comments should record exact SHA, commands or CI run links, real-flow evidence, reviewer result, and approved Repair Plan IDs. Do not claim a result from a different SHA.

## Protected actions

Issue/comment/label/branch/PR operations may be automated when safe. Merge to `main`, production deploy, and production mutation require explicit user approval for that specific action.
