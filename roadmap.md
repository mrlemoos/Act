# Act roadmap

A planned order for the next Act features, following the 20 November 2026 brainstorm. Fountain remains the source of truth. AI prose rewriting, cloud storage and real-time co-writing stay out of scope.

Effort is rough: S (days), M (about a week), L (longer, often with a format or platform risk).

## Suggested order

1. Finish the project board (in progress).
2. Character, slugline and transition autocomplete (specced).
3. Writer-controlled scene numbers.
4. Title-page editor.
5. Cast and location reports.
6. Portable project package (once board references are settled).
7. FDX import.
8. Outline drag-to-reorder.
9. FDX export (after the import model exists).
10. Timeline or pacing view.
11. Draft compare.
12. Revision marks and coloured revision PDFs.
13. Storyboard frames for selected shots.
14. Offline table read.
15. PDF to Fountain import.
16. iPhone and iPad companion (after a portable package exists).

Items 3–5 can follow autocomplete immediately; they are small writing tools and do not wait on the board. Item 6 can start once the in-progress board work has a stable reference model. FDX export should not precede import.

## 1. Finish the project board — in progress — M

The remaining board work from [docs/specs/project-board.md](docs/specs/project-board.md): trackpad pan and zoom, moving groups, scene cards, opening a card in the editor, previews, links across drafts, and relinking missing files. The board is already the project home, but those gaps leave it unfinished.

A separate coding agent is implementing this. This roadmap only records the status. Do not start overlapping board work here.

Depends on the existing board implementation. Unlocks portable packages, draft compare, and opening drafts from the board.

## 2. Character, slugline and transition autocomplete — specced — S–M

Inline completions for speaking cues (including extensions such as `(V.O.)`, but never `(CONT'D)`), scene headings (INT./EXT., locations, and a built-in time-of-day list in the app locale) and transitions. Rank from the current screenplay first, then a small built-in set. Character-library names are a secondary source only while the writer is typing in uppercase.

Every comparable editor has this, and Act already classifies the three element kinds in `FountainParser`. The draft specification is [docs/specs/autocomplete.md](docs/specs/autocomplete.md). The open candidate-source questions are now decided; a few locale-specific time-of-day wordings remain for review and do not block implementation. Recommend a breakdown into an ActCore engine slice and a native editor-UI slice once work is authorised.

Depends on the existing parser, editor and `L10n` contract, not on the board. Shares element harvest with later cast and location reports.

## 3. Writer-controlled scene numbers — S–M

Let the writer insert, lock and renumber Fountain `#n#` scene numbers in source, so shot-list links stop breaking when scenes move.

The parser already reads `#n#` for scene identity (`FountainParser` / `FountainScene`). Without writer control, numbers are easy to mistype and painful to keep stable.

Depends on the existing parser. Helps shot lists and any later reports that jump to a scene. Independent of autocomplete, but natural to do next.

## 4. Title-page editor — S

A small form that writes only the known title-page metadata keys (title, credit, author, source, draft date, contact, copyright, notes, paper) and leaves the rest of the source untouched.

Title-page fields are already parsed and shown in PDF preview, but they are awkward to edit as raw keys. A form should not become a second source of truth.

Depends on the existing title-page parse and `Paper:` handling. No dependency on the board or FDX.

## 5. Cast and location reports — S

Lists of speaking characters, locations and times of day, each jumping to the relevant line.

Cheap once heading and cue harvest exists, and useful for production conversations without leaving Act. Read-only; they must not rewrite Fountain.

Best after autocomplete (shared harvest). Scene numbers would make jumps clearer but are not required.

## 6. FDX import — L

Open Final Draft `.fdx` files as Fountain in Act.

Agents and producers still send FDX, so this is what makes Act usable as an everyday editor. Conversion will not be perfect; the result must be ordinary Fountain the writer can review.

Independent of the board. Should precede FDX export so both share one mapping. Large because the format is wide and lossy.

