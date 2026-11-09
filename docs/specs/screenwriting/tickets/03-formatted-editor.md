# 03. Write in formatted screenplay view

Status: active
Parent: [Act screenwriting v1](../spec.md)
Blocked by: [01. Open and save screenplays](01-open-save.md), [02. Interpret Fountain scenes](02-fountain-scenes.md)

## Delivered behaviour

Courier screenplay editing with fading syntax, source mode and scene navigation.

## What to build

Build a native text editor with selection-safe formatting, undo support, screenplay indents and a source toggle. Scene navigation moves caret to correct UTF-16 ranges. Keep one editable source as authority; provide accessible controls and keyboard commands.

## Acceptance checks

- [ ] Courier screenplay editing with fading syntax, source mode and scene navigation.
- [ ] Failures are visible and preserve existing user content.
- [ ] Relevant automated checks pass; manual evidence and remaining limits are recorded.

## Validation

```sh
swift build && swift test
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

Native Courier layout, scene outline population, paste, undo and redo inspected. Latest compact interface rendered offscreen from actual app views and inspected at .scratch/compact-preview/screenplay.png. Outline now defaults hidden; counters, branding and status footer removed; Source/PDF moved to toolbar menu. Native source-toggle, navigation and final menu interactions remain for manual verification because computer-use transport failed. See [validation](../validation.md).
