# Issue Planning

## Purpose
Convert an approved product brief/change request into a GitHub Issue that Codex and an Independent Reviewer can execute without relying on chat history.

## When to use
Use before implementation of any nontrivial product change or before formal repair work that requires a new Issue.

## Inputs
- product brief or concrete user request
- repository/project state
- relevant existing behavior/tests

## Procedure
1. Fill the sections in `templates/ISSUE_TEMPLATE.md`.
2. Define one explicit Goal and User Value.
3. List Scope and `Must Not Change` separately.
4. Add implementation requirements only where architecture/constraints are intentional; do not over-specify harmless implementation detail.
5. Describe required real user flow. For stateful behavior, trace `user action → writer → state → persistence → reader → UI result` where applicable.
6. Add negative/failure cases relevant to the feature.
7. Write Acceptance Criteria as independently verifiable `AC-*` items with exact observable results.
8. Define regression and delivery requirements, including exact-SHA CI and Independent Review.
9. Apply the risk classification and mark the Issue `codex-ready` only when the specification is executable.

## Safety rules
- Never use vague Acceptance Criteria such as `功能正常` or `works correctly`.
- Fixtures/synthetic tests cannot replace explicitly required real-flow validation.
- Do not hide scope expansion inside implementation requirements.
- Do not mark `codex-ready` if a critical product decision is unresolved.

## Expected output
A GitHub-ready Issue body matching `templates/ISSUE_TEMPLATE.md`, plus:
```text
ISSUE_STATUS: CODEX_READY|NEEDS_PRODUCT_DECISION
RISK: LOW|MEDIUM|HIGH
```

## Failure handling
If the request cannot be made verifiable, return the smallest list of unresolved decisions. Do not hand an ambiguous Issue to Codex.
