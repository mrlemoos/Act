# 05. Open draft planning assets

Status: active
Parent: [Project board](../../project-board.md)
Blocked by: 1 Create and reopen project boards

## Delivered behaviour

Reach original draft character sheets and selected shot lists from board cards.

## What to build

- Link draft-owned character collections and existing shot JSON files; display available thumbnails.
- Open existing workspaces, retain original provenance and show explicit additional draft links.
- Protect pending shot edits when switching linked lists.

## Acceptance checks

- [x] Linked shot files validate before use and retain independent persistence.
- [x] Character previews can load from validated local libraries without opening a draft.
- [ ] Successful desktop asset-opening and sharing evidence is recorded.


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
