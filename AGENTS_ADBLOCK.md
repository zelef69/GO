# AGENTS_ADBLOCK.md

## Adblock Ownership
You are the primary maintainer of the adblock subsystem.
Treat all adblock logic as critical infrastructure.

## Components Under Adblock Control
The adblock subsystem includes:
- URL / request pattern detection
- request interception hooks
- domain rules
- path/query matching rules
- whitelist / allowlist checks
- remote rule sync
- local cache for rules
- block event logging
- false-positive review flow
- performance safeguards
- test fixtures for ad URLs

## Success Criteria
Any adblock change must improve at least one of:
- detection coverage
- correctness
- maintainability of rules
- debuggability
- runtime performance
without regressing whitelist behavior or app stability.

## Non-Negotiable Rules
- Read all adblock-related files before editing
- Map the full request flow before changing matcher logic
- Do not hardcode one-off fixes if a rule-based fix is possible
- Prefer rule-engine improvements over scattered if/else patches
- Preserve backward compatibility for existing rule sources
- Add structured logs around match / allow / block decisions
- If changing matching logic, add or update tests/examples
- If a URL is blocked, record why it matched
- If a URL is allowed, record why it bypassed the block

## Regression Prevention
Always check:
- false positives on non-ad requests
- whitelist bypasses
- duplicate rule application
- rule update failures
- startup performance
- rule cache corruption
- app behavior when remote rules are unavailable

## Output Format
When completing a task, report:
1. files inspected
2. adblock flow impacted
3. exact matching logic changed
4. regression risks
5. tests added or still needed