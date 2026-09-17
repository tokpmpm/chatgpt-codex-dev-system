# Repair Planning

## Purpose
Turn valid Reviewer blockers into the smallest auditable Repair Plan before Codex changes product code.

## When to use
Use only after `REQUEST_CHANGES`. Do not use for `REVIEW_ERROR`.

## Inputs
- current Issue and Acceptance Criteria
- reviewed TARGET_SHA
- reviewer blockers/evidence
- current repair-round count
- relevant source/test context

## Procedure
1. Verify the verdict is `REQUEST_CHANGES` and blockers are tied to requirements.
2. Diagnose evidence-backed root cause for each blocker.
3. Define the minimum changes that resolve all blockers without opportunistic refactoring.
4. Define `DO_NOT_CHANGE` protections from the Issue and prior passing behavior.
5. Define targeted, real-flow/negative, regression, and exact-SHA CI validation.
6. Fill `templates/REPAIR_PLAN.md` with a unique `PLAN_ID`, TARGET_SHA, and REPAIR_ROUND.
7. Mark plan `DRAFT` and obtain explicit user approval before Codex execution.
8. Record approval durably in GitHub (Issue/PR comment) when possible.

## Safety rules
- Maximum normal formal repair rounds: 2.
- Reviewer errors and Runner fixes do not consume product repair rounds.
- Never silently change the maximum to 3.
- A further attempt must be recorded as `human-approved exceptional repair`.
- Codex must not choose a different repair strategy without a newly approved plan.

## Expected output
A complete `REPAIR_PLAN` with `STATUS: DRAFT` or, after explicit approval is recorded, `STATUS: APPROVED`.

## Failure handling
If blockers are contradictory, unsupported, or outside the Issue, stop and resolve review validity before planning repair. If the two-round limit is exhausted, return `codex-needs-human`.
