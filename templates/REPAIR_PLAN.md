# Repair Plan

```text
PLAN_ID: RP-<issue>-R<round>-<short-id>
STATUS: DRAFT
ISSUE: #<number>
TARGET_SHA: <reviewed sha>
REPAIR_ROUND: <1|2|EXCEPTIONAL>

ROOT_CAUSE:
<evidence-backed cause of the reviewer blockers>

CHANGES:
1. <smallest concrete change>
2. ...

DO_NOT_CHANGE:
- <protected behavior/scope>

VALIDATION:
- <targeted test mapped to blocker>
- <real flow if required>
- <negative case>
- <full regression / exact-SHA CI>
```

User approval changes `STATUS` to `APPROVED`. Codex may not execute a DRAFT plan.
