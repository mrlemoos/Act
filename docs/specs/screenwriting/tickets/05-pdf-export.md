# 05. Export screenplay PDFs

Status: complete
Parent: [Act screenwriting v1](../spec.md)
Blocked by: [02. Interpret Fountain scenes](02-fountain-scenes.md)

## Delivered behaviour

Export paginated Courier screenplay PDFs.

## What to build

Implement Sources/ActCore/ScreenplayPDF.swift. Use Fountain elements to lay out title page, scene headings, dialogue, character cues and transitions. US Letter screenplay page with conventional margins; avoid isolated character cues, measure overflow and preserve Unicode. PDF export panel belongs to app integration.

## Acceptance checks

- [x] Export paginated Courier screenplay PDFs.
- [x] Failures are visible and preserve existing user content.
- [x] Relevant automated checks pass; manual evidence and remaining limits are recorded.

## Validation

```sh
swift test --filter PDF
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

Seven PDF tests pass, covering Letter geometry, Unicode extraction, measured overflow, cue protection, side-by-side dual dialogue, hidden comments and long title/contact pagination. Representative title/body PDF visually inspected in .scratch/pdf-preview/. See [validation](../validation.md).
