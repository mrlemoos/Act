# 02. Interpret Fountain scenes

Status: complete
Parent: [Act screenwriting v1](../spec.md)
Blocked by: none

## Delivered behaviour

Parse screenplay elements and scene boundaries with persistent scene references.

## What to build

Implement Sources/ActCore/Fountain.swift and Tests/ActCoreTests/FountainTests.swift. Public FountainParser.parse(_ source: String) -> FountainScreenplay; screenplay has source, elements and scenes. Elements expose kind, text and UTF-16 NSRange. Scenes expose id, heading, text and range. Cover title pages, forced headings, dialogue, dual dialogue, transitions, notes, boneyards and Unicode. Raw source remains authoritative; scene identity must survive edits outside the scene.

## Acceptance checks

- [x] Parse screenplay elements and scene boundaries with persistent scene references.
- [x] Failures are visible and preserve existing user content.
- [x] Relevant automated checks pass; manual evidence and remaining limits are recorded.

## Validation

```sh
swift test --filter FountainTests
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

Nine Fountain tests pass, including raw-source/UTF-16 preservation, stable numbered scene references, repeated headings, forced syntax and inline/multiline comments. Repeated unnumbered heading insertion can change later occurrence IDs; fingerprints flag changed associations. See [validation](../validation.md).
