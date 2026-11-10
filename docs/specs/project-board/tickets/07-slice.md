# 07. Verify native project workflows

Status: active
Parent: [Project board](../../project-board.md)
Blocked by: 3 Outline with notes and groups, 4 Link selected scenes, 5 Open draft planning assets, 6 Recover links and protect saves

## Delivered behaviour

Record complete native workflow evidence and regression results.

## What to build

- Run core/native tests, app build and Galicia metadata check.
- Inspect light/dark/narrow layouts and actual creation, editing, navigation, links and document lifecycle.
- Record automation errors and unverified behaviour without claiming completion.

## Acceptance checks

- [x] All automated regression checks pass.
- [ ] Native drag, pinch, relinking, asset opening, save/reopen and recovery checks are evidenced.


## Validation

```sh
swift test
scripts/build-app.sh
node .galicia/check.ts
```

Record automated evidence and relevant native interaction limitations before completion.

## Context

- Parent spec: [Project board](../../project-board.md)
- ADRs: none
- Domain: [Context](../../../../context.md)
- Existing seams: ActCore persistence and ActApp native document/workspace tests.

## Out of scope

- Other slices and the parent exclusions.

## Evidence

Implementation present. See [validation evidence](../validation.md); unchecked native checks remain open.
