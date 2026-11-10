# 02. Navigate and arrange cards

Status: active
Parent: [Project board](../../project-board.md)
Blocked by: 1 Create and reopen project boards

## Delivered behaviour

Pan, zoom and arrange cards independently of screenplay order.

## What to build

- Implement bounded zoom anchored at the pinch point, background panning and card-header movement.
- Remove only board references and preserve undo/redo state.

## Acceptance checks

- [x] Automated navigation preserves the pinch anchor and clamps zoom.
- [x] Removing a card leaves source files unchanged; undo restores the card.
- [ ] Native drag and physical pinch interaction have successful desktop evidence.


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
