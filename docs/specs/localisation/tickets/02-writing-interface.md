# 02. Writing, settings and PDF interface

Status: complete
Parent: [App localisation](../../localisation.md)
Blocked by: [1. Native language selection and menus](01-native-language-selection.md)

## Delivered behaviour

Writing controls, outline placeholders, style settings and bundled examples, PDF preview/export controls, document alerts, tooltips and accessibility labels appear in the selected language. Existing screenplay source and exported screenplay text remain unchanged.

## What to build

Implement this interface slice across native SwiftUI/AppKit callers, ActCore errors when relevant, and seven-locale bundled translation resources. Include interpolated values, tooltips and accessibility labels. Preserve the parent spec's document and generation boundaries. Use the shared locale lookup and formatting contract from ticket 1.

## Acceptance checks

- [x] Writing controls, outline placeholders, style settings and bundled examples, PDF preview/export controls, document alerts, tooltips and accessibility labels appear in the selected language. Existing screenplay source and exported screenplay text remain unchanged.
- [x] Missing/unsupported translations resolve through British English without crashes or raw internal identifiers.
- [x] Tests exercise the slice's actual behavioural seam and retain existing persistence and content invariants.
- [x] Record scoped validation evidence before completion.

## Validation

Three writing localisation tests pass alongside native editor, document, presentation and PDF regression tests. Actual settings/examples were inspected across seven locale renders. See [recorded evidence and limits](../validation.md).

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
