# PROJECT STATE

This file stores stable facts, checkpoints, architecture decisions, known limitations, and the next recommended step. Query GitHub live for current PR, Actions, and review status.

## Production

- Production URL: N/A — framework repository
- Production branch: `main`
- Production version: not released

## Current Development

- Target version: `v1.1.0`
- Feature branch: next implementation must use a dedicated feature branch
- Latest validated framework checkpoint SHA: `43f400bd2e5e93ea4e395fc08fec129540188134`
- Current Issue: `#1 Implement executable automated Runner with zero manual prompt relay`
- Current milestone: automated Runner + public-shareable workflow

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
- automatic prompt generation is now a required Runner design principle; manual prompt relay is fallback/debug only

## Known Risks

- The executable Runner is not implemented yet; automatic prompt generation/model invocation is currently a documented contract and Issue #1 acceptance target.
- A product repository must replace/extend the framework-only `ci/ai-verify.sh` with real product validation before treating CI as a product release/review gate.
- GitHub platform setup is not fully represented by files: `main` protection/ruleset, required status checks, label definitions, and Template repository mode must be configured once per repo. See `docs/REPOSITORY_SETUP.md`.

## Deferred

- Optional GitHub Project board automation
- Additional Developer/Reviewer provider adapters beyond the first executable path

## Next Recommended Step

Implement Issue #1 on a dedicated feature branch. The first Runner must automatically generate Developer/Repair/Reviewer prompts and invoke the configured model adapters; users must not manually copy/paste prompts in the normal workflow.

## Review Status

- Framework bootstrap checkpoint exists and its framework validation passed.
- Issue #1 implementation has not started yet.
- Dynamic CI/review status: query GitHub live.

## State Update Rule

Update this file only when stable facts, architecture decisions, checkpoints, limitations, or recommended next steps change. Do not mirror short-lived PR/Actions/reviewer state here.
