# 08. Integrate and verify release

Status: active
Parent: [Act screenwriting v1](../spec.md)
Blocked by: [03. Write in formatted screenplay view](03-formatted-editor.md), [04. Protect writing](04-protect-writing.md), [05. Export screenplay PDFs](05-pdf-export.md), [06. Generate shots locally](06-local-shots.md), [07. Edit scene-linked shot lists](07-shot-documents.md)

## Delivered behaviour

Runnable integrated macOS app with verified writing, export and local generation.

## What to build

Wire editor, recovery, PDF export, runtime setup and editable shot documents. Inspect actual UI. Verify keyboard access, undo, multiple windows, long scripts, external changes, cancellation and restart. Run actual offline inference where runtime/model are available; record blockers accurately. Provide app bundle and instructions; signing/notarisation and publication excluded.

## Acceptance checks

- [ ] Runnable integrated macOS app with verified writing, export and local generation.
- [ ] Failures are visible and preserve existing user content.
- [ ] Relevant automated checks pass; manual evidence and remaining limits are recorded.

## Validation

```sh
swift build && swift test && node .galicia/check.ts
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

Integrated app builds and 41 tests pass with both opt-in real-model checks enabled. Earlier native opening, saving, formatted text, undo/redo and shot persistence were verified. Compact screenplay was rendered offscreen and inspected. Remaining native checks are listed in validation.md; CUA inventory reported native pipe closed and browser host unavailable. Read-only process sampling showed Act idle in NSApplication.run, not a close deadlock. Parent remains active. See [validation](../validation.md).
