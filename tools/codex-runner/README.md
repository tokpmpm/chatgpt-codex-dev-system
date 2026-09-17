# Local Codex Runner — Automation Contract

## Status

Required next milestone. The framework rules and CI gate already exist; the executable Runner still needs implementation.

The Runner is infrastructure, not a product decision-maker. Its job is to turn approved GitHub state into deterministic prompts and guarded model executions without requiring the user to copy/paste prompts or operate Codex CLI manually.

## User experience

Normal operation should be close to:

```text
ai-dev start --issue 12
```

The Runner then:

1. reads `AGENTS.md`, `docs/PROJECT_STATE.md`, workflow protocols, the GitHub Issue, Acceptance Criteria, and current PR/Repair Plan;
2. verifies repository, branch, HEAD, and dirty-worktree guards;
3. generates the Developer prompt automatically from the approved inputs;
4. invokes Codex non-interactively (for example through `codex exec` internally);
5. runs targeted tests, real-flow checks, negative cases, and regression required by the Issue;
6. commits and pushes the feature branch only after local validation succeeds;
7. waits for/checks exact-SHA CI;
8. generates the Reviewer prompt automatically from the exact pushed SHA, diff, Issue, AC, test evidence, and CI evidence;
9. launches a fresh isolated Reviewer;
10. parses `APPROVE`, `REQUEST_CHANGES`, or `REVIEW_ERROR` and transitions the workflow accordingly.

The user does **not** manually copy Developer or Reviewer prompts. Prompt generation and model invocation are Runner responsibilities.

## Automatic prompt pipeline

Prompts are derived from durable inputs, not handwritten ad-hoc strings.

### Developer prompt inputs

- `AGENTS.md`
- `docs/PROJECT_STATE.md`
- current Issue body
- Acceptance Criteria
- `Must Not Change`
- risk class
- current branch + base SHA
- relevant approved Repair Plan when repairing

### Reviewer prompt inputs

- Review mode: FULL or DELTA
- current Issue + AC
- exact pushed product SHA
- exact diff / changed files
- relevant source paths
- local validation evidence
- exact-SHA CI evidence
- previous blockers + approved Repair Plan for DELTA review

### Prompt evidence

For every model execution, record an auditable run record in GitHub containing at least:

- RUN_ID
- role (`developer` / `reviewer`)
- Issue / PR
- input SHAs
- generated prompt hash
- model/provider
- start/end status
- result summary

The full generated prompt may be stored as an attached/linked run artifact or GitHub comment when practical, but it must never be committed into the product branch merely to create evidence.

## Responsibilities

The Runner must provide:

- automatic prompt generation
- non-interactive Developer invocation
- non-interactive isolated Reviewer invocation
- exact SHA guard
- branch guard
- dirty-worktree guard
- exact-SHA CI gate
- timeout and provider-error diagnostics
- at most one fresh Reviewer retry for execution errors
- product repair-round tracking
- explicit review-only recovery
- deterministic runtime fixture tests
- source and installed-runner self-tests
- transactional install / rollback

`codex exec` or another non-interactive Codex interface may be used internally. This is an implementation detail; users should not need to run Codex CLI or paste prompts themselves.

## Separation boundary

Product work and Runner work never share a repair round or branch:

```text
product: feature/<issue>-<slug> or fix/<issue>-<slug>
runner:  chore/local-codex-runner (or chore/runner-*)
```

Runner changes must never modify product code as a side effect. Product repair accounting ignores Runner-only commits.

## Components

1. **Guard layer** — verifies repo, branch, expected SHA, and clean/known worktree state.
2. **GitHub adapter** — reads Issues/PRs/CI/reviews and records auditable state.
3. **Prompt builder** — deterministically composes Developer, Reviewer, and Repair execution prompts from approved GitHub/repo inputs.
4. **Developer adapter** — invokes Codex automatically only for an approved Issue/Repair Plan.
5. **Reviewer adapter** — launches a fresh isolated read-only reviewer with strict output parsing.
6. **State ledger** — tracks repair round and reviewer retry metadata without treating labels as authority by themselves.
7. **Recovery controller** — review-only path that cannot call Developer or mutate product state.
8. **Fixture harness** — fake Developer/Reviewer/GitHub outcomes for deterministic runtime tests.
9. **Installer** — stages installation, runs installed-copy self-test, then atomically activates or rolls back.

## Guard order

Before any model call:

1. expected repository matches
2. branch matches requested task branch
3. `HEAD == expected SHA` when exact SHA is required
4. dirty tree is empty or explicitly recognized as task-owned
5. requested workflow transition is valid
6. all prompt inputs resolve to the intended Issue/Repair Plan/version
7. for review, exact-SHA CI is PASS

Fail closed before calling a model if a guard fails.

## Repair flow

`REQUEST_CHANGES` must not let Codex invent its own fix.

```text
Reviewer REQUEST_CHANGES
→ ChatGPT produces minimal Repair Plan
→ user approval is recorded
→ Runner reads the approved plan
→ Runner automatically generates repair prompt
→ Runner invokes Codex
→ validation + new commit + exact-SHA CI
→ fresh DELTA Reviewer
```

Normal maximum formal product repairs = 2. A user-authorized extra attempt is stored as `human-approved exceptional repair`; never implement it by changing the normal maximum to 3.

## Reviewer error semantics

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

Allowed action: automatically generate a fresh Reviewer prompt and invoke only a fresh Reviewer.

Forbidden: Developer/Codex, Repair, regression, CI rerun, product commit/push, merge, deploy.

## Deterministic self-test contract

Syntax checking alone is insufficient. Runtime fixtures must mock full transitions and prompt generation.

Minimum review-only fixture:

```text
review-error
→ explicit recovery
→ auto-generate reviewer prompt
→ fake reviewer PROVIDER_ERROR
→ one fresh retry with a fresh isolated reviewer
→ fake APPROVE
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
PROMPT INPUT SHA = expected product SHA
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

## First implementation target

Implement explicit, guarded automation first:

```text
ai-dev status
ai-dev start --issue <n>
ai-dev review --sha <sha>
ai-dev repair --plan <plan-id>
ai-dev recover-review --sha <sha>
```

`start`, `review`, and `repair` generate their prompts automatically and invoke the configured model adapters. Merge and production deploy remain separate protected actions requiring explicit user approval.