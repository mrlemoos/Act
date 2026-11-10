# 14. Title-page preview and per-screenplay paper size

Status: complete
Parent: [Act screenwriting v1](../spec.md)
Blocked by: none

## Delivered behaviour

Command-P opens a reusable PDF preview window for the active screenplay. It offers Print, Export PDF and a per-file paper selector. Source and presentation-setting edits refresh the preview after a 250 ms debounce; the viewer retains its current page and destination where possible.

## What to build

Fountain metadata `Paper: US Letter` or `Paper: A4` controls preview, print and export. Missing or unknown values use US Letter without changing source. Selecting a size writes canonical metadata through document undo and dirty tracking. Other source bytes and existing line endings remain unchanged. Paper metadata alone does not generate a title page and never appears in the PDF body.

Render title, credit, author/authors and source centrally in conventional order, regardless of metadata order. Contact, copyright, draft date and notes form a lower-left block. Indented continuation lines retain embedded colons. Oversized title content continues onto additional unnumbered pages without shrinking text. Body numbering starts separately, omitting the first body page's number.

US Letter is 612 × 792 PDF points. A4 is 595.2756 × 841.8898 points. Preserve physical margins and selected typography; adjust action wrapping and bottom bounds to the selected sheet.

## Acceptance checks

- [x] Command-P opens and reuses the active screenplay's preview.
- [x] Preview responds to source and presentation-setting changes.
- [x] Paper selection changes only that screenplay, supports undo and persists in Fountain.
- [x] Missing/unknown metadata defaults to US Letter without unsolicited rewrites.
- [x] Metadata updates preserve Unicode and LF, CRLF and CR line endings.
- [x] Multiline titles and contact details preserve colons and avoid clipping.
- [x] Title overflow remains unnumbered; body numbering remains separate.
- [x] Preview export and native print preparation use the same PDF renderer and paper size.
- [x] PDF failures are visible; failed export does not replace existing user files with partial data.

## Validation

```sh
swift test
ACT_TEST_PDF_PREVIEW_DIRECTORY="$PWD/.scratch/pdf-paper-preview" swift test
scripts/build-app.sh
node .galicia/check.ts
```

The full default suite passed on 10 November 2026, including five new core paper/title tests and four new native preview tests. Existing opt-in model checks remained skipped. New native checks cover per-document undo/dirty tracking, live source/preferences refresh and the Command-P menu binding.

Letter title and A4 body PDFs were rendered with Poppler and visually inspected. Offscreen PDFView snapshots do not capture its composited content reliably and are not visual proof. Live computer-use inspection of the built app verified Command-P, rendered title-page content, the A4 selector, metadata appearing in the editor, Command-S, preview export and closing/reopening the preview. The exported live PDF was checked separately for A4 dimensions. The native print dialogue displayed both pages and was cancelled. Physical printer output was not tested because no printer was selected.

## Context

- Parent spec: [Act screenwriting v1](../spec.md)
- ADRs: none
- Relevant code or domain context: [Context map](../../../../context.md)

## Out of scope

- Global paper preferences, automatic metadata repair, new title-page editing forms.
- Signing for distribution, publication or committing changes.
