# 06. Recover links and protect saves

Status: active
Parent: [Project board](../../project-board.md)
Blocked by: 1 Create and reopen project boards

## Delivered behaviour

Preserve board edits across missing links and failed/conflicting saves.

## What to build

- Validate replacement file references and restore removed owner references explicitly.
- Use byte-based external-change checks; preserve unsaved state on failure and allow save copy or confirmed reload.
- Guard quitting with unsaved project state; use native document autosave/recovery lifecycle.

## Acceptance checks

- [x] External changes preserve both external bytes and unsaved board state.
- [x] Save-copy succeeds after conflict; invalid destinations preserve board state.
- [ ] Desktop relinking, close and crash/relaunch recovery evidence is recorded.


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
