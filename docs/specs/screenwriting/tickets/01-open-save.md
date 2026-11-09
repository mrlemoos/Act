# 01. Open and save screenplays

Status: complete
Parent: [Act screenwriting v1](../spec.md)
Blocked by: none

## Delivered behaviour

Runnable Swift macOS app opens, edits and saves UTF-8 Fountain without losing source content.

## What to build

Implement a Swift package with ActCore library, Act executable and ActCoreTests. Native document windows, open/save panels, correct filename handling and a runnable app bundle script. Preserve line endings and unrecognised Fountain syntax.

## Acceptance checks

- [x] Runnable Swift macOS app opens, edits and saves UTF-8 Fountain without losing source content.
- [x] Failures are visible and preserve existing user content.
- [x] Relevant automated checks pass; manual evidence and remaining limits are recorded.

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

Native app opened FirstLight.fountain after removing competing UTI filtering. Native save wrote the exact synthetic screenplay to .scratch/ui-checks/Act-UI-Test.fountain. UTF-8 BOM and line-ending round-trips pass DocumentTests. Build passes. See [validation](../validation.md).
