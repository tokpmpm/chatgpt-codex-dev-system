# AUTOMATIC PROMPT PIPELINE

## Principle

The user is not a prompt relay. Once an Issue or Repair Plan is approved, prompt construction and model invocation are Runner responsibilities.

## Developer execution

The Runner reads durable inputs from GitHub/repo, builds the Developer prompt, validates its input refs, records a prompt hash/run record, and invokes Codex automatically.

Required inputs:

- `AGENTS.md`
- `docs/PROJECT_STATE.md`
- current Issue
- Acceptance Criteria
- Scope / Must Not Change
- risk class
- base branch and SHA
- approved Repair Plan when applicable

## Reviewer execution

The Reviewer prompt is generated only after exact-SHA CI passes.

Required inputs:

- FULL or DELTA review mode
- Issue and Acceptance Criteria
- exact pushed SHA
- exact diff / changed paths
- validation evidence
- exact-SHA CI evidence
- prior blockers and approved Repair Plan for DELTA review

The Runner launches a fresh isolated Reviewer and strictly parses `APPROVE`, `REQUEST_CHANGES`, or `REVIEW_ERROR`.

## Repair execution

Codex may not invent a repair strategy after `REQUEST_CHANGES`.

The sequence is:

```text
REQUEST_CHANGES
→ ChatGPT creates Repair Plan
→ user approval is recorded
→ Runner reads approved plan
→ Runner generates repair prompt automatically
→ Runner invokes Codex automatically
```

## Audit record

Every model call records at least:

```text
RUN_ID
ROLE
ISSUE
PR
INPUT_SHA
PROMPT_HASH
MODEL_PROVIDER
MODEL
STARTED_AT
FINISHED_AT
RESULT
```

Prompt evidence must not create a product-code commit. Store run evidence in GitHub comments/artifacts or another dedicated non-product evidence channel.

## Safety

- A prompt must never target a different Issue/SHA than the guarded workflow state.
- Reviewer prompt generation is forbidden before exact-SHA CI PASS.
- Review-only recovery may generate only a Reviewer prompt.
- Reviewer execution errors never generate a Developer/Repair prompt.
- Merge and production deploy are never triggered merely because a generated prompt/model run succeeded.
