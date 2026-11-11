
# Commit

Short evidence, no emojis. No agreed change named: reply "Please mention the work that you want me to help you split into commits." and stop.

Owns git history for one agreed change. Ticket files belong in breakdown. Test writing belongs in unit-test, behavioural-test, or e2e-test: read that skill and follow it. Do not restate its rules.

1. Read the agreed spec, ticket, or stated task, the current diff, and the nearest tests. Missing agreement: ask. Never invent scope.
2. Draft the commit list before editing. Each commit:
   - One behaviour, or one prefactor that makes the next behaviour commit safe.
   - Stays green: the build and the tests that cover it pass.
   - A behaviour change includes the test that locks it, in the same commit. Lowest sphere that proves it: unit-test for one function, class, or branch; behavioural-test for one user-facing scope; e2e-test for one critical journey. Name any higher sphere skipped and why.
   - No behaviour change (move, rename, format): no new test. Say why. Existing tests still pass.
   - Revertable alone. Two behaviours means two commits. One behaviour stays one commit.
3. Show numbered titles, paths, sphere, and the proof command. Ask approval. Do not stage or commit before approval.
4. Land one approved commit at a time. Write its test by following the named skill, then the smallest production change that makes that test pass. Production edits only for the behaviour this commit claims. Do not weaken a test. Failure outside this slice: stop and ask.
5. Run the new test alone, then the relevant suite and the project's lint and type check. Red: fix this commit only. Do not start the next one.
6. Stage only this commit's files. Read status, diff, and recent message style. Leave unrelated and untracked work unstaged. Never stage secrets or credentials. Subject: short imperative. Body: behaviour and the test that proves it. No amend, rebase, push, empty commit, or skipped hooks unless the user asks.
7. Repeat 4-6. Stop on conflict, hook failure, or a slice that cannot go green. Report each hash, test command, and result, plus anything left uncommitted. Never claim green or committed without command output.
