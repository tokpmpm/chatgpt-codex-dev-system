# Codex Development

## Purpose
Execute an approved Issue or approved Repair Plan in Codex App with controlled scope and reviewable evidence.

## When to use
Use only when an Issue is `codex-ready` or a specific Repair Plan is `repair-approved`.

## Inputs
- repository
- current Issue + Acceptance Criteria
- approved Repair Plan when repairing
- project state and current branch/SHA

## Procedure
1. Read the mandatory files listed in `AGENTS.md` and the current Issue.
2. Verify branch, exact HEAD, and working tree; preserve unrelated/user changes.
3. Create/use the task branch; never implement product repair on the Runner branch.
4. For MEDIUM/HIGH risk, complete the pre-implementation steps in `docs/ONE_SHOT_DELIVERY_PROTOCOL.md`.
5. Trace actual source of truth and writer/reader/persistence/consumer paths where relevant.
6. Implement the smallest complete change satisfying all Acceptance Criteria.
7. Run targeted tests, required real flow, negative cases, and full regression.
8. Perform post-implementation red team and re-check `Must Not Change`.
9. Commit and push the candidate feature branch.
10. Report exact pushed SHA and evidence using `templates/CODEX_PROMPT.md` format.

## Safety rules
- Do not invent or broaden a repair strategy beyond an approved Repair Plan.
- Do not reset/discard unrelated changes.
- Do not weaken tests or modify golden baselines merely to pass.
- Do not merge `main` or deploy/mutate production.
- Do not claim `READY FOR REVIEW` with known blockers or unpushed work.

## Expected output
```text
STATUS: READY FOR REVIEW | BLOCKED
ISSUE: #...
BRANCH: ...
PRODUCT_SHA: ...
CHANGED: ...
TARGETED_TESTS: ...
REAL_FLOW: ...
NEGATIVE_CASES: ...
REGRESSION: ...
KNOWN_BLOCKERS: ...
```

## Failure handling
On implementation/test failure, keep the branch and evidence intact, report the concrete blocker, and stop. Do not mask the failure by changing requirements/tests. Infrastructure failures are reported separately from product defects.
