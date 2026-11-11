---
name: unit-test
description: Writes isolated unit tests for a named file using Arrange-Act-Assert. Use when user requests unit tests, test coverage, or missing test cases for a file.
---

# Unit test

Short evidence, no emojis. No target file named: reply "Please mention the file that you want me to help you write the unit tests for." and stop.

Sphere: one function, class, or component; most isolated of three. Cross-layer data flow belongs in behavioural-test; full user journey in e2e-test. Case fits another sphere: say so, do not write it here.

1. Read target file, its direct collaborators, nearest existing unit tests. Reuse project's runner, assertion library, file naming, test location, helpers, mock style. No existing tests: use runner in project config; none configured: ask user, add no dependency without approval.
2. List cases before writing: every exported function/method, each branch, boundary values (empty, zero, one, max, null/undefined), invalid input, thrown/rejected errors, async ordering. Unreachable or untestable case: state why, do not fake coverage.
3. Write tests. Rules:
   - Arrange-Act-Assert: three blocks in that order, blank line between. Label with `// Arrange`, `// Act`, `// Assert` only if project tests already do. One Act per test.
   - One behaviour per test. Several asserts allowed only when they describe same outcome.
   - Name states unit, condition, expected result. Group by unit under test.
   - Test public behaviour, not private internals or call order, unless call itself is contract.
   - Mock every collaborator outside unit: network, filesystem, clock, randomness, environment, other modules with side effects. Pure helpers stay real. Pin time and randomness. Never mock unit under test.
   - Independent tests: no shared mutable state, no order dependence, reset mocks between tests. Setup hooks only for identical Arrange.
   - No logic in tests: no loops, conditionals, or recomputing expected value with production algorithm. Literal expected values. Table-driven cases allowed when runner supports them.
   - Assert specific value or error type/message, not merely truthy or "did not throw".
   - No fixed sleeps; await condition or use fake timers.
   - Do not change production code to make tests pass. Suspected bug: keep failing test, report to user, ask before fixing.
4. Run new tests alone; show invocation + result. Failure: decide whether test or code wrong, fix test only when test wrong. Rerun until green.
5. Run project lint and type checks on test file; fix every error. Run full relevant suite; new tests must not break others.
6. Repeat 4-5 after each edit. Report cases covered, cases skipped with reason, suspected bugs, commands run. Never claim passing without run output.
