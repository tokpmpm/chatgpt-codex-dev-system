# PUBLIC AUTOMATION GOAL

For shared/public use, the system must not depend on the user copying prompts between ChatGPT, Codex, GitHub, and the Reviewer.

Normal responsibility split:

- ChatGPT: product decisions, Issue/AC planning, blocker analysis, Repair Plan creation.
- Runner: prompt generation, model invocation, guards, evidence, workflow transitions.
- Codex: code implementation and validation.
- Independent Reviewer: isolated read-only verification.
- GitHub: durable source of truth.
- User: product direction and protected approvals (repair when required, exceptional repair, merge, deploy).

Manual prompt copy/paste is a debugging/fallback mode only, never the default workflow.
