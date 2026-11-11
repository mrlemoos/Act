# 0001. Line-scoped editor styling

Status: accepted
Date: 2026-11-11
Deciders: Leo Lemos

## Context

The formatted editor restyled the entire screenplay on every keystroke and on every caret move into another paragraph. A feature-length script (Port of Ambitions: 114,063 UTF-16 units, 4,311 lines, 99 scenes) took 113 ms per keystroke in a release build, 220 ms with the outline open. Constant-factor fixes (commit 9f9b94f) reduced this to about 25 ms, still above a 16 ms frame, and the cost remains proportional to script length.

Slugline, the reference editor for this workflow, does not restyle while the writer types inside a line. It restyles the line when the writer presses Return or the line loses focus: the caret moves to another line or the window stops being key.

Fountain classification is contextual. Editing one line can reclassify neighbours: uppercasing a line before text turns that text into dialogue, a blank line changes whether the next line is a scene heading, and a repeated speaker changes a later cue's CONT'D annotation. Restyling only the literal edited line would leave those neighbours wrong.

Character highlights and CONT'D annotations were tracked in coordinator arrays keyed by absolute ranges. Those ranges go stale as soon as text changes without a full restyle.

## Decision

1. Typing inside a single line does not restyle. New characters take the typing attributes of the line, minus character highlight attributes.
2. The editor commits styling when:
   - an edit inserts or removes a line break, including Return and multi-line paste;
   - the caret moves to another paragraph;
   - the editor resigns first responder or its window resigns key, which covers switching to another app;
   - the source is replaced outside typing (undo, redo, paper size), settings, column width or source mode change.
3. A commit reparses the script and compares each element's presentation (kind, text, CONT'D suffix, slugline spacing, blank-line collapse, marker fading) with the presentation last applied. Only elements whose presentation changed are restyled. In practice this is the edited line and the line the caret left or entered, widened only when Fountain context changes a neighbour.
4. The outline sidebar reads entries the document publishes at load, on non-typing source changes and on each commit, so typing does not reparse the script for it.
5. Styling state lives in the text storage, so it moves with edits: character highlights carry a custom attribute and the colour they cover; CONT'D annotations are a custom attribute on the cue range, drawn from the visible range.
6. External source replacement edits only the differing span of the text storage instead of resetting the whole string, so undo and redo restyle incrementally too.

## Alternatives

### Restyle the edited line on every keystroke

Keeps live styling while typing. Rejected: every keystroke still needs a full parse (about 8 ms in release) to classify the line in context, and styling mid-word flickers markers and slugline weight. It also departs from the Slugline behaviour the writer expects.

### Restyle the literal edited line only, never neighbours

Smallest change. Rejected: produces visibly wrong formatting when a line's classification depends on its neighbours (character cues, dialogue, scene headings, CONT'D).

### Incremental parser

Parse only the changed region. Not chosen now: commits are rare, and a full parse is about 8 ms in release. Revisit if commit cost becomes visible.

## Consequences

- Keystrokes inside a line no longer parse or restyle the script; cost no longer scales with styling work.
- While typing, the current line can briefly show stale formatting (for example a new slugline is not bold) until Return or focus loss. This is intentional and matches Slugline.
- The outline follows committed lines, not keystrokes: the document publishes outline entries on load, on non-typing source changes (undo, redo, paper size) and on each editor commit. A heading typed but not yet committed appears in the outline on Return or focus loss.
- Highlight and annotation code must keep reading from text attributes; reintroducing range arrays would reintroduce stale ranges.
- Commits triggered by a line-break edit run inside the text view's edit notifications, where attribute changes do not reach the layout manager. Each commit invalidates layout and display for the ranges it restyles; without that, a new cue keeps its old indent on screen until something else relays it out.

## Evidence

- Release timings on Port of Ambitions before this decision: 113 ms per keystroke, 220 ms with outline; after constant-factor fixes: 25 ms and 27 ms.
- Release timings on the same script after this decision: 3 ms per keystroke (13 ms with outline open), 19-24 ms per Return, 2-3 ms per caret move to another line.
- Built release app, 124-character typing burst mid-script with the outline open: the build before this decision fell 21-23 s behind (about 170 ms per key); after it, text caught up 50-90 ms after the last key.
- Regression tests: `Tests/ActAppTests/EditorPerformanceTests.swift`, `Tests/ActAppTests/LineStylingTests.swift`.

## Linked specs

- [Act screenwriting v1](../specs/screenwriting/spec.md)
