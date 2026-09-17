# Review Result

## FULL / DELTA Review Matrix

```text
REVIEW_MATRIX_BEGIN
Requirement | Real source/path | Positive evidence | Negative/guard evidence | Status
AC-01 | ... | ... | ... | PASS
REVIEW_MATRIX_END
```

## Approve

```text
REVIEW_RESULT_BEGIN
VERDICT: APPROVE
BLOCKER_COUNT: 0
REVIEW_RESULT_END
```

## Request changes

```text
REVIEW_RESULT_BEGIN
VERDICT: REQUEST_CHANGES
BLOCKER_COUNT: N
BLOCKERS:
1. [AC-ID] <specific unmet requirement and evidence>
REVIEW_RESULT_END
```

## Reviewer execution error

```text
REVIEW_ERROR_BEGIN
TYPE: PROVIDER_CAPACITY|TIMEOUT|NETWORK|INVALID_OUTPUT|OTHER
PRODUCT_SHA: <sha>
RETRYABLE: YES|NO
DETAIL: <diagnostic>
REVIEW_ERROR_END
```
