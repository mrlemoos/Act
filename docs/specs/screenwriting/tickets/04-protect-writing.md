# 04. Protect writing

Status: active
Parent: [Act screenwriting v1](../spec.md)
Blocked by: [01. Open and save screenplays](01-open-save.md)

## Delivered behaviour

Autosave, undo, crash recovery and explicit external-change conflicts.

## What to build

Use native document undo and autosave where possible. Restore recoverable text after interruption. Detect changed backing files and offer reload or keep/save-copy without silently overwriting either version. Surface write failures.

## Acceptance checks

- [ ] Autosave, undo, crash recovery and explicit external-change conflicts.
- [ ] Failures are visible and preserve existing user content.
- [ ] Relevant automated checks pass; manual evidence and remaining limits are recorded.

## Validation

```sh
swift test --filter Document
```

Use behavioural tests at the relevant parser, document, PDF or runtime seam. Record evidence before marking complete. UI and real inference require separate manual checks.

## Context

- Parent spec: [Act screenwriting v1](../spec.md)
- ADRs: none
- Domain context: [Context map](../../../../context.md)

## Out of scope

- Other tickets' owned implementation, except agreed integration changes.
- Signing, notarisation, publication and custom font.

## Implementation evidence

Native document save and undo/redo verified. DocumentTests checks changed/missing backing files. Nine ShotRecoveryTests prove metadata restoration, first-save/rename migration, unique untitled matching, ambiguity rejection and preservation after failed migration. Native crash/relaunch and live external-change conflict interactions remain unverified; no claim of end-to-end crash recovery. See [validation](../validation.md).
