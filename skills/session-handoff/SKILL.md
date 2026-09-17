# Session Handoff

## Purpose
Recover project state in a fresh ChatGPT/Codex session without requiring the user to repeat history.

## When to use
Use at the start of a new session, after a long interruption, or whenever current workflow stage is uncertain.

## Inputs
- repository identity
- repository files
- live GitHub Issues/PRs/branches/commits/CI/reviews

## Procedure
1. Read `AGENTS.md`, `docs/PROJECT_STATE.md`, `docs/AI_WORKFLOW.md`, and `docs/REVIEW_PROTOCOL.md`.
2. Query open/recent Issues and PRs relevant to current development.
3. Identify active branch and exact product SHA.
4. Query exact-SHA CI and review evidence.
5. Read the current Issue/Acceptance Criteria and latest approved Repair Plan if present.
6. Reconstruct stage from evidence, not label alone.
7. Compare dynamic GitHub facts with stable `PROJECT_STATE.md`; update the latter only if stable context is stale.
8. Return the required seven-line handoff summary and one next action.

## Safety rules
- Do not infer current state from prior chat memory when GitHub can answer it.
- Do not ask the user to restate history already recoverable from the repo.
- Do not mutate code or workflow state merely while recovering context.

## Expected output
```text
CURRENT STATE: <stage>
CURRENT ISSUE: <# / title or none>
PRODUCT SHA: <sha or none>
CI STATUS: <PASS|FAIL|PENDING|NOT_FOUND>
REVIEW STATUS: <APPROVED|REQUEST_CHANGES|REVIEW_ERROR|NOT_STARTED>
KNOWN BLOCKERS: <none or list>
NEXT ACTION: <one action>
```

## Failure handling
If evidence is missing or contradictory, state exactly what cannot be established and use the safest earlier workflow stage. Do not fabricate a SHA, CI result, approval, or review verdict.
