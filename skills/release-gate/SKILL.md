# Release Gate

## Purpose
Prevent merge/deploy until technical gates pass and the user explicitly authorizes the specific protected action.

## When to use
Use after Independent Reviewer `APPROVE`, before merge to `main`, production deploy, or production mutation.

## Inputs
- Issue/PR
- current PR head/product SHA
- exact-SHA CI result
- Reviewer result for the same SHA
- unresolved blocker/thread state
- requested merge/deploy action
- explicit user approval status

## Procedure
1. Re-read PR head SHA immediately before gating.
2. Confirm required exact-SHA CI is PASS for that SHA.
3. Confirm the Independent Reviewer returned `APPROVE` for the same SHA with zero blockers.
4. Confirm no newer product commit invalidated the evidence.
5. Confirm required repair approvals/history are complete and no `codex-needs-human`/`blocked` state remains.
6. If the user has not explicitly approved this merge/deploy, stop at `READY_FOR_USER_APPROVAL`.
7. If the user explicitly approved the specific action and all gates still match, return `APPROVED_FOR_MERGE` or `APPROVED_FOR_DEPLOY`; the operator may then perform only that approved action.

## Safety rules
- Never infer approval from prior general statements or from `review-approved` alone.
- Approval is action-specific; merge approval is not deploy approval unless the user explicitly says both.
- Re-check SHA after approval if the branch could have moved.
- Never bypass a failing/pending CI or reviewer blocker.

## Expected output
```text
RELEASE_GATE: BLOCKED|READY_FOR_USER_APPROVAL|APPROVED_FOR_MERGE|APPROVED_FOR_DEPLOY
PRODUCT_SHA: ...
CI: ...
REVIEW: ...
USER_APPROVAL: MISSING|CONFIRMED
BLOCKERS: ...
```

## Failure handling
If SHA/evidence changed, invalidate the gate and return to the appropriate CI/review stage. Do not merge/deploy based on stale approval evidence.
