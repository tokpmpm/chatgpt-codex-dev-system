# GitHub Operator

## Purpose
Keep GitHub as the durable source of truth for work state, exact SHA evidence, and safe workflow transitions.

## When to use
Use to read/create/update Issues, branches, PRs, labels, comments, CI evidence, review evidence, and repair approval records.

## Inputs
- repository
- current Issue/PR identifiers
- expected branch/SHA
- requested transition/action

## Procedure
1. Read `AGENTS.md` and determine the intended workflow stage.
2. Query live GitHub state instead of trusting stale chat or `PROJECT_STATE.md` for PR/CI/review status.
3. Before a write, verify repository, target Issue/PR, branch, and expected SHA.
4. Use the recommended stage labels from `docs/GITHUB_WORKFLOW.md`; remove contradictory stale stage labels when transitioning.
5. Record evidence with the exact product SHA in Issue/PR comments.
6. For CI checks, confirm the check/run belongs to the exact candidate SHA.
7. Update `docs/PROJECT_STATE.md` only for stable decisions/checkpoints, not every workflow transition.

## Safety rules
- Never force-move/reset a user's branch to discard unconfirmed work.
- Do not claim green CI from another SHA.
- Do not auto-trigger product repair from a `review-error` label.
- Do not merge into `main`, enable an equivalent automatic merge path, deploy, or mutate production without explicit user approval for that specific action.
- Prefer additive auditable records (Issue/PR comments) for repair approvals/reviewer results.

## Expected output
```text
GITHUB_STATE
ISSUE: ...
PR: ...
BRANCH: ...
PRODUCT_SHA: ...
CI: ...
LABEL_STAGE: ...
REVIEW: ...
WRITE_PERFORMED: ...
```

## Failure handling
On permission/API/conflict errors, leave Git state unchanged and report the exact failed operation. Re-read current state before retrying any write that could have raced.
