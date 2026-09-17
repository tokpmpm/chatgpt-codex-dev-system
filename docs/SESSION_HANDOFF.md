# SESSION HANDOFF

A new session must recover from GitHub/repo state rather than asking the user to replay history.

## Recovery procedure

1. Identify the repository.
2. Read `AGENTS.md`.
3. Read `docs/PROJECT_STATE.md`.
4. Read `docs/AI_WORKFLOW.md` and `docs/REVIEW_PROTOCOL.md`.
5. Query open/recent Issues and PRs relevant to current development.
6. Identify current feature/repair branch and exact product SHA.
7. Query exact-SHA CI and current review evidence.
8. Read the current Issue, Acceptance Criteria, and latest approved Repair Plan if any.
9. Infer the current workflow stage from evidence, not from labels alone.
10. Report the state and the single next action.

## Required handoff output

```text
CURRENT STATE: <stage>
CURRENT ISSUE: <# / title or none>
PRODUCT SHA: <exact sha or none>
CI STATUS: <PASS|FAIL|PENDING|NOT_FOUND>
REVIEW STATUS: <APPROVED|REQUEST_CHANGES|REVIEW_ERROR|NOT_STARTED>
KNOWN BLOCKERS: <none or concise list>
NEXT ACTION: <one concrete action>
```

If GitHub evidence conflicts with `PROJECT_STATE.md`, prefer current repository/GitHub facts for dynamic state and update `PROJECT_STATE.md` only if its stable facts/checkpoints are stale.

Do not ask the user to restate project history unless the repository genuinely lacks the decision needed to proceed.
