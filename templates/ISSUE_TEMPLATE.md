# <Issue title>

## Goal
<What must become true?>

## User Value
<Why this matters to the user/business?>

## Risk
LOW | MEDIUM | HIGH

## Scope
- ...

## Must Not Change
- ...

## Implementation Requirements
- ...

## Real Flow Validation
Describe the real flow, including `user action → writer → state → persistence → reader → UI result` where applicable.

## Negative / Failure Cases
- ...

## Acceptance Criteria
- [ ] AC-01: <observable condition + exact expected result>
- [ ] AC-02: <observable condition + exact expected result>

## Regression Requirements
- Existing behavior that must still pass: ...
- Required full CI entrypoint: `ci/ai-verify.sh` or project equivalent

## Delivery Requirements
- [ ] work on feature/fix branch
- [ ] targeted tests pass
- [ ] required real-flow validation recorded
- [ ] negative cases pass
- [ ] full regression passes
- [ ] candidate commit pushed
- [ ] exact candidate SHA passes GitHub CI
- [ ] Independent Reviewer reviews that same SHA
