# 12. Automatic curly apostrophes

Status: complete
Parent: [Act screenwriting v1](../spec.md)
Blocked by: none

## Delivered behaviour

Typing a straight apostrophe inserts a right curly apostrophe in the screenplay editor.

## What to build

Convert a single typed ASCII apostrophe to U+2019 through native text insertion, in both formatted and source modes. Preserve selection replacement, caret behaviour and document undo/redo. Do not rewrite opening files or multi-character inserted/pasted strings. Keep already-curly apostrophes unchanged. Leave active IME composition and other native text insertion behaviour alone.

## Acceptance checks

- [x] Single apostrophes become U+2019, including contractions and possessives.
- [x] Selected apostrophe replacement and accented text work in the native editor.
- [x] Loaded source and multi-character paste are preserved literally.
- [x] Double quotes and already-curly apostrophes retain their input.
- [x] Each insertion remains one undo step and redo restores the same result.
- [x] The updated app bundle builds successfully.

## Validation

```sh
scripts/build-app.sh
node .galicia/check.ts
```

Eight offscreen native editor cases passed in `.scratch/apostrophe-check/check.sh`. They exercised actual insertion, authoritative source, loading preservation, selection replacement, source mode, undo and redo. No live document or system input was used. The existing offscreen Return harness checks that the new text-insertion override preserves Return behaviour.

## Context

- Parent spec: [Act screenwriting v1](../spec.md)
- ADRs: none
- Relevant code or domain context: [Context map](../../../../context.md)
- Validation: [Evidence](../validation.md)

## Out of scope

- Rewriting existing screenplay punctuation or multi-character pastes.
- Smart double quotation marks or changing generated continuation cue text.
- Adding another visible preference.
