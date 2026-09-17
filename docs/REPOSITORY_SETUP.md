# REPOSITORY SETUP

One-time GitHub repository settings that cannot be represented only by committed files.

The committed workflow is usable without these settings, but a production-strength reusable template should complete them once per repository.

## 1. Protect `main`

Create a branch protection rule or repository ruleset for `main` with these minimum controls:

- Require changes to arrive through a pull request for normal product work.
- Require the `Exact SHA validation` status check from `.github/workflows/review.yml` before merge.
- Block force pushes.
- Block branch deletion.
- Do not enable unattended auto-merge as a substitute for explicit user merge approval.

The workflow's user-approval rule still applies even when GitHub reports all checks green. A green CI/review state means `eligible for user decision`, not `authorized to merge`.

## 2. Create workflow labels

Create these repository labels exactly once:

- `codex-ready`
- `codex-running`
- `reviewing`
- `review-approved`
- `review-error`
- `repair-awaiting-plan`
- `repair-approved`
- `codex-needs-human`
- `blocked`

Operational code must not assume a label alone authorizes a model call, Repair, merge, or deploy. Labels are discoverability/state hints; exact GitHub evidence and explicit approvals remain authoritative.

## 3. Enable Template repository mode

If this repository is used as the reusable source for new projects, enable GitHub's **Template repository** setting.

When creating a product repo from the template:

1. fill `docs/PROJECT_STATE.md` with product-specific stable state,
2. replace/extend `ci/ai-verify.sh` with real product validation,
3. verify the copied `review.yml` succeeds on the product repo,
4. create the workflow labels,
5. protect that product repo's `main` branch.

## 4. Verify after setup

Confirm:

- `main` is reported as protected/ruleset-governed,
- force push/deletion are blocked,
- `Exact SHA validation` is a required check,
- all nine workflow labels exist,
- this repository is marked as a template when intended,
- merge/deploy still require explicit user approval under `AGENTS.md` and `skills/release-gate/SKILL.md`.

## Source-of-truth rule

Do not copy volatile Actions state into this file. Query GitHub live for the current branch protection/ruleset, exact-SHA CI, PR, and review state.