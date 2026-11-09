# 07. Edit scene-linked shot lists

Status: complete
Parent: [Act screenwriting v1](../spec.md)
Blocked by: [01. Open and save screenplays](01-open-save.md), [02. Interpret Fountain scenes](02-fountain-scenes.md)

## Delivered behaviour

Separate persisted editable shot lists retain scene associations.

## What to build

Implement versioned shot-list JSON persistence and editable workspace. Include stable shot IDs and scene anchors, source revision metadata and stale/missing scene handling. Explicit save location, reload and errors. Provide framing, action, camera movement and rationale fields. Generated output enters this document, never Fountain source.

## Acceptance checks

- [x] Separate persisted editable shot lists retain scene associations.
- [x] Failures are visible and preserve existing user content.
- [x] Relevant automated checks pass; manual evidence and remaining limits are recorded.

## Validation

```sh
swift test --filter Shot
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

Native shot fields edited, survived workspace switching and saved as separate JSON. Six ShotListTests and nine ShotRecoveryTests pass, including stale/missing scenes, transactional replacement and identifier collision rejection. Compact rows show framing/action and collapse camera/rationale into Details. Latest compact shot controls compile; final native interaction check belongs to ticket08. See [validation](../validation.md).
