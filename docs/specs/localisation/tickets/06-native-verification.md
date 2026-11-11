# 06. Completeness and native verification

Status: complete
Parent: [App localisation](../../localisation.md)
Blocked by: [2. Writing, settings and PDF interface](02-writing-interface.md), [3. Shot planning interface](03-shot-planning.md), [4. Character interface](04-character-interface.md), [5. Project board interface](05-project-board.md)

## Delivered behaviour

All seven locales have complete translations with compatible substitutions and count forms. The packaged app selects languages natively, falls back to British English and renders usable layouts. Existing editing, persistence and generation contracts pass regression checks.

## What to build

Implement this interface slice across native SwiftUI/AppKit callers, ActCore errors when relevant, and seven-locale bundled translation resources. Include interpolated values, tooltips and accessibility labels. Preserve the parent spec's document and generation boundaries. Use the shared locale lookup and formatting contract from ticket 1.

## Acceptance checks

- [x] All seven locales have complete translations with compatible substitutions and count forms. The packaged app selects languages natively, falls back to British English and renders usable layouts. Existing editing, persistence and generation contracts pass regression checks.
- [x] Missing/unsupported translations resolve through British English without crashes or raw internal identifiers.
- [x] Tests exercise the slice's actual behavioural seam and retain existing persistence and content invariants.
- [x] Record scoped validation evidence before completion.

## Validation

The final integrated suite reports 164 tests, zero failures and three opt-in real-inference skips. Seven fresh native locale processes pass with 13 valid renders each, including visible PDF toolbar checks at minimum width. Packaged app build/signature and native smoke checks pass. See [recorded evidence and limits](../validation.md).

```sh
swift test
scripts/build-app.sh
node .galicia/check.ts
```

Use native app tests for visible labels, menus and document state where applicable. Ticket 6 records packaged-app and layout evidence across all seven locales; earlier slices require scoped checks.

## Context

- Parent spec: [App localisation](../../localisation.md)
- ADRs: none
- Domain: [Screenwriting](../../../../context.md)
- Contracts: [Screenwriting v1](../../screenwriting/spec.md), [Characters](../../screenwriting/character-sheets.md), [Project board](../../project-board.md)
- Test seams: [Tests](../../../../Tests/README.md)

## Out of scope

- Changes to stored/generated content, language switching without relaunch, deployment and publication.
