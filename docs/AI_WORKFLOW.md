# AI WORKFLOW

## Goal

Deliver work in one controlled path instead of using the user as an iterative QA loop.

## State machine

```text
PLANNING
  → CODEX_READY
  → CODEX_RUNNING
  → CI_PENDING
  → REVIEWING
      → REVIEW_APPROVED
      → REPAIR_AWAITING_PLAN
      → REVIEW_ERROR

REPAIR_AWAITING_PLAN
  → REPAIR_APPROVED
  → CODEX_RUNNING
  → CI_PENDING
  → REVIEWING (DELTA REVIEW)

After 2 failed formal repair rounds
  → CODEX_NEEDS_HUMAN
```

GitHub labels mirror the operational state where practical; GitHub itself remains the live source for PR/CI/review status.

## Standard delivery

1. ChatGPT converts the request into a scoped Issue with measurable Acceptance Criteria.
2. Classify risk: LOW, MEDIUM, or HIGH.
3. Codex works only from the approved Issue/Repair Plan.
4. For MEDIUM/HIGH, execute the One-Shot Delivery protocol before editing.
5. Run targeted tests, required real-flow validation, negative/failure cases, and full regression.
6. Commit and push a feature branch.
7. Run CI against the exact pushed SHA.
8. Only after that exact SHA passes CI may an isolated Reviewer begin.
9. Reviewer returns `APPROVE`, `REQUEST_CHANGES`, or `REVIEW_ERROR`.
10. `APPROVE` enters the release gate; merge/deploy still require explicit user approval.

## Risk classification

- **LOW** — isolated documentation/copy/style change with no persistence, auth, money, destructive operation, shared state, or critical flow.
- **MEDIUM** — user-visible behavior, state transitions, API/data flow, responsive UI, or meaningful regression surface.
- **HIGH** — auth/permissions, money, destructive writes, migrations, production infrastructure, concurrency/shared state, security-sensitive data, or broad architectural change.

When uncertain, choose the higher class.

## Reviewer error path

`REVIEW_ERROR` means the reviewer execution failed, not the product.

- Keep the same product SHA.
- Do not increment repair round.
- Do not call Developer/Codex.
- Do not rerun regression or CI merely because reviewer infrastructure failed.
- A fresh reviewer may retry once.
- If the retry also fails, mark `review-error` and require human/infrastructure handling.

## Review-only recovery

Recovery is explicit opt-in for the case where product SHA is unchanged and exact-SHA CI already passed. It may invoke only a fresh Independent Reviewer. It must not modify or revalidate the product through Developer/Codex.

## Repair path

A reviewer blocker is analyzed by ChatGPT first. Codex must not invent a repair plan. The user approves the plan before Codex executes it. Formal product repairs are capped at two rounds; a further attempt must be separately recorded as a user-approved exceptional repair, never as a silent increase to the configured limit.
