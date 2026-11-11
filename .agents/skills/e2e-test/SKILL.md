---
name: e2e-test
description: Writes end-to-end tests for a user journey through the running app, Playwright preferred. Use when user requests e2e, end-to-end, Playwright, or Cypress tests.
---

# E2E test

Short evidence, no emojis. No target journey named: reply "Please mention the user journey that you want me to help you write the e2e tests for." and stop.

Sphere: full user journey through running app, browser to backend. Branch and boundary detail belongs in unit-test; one scope with mocked lowest layer in behavioural-test. Case fits another sphere: say so, do not write it here. Only critical journeys here.

Tool: Playwright preferred. Cypress only when project already uses it. Neither installed: ask user, add no dependency without approval.

1. Read existing e2e config, nearest e2e tests, routes and pages on journey. Reuse project's base URL, fixtures, auth setup, page objects, file naming, test location. Find app start command and test environment; state both.
2. List cases: journey start, each step, end state, one critical failure path. Skip variations coverable in lower spheres; name them.
3. Write tests. Rules:
   - Arrange-Act-Assert: three blocks in that order, blank line between. Label with `// Arrange`, `// Act`, `// Assert` only if project tests already do. Arrange seeds data and signs in; Act is one journey of user steps; Assert checks end state.
   - One journey per test. Several asserts allowed only when they describe same end state.
   - Name states journey, condition, expected result.
   - Mock nothing inside app. Third-party service only when no test environment exists; state it.
   - Drive as user: locate by role, label, text; test ids last resort. No CSS/XPath tied to markup. No direct state or storage edits in Act.
   - Assert user-visible end state: URL, visible content, persisted result after reload where relevant.
   - Independent tests: each creates and cleans own data, unique per run. No order dependence. Auth via project's stored-state or fixture, not repeated UI login, unless login is journey.
   - No fixed sleeps; rely on auto-waiting and web-first assertions.
   - No conditionals on page state. Flaky test: find cause, never add retries to hide it.
   - Credentials from environment or project fixtures. Never hardcode or commit secrets.
   - Do not change production code to make tests pass. Suspected bug: keep failing test, report to user, ask before fixing.
4. Start app with project's command. Never target production without authorisation. Run new tests alone; show invocation + result. Failure: read trace/screenshot, decide whether test or app wrong, fix test only when test wrong. Rerun until green; run 3 times to check flakiness.
5. Run project lint and type checks on test file; fix every error. Run full e2e suite when feasible; else state not run.
6. Repeat 4-5 after each edit. Report journeys covered, cases skipped with reason, environment and browsers used, suspected bugs, commands run. Never claim passing without run output.
