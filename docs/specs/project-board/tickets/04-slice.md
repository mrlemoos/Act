# 04. Link selected scenes

Status: complete
Parent: [Project board](../../project-board.md)
Blocked by: 2 Navigate and arrange cards

## Delivered behaviour

Select scenes from a draft outline while preserving independent visual ordering.

## What to build

- Add scene cards only on explicit selection, retaining identity and source fingerprint.
- Display changed/missing states; explicit review acknowledges changed text without changing notes/position.

## Acceptance checks

- [x] Current, changed and missing scene states are distinguished.
- [x] Scene-card layout never edits Fountain and no silent relinking occurs.


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

Automated acceptance evidence recorded. See [validation evidence](../validation.md); unchecked native checks remain open.
