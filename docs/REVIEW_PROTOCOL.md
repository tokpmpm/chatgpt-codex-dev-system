# REVIEW PROTOCOL

## Preconditions

A review may start only when all are available:

- current Issue and Acceptance Criteria,
- exact pushed product SHA,
- exact-SHA CI PASS,
- exact diff and relevant source,
- test/real-flow evidence required by the Issue.

If exact-SHA CI is not green, stop; do not review a different SHA or a local working tree.

## Reviewer isolation

The Independent Reviewer uses a fresh isolated session and is read-only. It must not edit code, commit, push, merge, deploy, or redesign the implementation.

## FULL REVIEW

Use for the first review of an Issue. Inspect:

- Issue and Acceptance Criteria,
- exact diff,
- relevant source paths,
- tests,
- CI evidence,
- real-flow and negative-case evidence,
- `Must Not Change` / regression requirements.

## DELTA REVIEW

Use after an approved Repair Plan. Inspect:

- previous blockers,
- approved Repair Plan,
- before SHA and after SHA,
- exact repair diff,
- targeted evidence,
- exact after-SHA CI,
- repaired requirements.

Previously passing requirements may be carried forward only when the repair diff cannot reasonably affect them. If impact is plausible, re-check them.

## Required output

```text
REVIEW_MATRIX_BEGIN
Requirement | Real source/path | Positive evidence | Negative/guard evidence | Status
AC-01 | ... | ... | ... | PASS/FAIL
REVIEW_MATRIX_END

REVIEW_RESULT_BEGIN
VERDICT: APPROVE
BLOCKER_COUNT: 0
REVIEW_RESULT_END
```

or

```text
REVIEW_RESULT_BEGIN
VERDICT: REQUEST_CHANGES
BLOCKER_COUNT: N
BLOCKERS:
1. [AC-ID] concrete unmet requirement + evidence
2. ...
REVIEW_RESULT_END
```

A blocker must map to an Acceptance Criterion, explicit regression rule, safety rule, or demonstrable defect in the required flow. Preferences and unrelated refactors are not blockers.

## REVIEW ERROR

Execution/infrastructure failure is reported separately:

```text
REVIEW_ERROR_BEGIN
TYPE: PROVIDER_CAPACITY|TIMEOUT|NETWORK|INVALID_OUTPUT|OTHER
PRODUCT_SHA: <sha>
RETRYABLE: YES|NO
DETAIL: <concise diagnostic>
REVIEW_ERROR_END
```

A `REVIEW_ERROR` must not be converted into `REQUEST_CHANGES`, must not increment repair rounds, and must not trigger product changes.
