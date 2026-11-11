
# Behavioural test

Short evidence, no emojis. No target scope named: reply "Please mention the file or scope that you want me to help you write the behavioural tests for." and stop.

Sphere: one user-facing scope, e.g. a form, proving data flow through its layers. Single-function branch detail belongs in unit-test; full journey through running app in e2e-test. Case fits another sphere: say so, do not write it here.

1. Read target scope, every layer between it and lowest boundary, nearest existing behavioural tests. Reuse project's runner, rendering/testing library, request-mocking tool, file naming, test location, helpers. Nothing configured: ask user, add no dependency without approval.
2. Name mocked layer before writing: lowest one only, e.g. API/network transport. Everything above stays real: abstractions over the API, hooks, stores, validation, child components. Never mock abstraction sitting on top of mocked layer. Extra mock needed: state which and why.
3. List cases: success, each validation failure, lower-layer error, loading/pending state, empty data, user correction after error. Unreachable or untestable case: state why, do not fake coverage.
4. Write tests. Rules:
   - Arrange-Act-Assert: three blocks in that order, blank line between. Label with `// Arrange`, `// Act`, `// Assert` only if project tests already do. Arrange renders scope and sets mocked-layer responses; Act is one user interaction sequence; Assert checks outcome.
   - One behaviour per test. Several asserts allowed only when they describe same outcome.
   - Name states scope, condition, expected result. Group by scope under test.
   - Drive through user-visible controls. Query by role, label, text; test ids last resort. No reaching into component state or internals.
   - Assert what user sees plus exact payload sent to mocked layer. Literal expected values, not recomputed with production algorithm.
   - Independent tests: no shared mutable state, no order dependence, reset mocks and stores between tests. Setup hooks only for identical Arrange.
   - No loops or conditionals in tests. Table-driven cases allowed when runner supports them.
   - Pin time and randomness. No fixed sleeps; await visible condition.
   - Unhandled request to mocked layer fails test.
   - Do not change production code to make tests pass. Suspected bug: keep failing test, report to user, ask before fixing.
5. Run new tests alone; show invocation + result. Failure: decide whether test or code wrong, fix test only when test wrong. Rerun until green.
6. Run project lint and type checks on test file; fix every error. Run full relevant suite; new tests must not break others.
7. Repeat 5-6 after each edit. Report mocked layer, cases covered, cases skipped with reason, suspected bugs, commands run. Never claim passing without run output.
