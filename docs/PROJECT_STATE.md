# PROJECT STATE

This file stores stable facts, checkpoints, architecture decisions, known limitations, and the next recommended step. Query GitHub live for current PR, Actions, and review status.

## Production

- Production URL: N/A — framework repository
- Production branch: `main`
- Production version: not released

## Current Development

- Target version: `v1.0.0`
- Feature branch: bootstrap completed on `main`; future changes use feature/chore branches
- Latest product checkpoint SHA: `43f400bd2e5e93ea4e395fc08fec129540188134`
- Current Issue: framework bootstrap completed without a pre-existing Issue
- Current milestone: reusable workflow v1 pilot-ready

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
- framework contract validation workflow executes successfully at the v1 checkpoint

## Known Risks

- v1 defines Runner behavior but does not yet implement automatic model invocation.
- A product repository must replace/extend the framework-only `ci/ai-verify.sh` with real product validation before treating CI as a product release/review gate.
- GitHub labels and repository template mode may require one-time repository configuration outside repo content.

## Deferred

- Executable local Codex Runner
- Automated reviewer-provider adapters
- Transactional installer/rollback implementation
- Optional GitHub Project board automation

## Next Recommended Step

Use this framework on one real product Issue end-to-end. Capture friction before implementing Runner automation.

## Review Status

- Framework bootstrap checkpoint exists and its framework validation passed.
- Independent Reviewer has not reviewed the framework itself.
- Dynamic CI/review status: query GitHub live.

## State Update Rule

Update this file only when stable facts, architecture decisions, checkpoints, limitations, or recommended next steps change. Do not mirror short-lived PR/Actions/reviewer state here.
