# Local Codex Runner — v1 Architecture Contract

## Status

Design contract only. The reusable workflow is usable without this Runner through ChatGPT + GitHub + Codex App. Implement the Runner only after one or more real product pilots validate the workflow.

The Runner is infrastructure; it must not become a second product decision-maker.

## Responsibilities

A future Runner may orchestrate approved development/review steps, but must provide:

- exact SHA guard
- branch guard
- dirty-worktree guard
- exact-SHA CI gate
- isolated Reviewer execution
- timeout and provider-error diagnostics
- at most one fresh Reviewer retry for execution errors
- product repair-round tracking
- explicit review-only recovery
- deterministic runtime fixture tests
- source and installed-runner self-tests
- transactional install / rollback

`codex exec` may be used internally. Normal user operation should still be copy/paste-friendly for Codex App and must not require manual Codex CLI use.

## Separation boundary

Product work and Runner work never share a repair round or branch:

```text
product: feature/<issue>-<slug> or fix/<issue>-<slug>
runner:  chore/local-codex-runner (or chore/runner-*)
```

Runner changes must never modify product code as a side effect. Product repair accounting ignores Runner-only commits.

## Proposed components

1. **Guard layer** — verifies repo, branch, expected SHA, clean/known worktree state.
2. **GitHub adapter** — reads exact-SHA CI, Issues/PRs/labels/comments and records auditable state.
3. **Developer adapter** — invokes Codex only for an approved Issue/Repair Plan.
4. **Reviewer adapter** — launches a fresh isolated read-only reviewer with strict output parsing.
5. **State ledger** — tracks repair round and review retry metadata without treating labels as authority by themselves.
6. **Recovery controller** — review-only path that cannot call Developer or mutate product state.
7. **Fixture harness** — fake Developer/Reviewer/GitHub outcomes for deterministic runtime tests.
8. **Installer** — stages installation, runs installed copy self-test, then atomically activates or rolls back.

## Guard order

Before any model call:

1. expected repository matches
2. branch matches requested task branch
3. `HEAD == expected SHA` when exact SHA is required
4. dirty tree is empty or explicitly recognized as task-owned
5. requested workflow transition is valid
6. for review, exact-SHA CI is PASS

Fail closed before calling a model if a guard fails.

## Reviewer semantics

Reviewer outcomes are three-valued:

- `APPROVE`
- `REQUEST_CHANGES`
- `REVIEW_ERROR`

`REVIEW_ERROR` examples: provider capacity, timeout, network failure, malformed/invalid reviewer output.

On Reviewer execution error:

- product SHA stays unchanged
- repair round stays unchanged
- Developer calls = 0
- regression reruns = 0
- CI reruns = 0
- fresh reviewer retry allowed once
- second error → `review-error` + needs human/infrastructure handling

## Review-only recovery

Must be explicit opt-in; a label alone must never invoke a model.

Preconditions:

- product SHA unchanged
- exact-SHA CI already PASS
- prior failure is `REVIEW_ERROR`, not `REQUEST_CHANGES`

Allowed action: fresh Reviewer only.

Forbidden: Developer/Codex, Repair, regression, CI rerun, product commit/push, merge, deploy.

## Repair accounting

Normal maximum formal product repairs = 2. Store the round against Issue + target/after SHAs. Only an approved product Repair Plan execution increments it. Runner fixes and Reviewer execution errors do not.

A user-authorized extra attempt is stored as `human-approved exceptional repair`; never implement it by changing the normal maximum to 3.

## Deterministic self-test contract

Syntax checking alone is insufficient. Runtime fixtures must mock full transitions.

Minimum review-only fixture:

```text
review-error
→ explicit recovery
→ fake reviewer PROVIDER_ERROR
→ one fresh retry
→ fake reviewer APPROVE
```

Assert:

```text
REAL MODEL CALLS = 0
DEVELOPER/CODEX CALLS = 0
REGRESSION RUNS = 0
CI RERUNS = 0
PRODUCT SHA = unchanged
REPAIR ROUND = unchanged
REVIEWER FAKE CALLS = 2
FINAL REVIEW = APPROVE
```

Run the same fixture against:

1. source Runner
2. staged/installed Runner

An install is not successful until the installed copy passes the same deterministic tests.

## Transactional install / rollback

1. install into a staging path/versioned directory
2. run deterministic self-tests there
3. verify configuration and executable paths
4. atomically switch the active pointer/symlink
5. on any failure, keep/restore the previous active version

Never partially overwrite the only working Runner installation.

## v1 implementation recommendation

Do not implement unattended label-triggered automation first. Start with explicit commands/actions such as `prepare`, `review`, `repair --plan <id>`, and `recover-review --sha <sha>`, with every protected transition guarded by GitHub evidence and user approval where required.