## 7. FDX export — L

Write a Final Draft `.fdx` copy for readers who only use Final Draft. The Act document remains Fountain.

Depends on the import mapping (item 6) so round-tripping is defined in one place. Does not replace Fountain as the native format.

## 8. Revision marks and coloured revision PDFs — L

Track revisions and export coloured revision PDFs. Store marks in a sidecar, not in the raw Fountain, so source stays clean and comparable.

Production paperwork that Highland and Final Draft already treat as standard. Sidecar authority must follow the same pattern as shot lists: never silently edit the screenplay.

Easier once scene numbers exist. FDX import/export may need to declare how marks travel; that can be a later contract. Large because of pagination, colours and production conventions.

## 9. Drag to reorder in the outline — M

Drag scenes or sections in the outline and apply that as a deliberate, undoable rewrite of the Fountain source.

Writers already think in the outline; today, reordering means cutting and pasting source by hand. The rewrite must be explicit and undoable, never a silent board-style rearrangement. The project board must still not change screenplay order on its own.

Depends on the existing outline. Independent of the board. Scene numbers should be locked or reviewed so reordering does not scramble production numbers.

## 10. Timeline or pacing view — M

A view built from the same page breaks the PDF uses, so a slow second act is visible at a glance.

Page count is already a production language Act speaks in export. This is a read-only presentation of that pagination, not a second layout engine.

Depends on the existing PDF paginator. Independent of FDX. More useful once scene numbers are visible.

## 11. Portable project package — M

A project package with relative paths, so a board can move to another Mac without every card breaking.

Version-1 boards store absolute paths and already exclude portability pending a separate decision. This is the first time a project will actually travel.

Depends on the finished board reference model (item 1). Should precede an iOS companion that shares files through iCloud. May need a short ADR for package layout and identity.

## 12. Draft compare — M

Compare two Fountain files from the board and show a readable difference.

Drafts already live as separate Fountain files on the board. Writers need to see what changed without leaving Act or pasting into another tool.

Depends on the board being able to open and identify drafts (item 1). Revision marks (item 8) are a different, production-oriented history and should not block a basic compare.

## 13. Storyboard frames for selected shots — M–L

Generate stills for chosen shots, with the same prompt preview and explicit approval already used for character sheets.

Natural extension of local shot planning, but it must stay opt-in and must not rewrite Fountain or the shot list unless the writer accepts the image. Reuse the character-sheet approval pattern.

Depends on existing shot lists and the character-sheet agent approval flow. No dependency on FDX.

## 14. PDF to Fountain import — L

Import a screenplay PDF to Fountain, with a mandatory review step.

Useful for material that only exists as a PDF, but conversion will never be perfect, so the writer must review before the result becomes a working draft.

Independent, large, and should not precede FDX import (FDX is the more faithful interchange). Keep it behind a review UI; never overwrite an open document silently.

## 15. iPhone and iPad companion — L

A companion app that edits the same Fountain files through iCloud.

Writing happens away from the Mac. This is large (another platform, document lifecycle, and conflict handling) and only makes sense once projects can travel as relative packages (item 11). Still no Act-hosted cloud and no real-time co-writing.

## 16. Offline table read — M

Read the script aloud with macOS voices, a distinct voice per character.

A practical, fully offline use of the cue list already in the parser. It must not change source, and voice choices belong in settings or a sidecar, not in Fountain.

Depends only on character-cue parsing. Cast reports (item 5) would give a convenient roster, but are not required.

## Deliberate exclusions

These stay out of the roadmap on purpose, as in the v1 screenwriting spec and the brainstorm:

- AI prose rewriting of Fountain source.
- Act-hosted or sync-service cloud storage (iCloud file sharing for a later companion is device sync of the writer's own files, not an Act cloud).
- Real-time co-writing or collaboration.

Custom fonts, signing, notarisation and publication also remain outside this list.