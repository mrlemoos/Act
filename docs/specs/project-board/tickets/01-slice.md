# 01. Create and reopen project boards

Status: complete
Parent: [Project board](../../project-board.md)
Blocked by: none

## Delivered behaviour

Open a local .actboard project, link existing drafts and reopen saved state.

## What to build

- Register project document type without changing standalone Fountain opening. Present Board inside the main workspace tabs; project documents create no separate board window.
- Persist versioned board data, stable identities, references and viewport state.

## Acceptance checks

- [x] Project and Fountain documents route to their respective native views.
- [x] Save/reopen preserves project state without changing draft bytes.


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
