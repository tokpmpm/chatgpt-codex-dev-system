# PROJECT STATE

This file stores stable facts, checkpoints, architecture decisions, known limitations, and the next recommended step. Query GitHub live for current PR, Actions, and review status.

## Production

- Production URL: N/A — framework repository
- Production branch: `main`
- Production version: not released

## Current Development

- Target version: `v1.0.0`
- Feature branch: bootstrap on `main`; future changes use feature/chore branches
- Latest product checkpoint SHA: `PENDING_V1_BOOTSTRAP_SHA`
- Current Issue: framework bootstrap (no Issue created before repository initialization)
- Current milestone: reusable workflow v1

## Validated Scope

- GitHub-centered source of truth
- Issue + verifiable Acceptance Criteria contract
- Codex implementation discipline
- exact-SHA CI gate
- isolated Full/Delta Review protocol
- maximum two formal product repair rounds
- reviewer error vs product rejection separation
- explicit review-only recovery semantics
- session handoff contract
- release gate requiring explicit user approval

## Known Risks

- v1 defines Runner behavior but does not yet implement automatic model invocation.
- Generic CI cannot know a product's test stack; downstream product repositories must provide `ci/ai-verify.sh` when a recognized product marker exists.
- GitHub labels and repository template mode may require one-time repository configuration outside this repo content.

## Deferred

- Executable local Codex Runner
- Automated reviewer-provider adapters
- Transactional installer/rollback implementation
- Optional GitHub Project board automation

## Next Recommended Step

Use this framework on one real product Issue end-to-end. Capture friction before implementing Runner automation.

## Review Status

- Framework bootstrap: not independently reviewed yet.
- Dynamic CI/review status: query GitHub live.

## State Update Rule

Update this file only when stable facts, architecture decisions, checkpoints, limitations, or recommended next steps change. Do not mirror short-lived PR/Actions/reviewer state here.
