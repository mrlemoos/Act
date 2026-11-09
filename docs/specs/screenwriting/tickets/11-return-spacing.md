# 11. Context-aware Return spacing

Status: complete
Parent: [Act screenwriting v1](../spec.md)
Blocked by: none

## Delivered behaviour

Return inserts two line breaks between screenplay blocks and one within character/dialogue blocks.

## What to build

Determine the current line's Fountain context from the selection start, including an unfinished character cue without existing dialogue. Character cues, dialogue and dialogue parentheticals receive one line break. A trailing empty line still belongs to dialogue until a blank separator ends that block. Action, scene headings, sections, synopses and other contexts receive two.

Apply this to the native screenplay editor, including source mode. Use native insertion so selection replacement, caret placement and document undo remain correct. Preserve the current or preceding local LF/CRLF/CR line-ending style. Do not intercept active IME composition or modified Return commands. Probe text used for classification is never written to the document.

## Acceptance checks

- [x] Return separates action/headings/outline paragraphs with two breaks.
- [x] Unfinished character cues, dialogue and parentheticals use one break.
- [x] Unicode selection context, blank dialogue boundaries and existing line endings are handled.
- [x] Native insertion places the caret correctly and is one document undo step.
- [x] Updated app bundle rebuilt and verified.

## Validation

```sh
swift test --filter FountainEditingTests
scripts/build-app.sh
node .galicia/check.ts
```

Seven focused tests pass. An offscreen AppKit harness in `.scratch/return-check/` invoked the actual editor delegate and checked native text, authoritative document source, caret placement and one-step undo for seven cases: action, slugline, character cue, dialogue, parenthetical, source mode and CRLF. No system input or live document was used.

## Context

- Parent spec: [Act screenwriting v1](../spec.md)
- ADRs: none
- Relevant code or domain context: [Context map](../../../../context.md)
- Validation: [Evidence](../validation.md)

## Out of scope

- Reformatting existing Fountain source or changing PDF layout.
- Adding a preference or changing Return in shot-list fields.

## Implementation evidence

The app rebuilt successfully and its local ad-hoc signature verified. The parent specification remains active.
