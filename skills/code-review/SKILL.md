# Code Review

## Purpose
Provide an independent, read-only verdict against the Issue's Acceptance Criteria for the exact pushed product SHA.

## When to use
Use only after exact-SHA GitHub CI is confirmed PASS. Use FULL REVIEW for the first review and DELTA REVIEW after an approved repair.

## Inputs
- Issue + Acceptance Criteria
- exact product SHA
- CI evidence for that SHA
- exact diff/relevant source
- test, real-flow, and negative-case evidence
- previous blockers + approved Repair Plan for Delta Review

## Procedure
1. Start from a fresh isolated Reviewer session.
2. Verify the product SHA matches the pushed commit and CI evidence.
3. For FULL REVIEW, inspect every Acceptance Criterion, regression rule, and `Must Not Change` item affected by the diff.
4. For DELTA REVIEW, inspect previous blockers, plan, before/after SHA, exact repair diff, targeted evidence, and affected carried-forward requirements.
5. Build the required review matrix from real source paths and evidence.
6. Return exactly one semantic outcome: `APPROVE`, `REQUEST_CHANGES`, or `REVIEW_ERROR`.
7. A blocker must be concrete and map to an AC/regression/safety requirement.

## Safety rules
- Read-only: no edits, commits, pushes, merge, deploy, or reimplementation.
- Never review a working tree or a SHA different from the green CI SHA.
- Do not turn preferences/unrelated refactors into blockers.
- Do not turn provider/timeout/network/invalid-output failures into `REQUEST_CHANGES`.

## Expected output
Use the exact structures in `templates/REVIEW_RESULT.md` and `docs/REVIEW_PROTOCOL.md`, including `REVIEW_MATRIX_BEGIN/END`.

## Failure handling
Return `REVIEW_ERROR` with type, product SHA, retryability, and concise diagnostic. Do not increase repair round or request product changes.
