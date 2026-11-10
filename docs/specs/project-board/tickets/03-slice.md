# 03. Outline with notes and groups

Status: active
Parent: [Project board](../../project-board.md)
Blocked by: 2 Navigate and arrange cards

## Delivered behaviour

Write standalone beat notes and organise cards in named spatial groups.

## What to build

- Support editable card titles/body text and editable group names.
- Assign membership explicitly and move groups with their members; removing groups retains cards.

## Acceptance checks

- [x] Native note creation and text editing work.
- [x] Group movement preserves member offsets and leaves unrelated cards untouched.
- [ ] Native group dragging has successful desktop evidence.


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
