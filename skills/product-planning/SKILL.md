# Product Planning

## Purpose
Turn an ambiguous product request into a bounded, decision-ready product brief before implementation planning begins.

## When to use
Use for a new feature/product direction, a broad change request, or any request where user value, scope, source of truth, or success conditions are not yet explicit.

## Inputs
- user request and constraints
- existing product/repository context when available
- known technical/business limitations

## Procedure
1. State the user problem and desired outcome in observable terms.
2. Identify primary user, core flow, and source-of-truth/data implications.
3. Separate `In Scope`, `Out of Scope`, and `Must Not Change`.
4. Record constraints and stable decisions already made.
5. Identify only material unknowns; resolve them from repo/evidence when possible rather than asking the user to replay history.
6. Classify risk as LOW/MEDIUM/HIGH using `docs/AI_WORKFLOW.md`.
7. Propose the smallest coherent v1 and explicitly defer nonessential ideas.
8. Hand the result to `issue-planning`.

## Safety rules
- Do not write code or silently choose major product behavior that the user has not authorized.
- Do not expand scope to solve adjacent problems.
- Treat repository/current product behavior as evidence, not old chat memory.
- For destructive/security/production changes, prefer a narrower plan and mark the risk HIGH.

## Expected output
```text
PRODUCT_BRIEF_BEGIN
PROBLEM: ...
USER_VALUE: ...
PRIMARY_FLOW: ...
IN_SCOPE: ...
OUT_OF_SCOPE: ...
MUST_NOT_CHANGE: ...
SOURCE_OF_TRUTH: ...
CONSTRAINTS: ...
RISK: LOW|MEDIUM|HIGH
DEFERRED: ...
NEXT: CREATE_ISSUE
PRODUCT_BRIEF_END
```

## Failure handling
If evidence is insufficient for a safe product decision, record the exact unresolved decision and its impact. Continue with bounded assumptions only when they are reversible and clearly marked; otherwise stop before implementation planning.
