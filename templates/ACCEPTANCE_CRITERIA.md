# Acceptance Criteria

Use one ID per independently verifiable requirement.

| ID | User action / precondition | Observable expected result | Failure/guard expectation | Required evidence |
|---|---|---|---|---|
| AC-01 | ... | ... | ... | real flow / test / source path |
| AC-02 | ... | ... | ... | ... |

## Rules

- Avoid words such as `works`, `normal`, `correct`, or `properly` without an observable definition.
- Include persistence/read-back behavior for stateful features.
- Include desktop/mobile behavior when UI scope requires both.
- Include error/empty/loading/permission cases when relevant.
- Fixtures/synthetic tests do not replace an explicitly required real user flow.
