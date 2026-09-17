# RUNNER IMPLEMENTATION TARGET

## Goal

Implement an executable Runner that automatically generates prompts and invokes Codex / Independent Reviewer without manual prompt copy/paste.

## Minimum commands

```text
ai-dev status
ai-dev start --issue <n>
ai-dev review --sha <sha>
ai-dev repair --plan <plan-id>
ai-dev recover-review --sha <sha>
```

## v1 execution path

`start` must:

1. load repo/GitHub state;
2. validate branch/HEAD/worktree;
3. build Developer prompt from approved Issue + AC;
4. invoke Codex automatically;
5. run required local validation;
6. commit and push product branch;
7. wait for/check exact-SHA CI;
8. build Reviewer prompt automatically;
9. invoke a fresh isolated Reviewer;
10. persist run evidence and final workflow state.

## Required guards

- wrong repo/branch → fail closed
- unexpected dirty tree → fail closed
- prompt input SHA mismatch → fail closed
- review before exact-SHA CI PASS → fail closed
- repair without approved Repair Plan → fail closed
- more than 2 normal formal repair rounds → needs-human
- merge/deploy without explicit user approval → blocked

## Runtime tests

Use fake adapters; tests must never call real models.

Cover at least:

- successful implementation → CI PASS → APPROVE
- REQUEST_CHANGES → approved repair → DELTA APPROVE
- REQUEST_CHANGES without Repair Plan approval → no Codex call
- reviewer provider error → one fresh retry → APPROVE
- repeated reviewer error → review-error / needs-human
- review-only recovery → zero Developer calls, zero CI reruns, same product SHA
- prompt input SHA mismatch → zero model calls

The same test suite must run against source and staged/installed Runner.
