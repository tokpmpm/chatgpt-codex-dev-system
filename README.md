# ChatGPT × GitHub × Codex App — AI Development System

A reusable workflow for website, Web App, and tool projects where GitHub is the long-term source of truth.

## Roles

- **ChatGPT** — product planning, architecture, Acceptance Criteria, issue planning, repair plans, review coordination, acceptance, next-step decisions.
- **Codex App** — implementation, tests, bug fixes, regression, local validation, and execution of an approved plan.
- **GitHub** — Issues, PRs, commits, CI evidence, review evidence, workflow state, and durable handoff state.
- **Independent Reviewer** — isolated read-only review against Acceptance Criteria; returns `APPROVE`, `REQUEST_CHANGES`, or `REVIEW_ERROR`.
- **User** — product direction and explicit approval for exceptional repair, merge, and production deploy.

## Start here

Every new ChatGPT/Codex/Reviewer session reads, in order:

1. `AGENTS.md`
2. `docs/PROJECT_STATE.md`
3. `docs/AI_WORKFLOW.md`
4. `docs/REVIEW_PROTOCOL.md`
5. the current GitHub Issue and, when present, its PR

Then verify branch, HEAD SHA, working tree, and current GitHub CI/review status instead of relying on previous chat history.

## Core flow

```text
Product request
  → GitHub Issue + verifiable Acceptance Criteria
  → Codex implementation
  → targeted tests + real-flow validation + negative cases
  → full regression
  → commit + push feature branch
  → exact-SHA CI PASS
  → isolated Independent Review
      → APPROVE → user-approved merge/deploy
      → REQUEST_CHANGES → ChatGPT Repair Plan → user approval → Codex repair → Delta Review
      → REVIEW_ERROR → same-SHA review retry/recovery; no product repair
```

Medium/high-risk work uses `docs/ONE_SHOT_DELIVERY_PROTOCOL.md`. Formal product repair is capped at two rounds unless the user explicitly authorizes a separately recorded exceptional repair.

## Reuse in a product repository

Copy the framework files into the product repository, keep product code outside `skills/` and `docs/`, then fill `docs/PROJECT_STATE.md`. For repositories containing a recognized product marker (`package.json`, `pyproject.toml`, `Cargo.toml`, or `go.mod`), `.github/workflows/review.yml` requires an executable `ci/ai-verify.sh` so CI cannot silently pass without product validation.

## What v1 intentionally does not automate

v1 does not automatically invoke Codex or a reviewer model, merge, deploy, or mutate production. `tools/codex-runner/README.md` defines the runner contract for a later implementation with SHA/branch/dirty-tree guards, reviewer isolation, retry semantics, repair-round tracking, deterministic fixture tests, and transactional install/rollback.

## Directory map

```text
AGENTS.md
docs/                  Durable workflow and project state
skills/                Reusable agent procedures
templates/             Copy-ready Issue/review/repair artifacts
tools/codex-runner/     Runner architecture contract
.github/workflows/      CI gate
```

The workflow is intentionally GitHub-centered: a fresh session should be able to recover current state from the repository and GitHub without replaying old conversations.
