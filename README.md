# ChatGPT × GitHub × Codex — AI Development System

A reusable workflow for websites, Web Apps, and tool projects where GitHub is the long-term source of truth and `ai-dev` automates prompt generation, Codex execution, CI gating, and Independent Review.

## Roles

- **ChatGPT** — product planning, architecture, Acceptance Criteria, Issue planning, Repair Plans, acceptance, and next-step decisions.
- **Runner (`ai-dev`)** — reads approved GitHub/repo state, generates prompts automatically, invokes Developer/Reviewer adapters, applies guards, records audit evidence, and controls workflow transitions.
- **Codex** — implementation, tests, bug fixes, regression, and local validation through the Runner.
- **GitHub** — Issues, PRs, commits, CI evidence, review evidence, workflow state, and durable handoff state.
- **Independent Reviewer** — fresh isolated read-only review against Acceptance Criteria; returns `APPROVE`, `REQUEST_CHANGES`, or `REVIEW_ERROR`.
- **User** — product direction and explicit approval for protected Repair, exceptional repair, merge, and production deploy decisions.

## Quick start

Prerequisites: Git, GitHub CLI (`gh`) authenticated to the target repository, Python 3, and Codex CLI authenticated locally.

Install the Runner from this repository:

```bash
bash tools/codex-runner/install.sh
```

Then, from a product repository containing this framework:

```bash
ai-dev status
ai-dev start --issue 12
```

No manual Developer/Reviewer prompt copy-paste is required. The Runner builds prompts from the Issue, Acceptance Criteria, repository protocols, current branch/SHA, CI evidence, and approved Repair Plan when applicable.

## Core flow

```text
Product request
  → GitHub Issue + verifiable Acceptance Criteria
  → ai-dev generates Developer prompt
  → Codex implementation
  → local validation + regression
  → commit + push feature branch
  → exact-SHA CI PASS
  → ai-dev generates Reviewer prompt
  → fresh isolated Independent Review
      → APPROVE → release gate; merge/deploy still require explicit user approval
      → REQUEST_CHANGES → Repair Plan → explicit approval → automated repair → Delta Review
      → REVIEW_ERROR → same-SHA reviewer retry/recovery; no product repair
```

Medium/high-risk work uses `docs/ONE_SHOT_DELIVERY_PROTOCOL.md`. Formal product repair is capped at two rounds unless an exceptional repair is separately authorized and recorded.

## Runner commands

```text
ai-dev status
ai-dev start --issue <n>
ai-dev review --sha <sha> [--issue <n>]
ai-dev approve-repair --plan <plan-id> [--issue <n>]
ai-dev repair --plan <plan-id> [--issue <n>]
ai-dev recover-review --sha <sha> [--issue <n>]
ai-dev self-test
```

The supported entrypoint is `ai-dev`. `tools/codex-runner/runner.py` is the core engine; `entrypoint.py` adds fail-closed guards and durable audit confirmation.

## Reuse in another repository

Copy the framework files into the product repository, fill `docs/PROJECT_STATE.md`, and replace/extend `ci/ai-verify.sh` with the product's real targeted, real-flow, negative-case, and regression validation. A product repository must not treat the framework-only validation script as a sufficient product gate.

Complete the one-time GitHub setup in `docs/REPOSITORY_SETUP.md`: protect `main`, require the exact-SHA validation check, create the workflow labels, and enable Template repository mode when using this repository as a source template.

## Safety boundaries

- No automatic merge to `main`.
- No automatic production deploy.
- Reviewer runs only after exact-SHA CI PASS.
- Review/Planner adapters run read-only in isolated sessions/worktrees.
- `REVIEW_ERROR` never consumes a product repair round.
- Review-only recovery cannot call Developer, rerun regression, rerun CI, or change product SHA.
- Normal formal product repair maximum remains 2.

## Verification

```bash
bash tools/codex-runner/self-test.sh
```

The deterministic fixture suite is run against source, staged, and installed copies. GitHub Actions runs the same verification through `ci/ai-verify.sh`.

## Directory map

```text
AGENTS.md
docs/                  Durable workflow, project state, and repo setup
skills/                Reusable agent procedures
templates/             Issue/review/repair structures
tools/codex-runner/     Executable automated Runner + tests + installer
.github/workflows/      Exact-SHA CI gate
```

The workflow is GitHub-centered: a fresh session should recover current state from the repository and GitHub without replaying old conversations.
