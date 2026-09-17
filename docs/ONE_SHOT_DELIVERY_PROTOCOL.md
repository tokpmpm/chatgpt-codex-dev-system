# ONE-SHOT DELIVERY PROTOCOL

Required for MEDIUM and HIGH risk Issues.

## Before implementation

1. Read every Acceptance Criterion and `Must Not Change` rule.
2. Locate the actual source of truth for the feature.
3. Trace writer, reader, state, persistence, and UI/consumer paths where applicable.
4. Identify the existing tests and golden/baseline behavior.
5. Perform a pre-implementation red team: list plausible failure, stale-state, partial-write, invalid-input, concurrency, responsive, and compatibility cases relevant to the Issue.
6. Define how each Acceptance Criterion will be proven before changing code.
7. Only then implement the smallest complete change.

## After implementation

1. Run targeted tests for changed behavior.
2. Run the required real user flow end-to-end; fixtures alone are insufficient when the Issue requires real flow.
3. Run negative/failure cases.
4. Run full project regression through the project's declared CI entrypoint.
5. Perform a post-implementation red team against the final diff.
6. Confirm `Must Not Change` and unrelated behavior remain intact.
7. Confirm no known blocker is being deferred while claiming completion.

## Ready-for-review gate

Codex may report `READY FOR REVIEW` only when the exact candidate commit is clean, pushed, evidence is recorded, and all required local validation has passed. CI is still a separate GitHub gate before the Reviewer may start.

Do not lower test quality, alter golden baselines without justification, or replace a required real flow with synthetic evidence just to reach this status.
