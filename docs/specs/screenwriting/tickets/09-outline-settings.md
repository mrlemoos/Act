# 09. Outline bodies and screenplay settings

Status: complete
Parent: [Act screenwriting v1](../spec.md)
Blocked by: none

## Delivered behaviour

Fountain `=` synopsis lines appear as outline body text. A separate Settings window controls screenplay font, spacing before scene headings, heading weight and automatic dialogue continuations.

## What to build

Show sections, scenes and synopsis bodies in source order. Associate synopsis bodies with the nearest scene or section, including bodies before the first scene. Outline selection navigates each entry's exact UTF-16 source range.

Persist app-wide font family, screenplay point size, one/two blank lines before sluglines, bold/regular sluglines and automatic dialogue CONT'D. Apply them live to formatted editing and PDF export. Keep source view literal. Default to Courier 12 pt, two blank lines, bold sluglines and continuations enabled. The editor retains its existing readable scale relative to print size.

Continuation cues are generated presentation only when the same speaker resumes after action within the same scene. Do not duplicate explicit CONT'D. PDF dialogue spanning pages includes MORE and repeated continued cues when enabled, including dual dialogue. Settings do not remove explicit source cues or rewrite source whitespace. Notes, sections and synopses remain excluded from screenplay PDF body output.

Hashtag section heading text uses pink for level one, blue for level two and orange for level three or deeper, in both formatted editor and outline. Colours adapt to light and dark appearance.

Settings opens from Act > Settings, Command-comma or the existing toolbar menu. Keep additional controls off the writing screen. Unavailable fonts fall back to Courier; invalid/corrupt stored settings use validated defaults.

## Acceptance checks

- [x] Outline bodies preserve source order, ownership, Unicode navigation and hidden-comment exclusions.
- [x] Saved settings survive a new reader; corrupt or invalid values cannot break layout.
- [x] PDF settings affect font, wrapping, heading spacing and heading weight without source mutation.
- [x] Repeated and page-spanning dialogue continuations respect the toggle and avoid duplication.
- [x] Current settings, outline and native editor presentation are visually inspected and app bundle rebuilt.

## Validation

```sh
swift test
scripts/build-app.sh
node .galicia/check.ts
```

The integrated run passed 56 tests, with the two unchanged opt-in real-AI checks skipped. Focused PDF recheck covers the final long-cue preflight adjustment. Offscreen native view previews are separate from live desktop interaction.

## Context

- Parent spec: [Act screenwriting v1](../spec.md)
- ADRs: none
- Domain context: [Context map](../../../../context.md)
- Validation: [Evidence](../validation.md)

## Out of scope

- Generating a new custom font or distributing proprietary fonts.
- Per-document settings, collaboration and changing the local inference runtime.
- Adding presentation CONT'D or spacing into raw Fountain source.

## Implementation evidence

The app bundle rebuilt successfully. Offscreen light/dark previews confirm all three heading colours, settings controls and generated CONT'D. The full regression suite passed 56 tests with two opt-in AI checks skipped; the final PDF recheck passed all 12 PDF cases. Native desktop Settings interaction remains unverified and is recorded in parent integration validation. Parent specification remains active.

Settings location was subsequently changed by [10. Settings sidebar and live examples](10-settings-sidebar.md).
