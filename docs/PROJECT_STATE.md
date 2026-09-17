# PROJECT STATE

This file stores stable facts, checkpoints, architecture decisions, known limitations, and the next recommended step. Query GitHub live for current PR, Actions, and review status.

## Production

- Production URL: N/A — framework repository
- Production branch: `main`
- Production version: not released

## Current Development

- Target version: `v1.1.0`
- Feature branch: `feature/1-automated-runner`
- Current Issue: `#1 Implement executable automated Runner with zero manual prompt relay`
- Current PR: `#2 feat: executable automated ai-dev runner`
- Latest validated Runner code checkpoint before this state update: `8d7d4e9ffc9787810841e8f36b20fed789c7eb21`
- Current milestone: automated Runner implementation complete; independent review pending

## Validated Scope

- GitHub-centered source of truth
- Issue + verifiable Acceptance Criteria contract
- automatic Developer / Repair / Reviewer prompt generation; no normal-flow prompt relay
- non-interactive Codex Developer adapter
- explicit repository / branch / base SHA / input SHA prompt refs
- Developer branch/HEAD mutation guard; Runner owns commit/push transitions
- exact-SHA CI gate before review
- fresh isolated Reviewer worktree with read-only default adapter
- strict Full/Delta Reviewer output parsing
- maximum two formal product repair rounds
- approved Repair Plan required before repair execution
- reviewer error vs product rejection separation
- explicit review-only recovery on unchanged product SHA
- durable local + GitHub model-run audit evidence including Issue, PR (or N/A), branch, exact input SHA, prompt hash, provider/model, status, and timestamps
- transactional staged/versioned install with rollback of active Runner and command link
- deterministic source, staged, installed, and forced-rollback verification
- latest Runner code checkpoint passed exact-SHA GitHub CI with 21 deterministic runtime/contract tests

## Known Risks

- A real end-to-end provider run with authenticated local Codex + `gh` still must be performed in an actual product repository; CI intentionally uses fake adapters and makes zero real model calls.
- The default Repair Planner uses the configured planner adapter; projects that require ChatGPT specifically for Repair Planning should set a separate planner command/provider instead of relying on the default Codex CLI adapter.
- A product repository must replace/extend the framework-only `ci/ai-verify.sh` with real product validation before treating CI as a product release/review gate.
- GitHub platform setup is not fully represented by files: `main` protection/ruleset, required status checks, label definitions, and Template repository mode must be configured once per repo. See `docs/REPOSITORY_SETUP.md`.

## Deferred

- Additional Developer/Reviewer/Planner provider adapters beyond command-based v1
- Optional GitHub Project board automation
- Distribution packaging beyond the transactional local installer

## Next Recommended Step

Run an isolated Independent Reviewer against PR #2 exact head SHA after its exact-SHA CI is PASS. Do not merge until review returns `APPROVE` and the user explicitly authorizes merge.

## Review Status

- Automated Runner implementation exists on PR #2.
- Deterministic source/staged/installed/rollback validation has passed on the latest validated Runner code checkpoint.
- Independent Reviewer has not yet approved PR #2.
- Dynamic PR/CI/review status: query GitHub live.

## State Update Rule

Update this file only when stable facts, architecture decisions, checkpoints, limitations, or recommended next steps change. Do not mirror short-lived PR/Actions/reviewer state here.
