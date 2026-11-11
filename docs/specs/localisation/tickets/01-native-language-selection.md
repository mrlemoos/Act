# 01. Native language selection and menus

Status: complete
Parent: [App localisation](../../localisation.md)
Blocked by: none

## Delivered behaviour

Act follows macOS preferred app languages for en-GB, en-US, pt-BR, es-ES, fr-FR, de-DE and it-IT. Unsupported languages and missing translations fall back to British English. Packaged native menus retain actions and shortcuts.

## What to build

Implement this interface slice across native SwiftUI/AppKit callers, ActCore errors when relevant, and seven-locale bundled translation resources. Include interpolated values, tooltips and accessibility labels. Preserve the parent spec's document and generation boundaries. Supply a shared lookup and formatting contract, explicit British fallback, Swift package resources and app-bundle resource copying.

## Acceptance checks

- [x] Act follows macOS preferred app languages for en-GB, en-US, pt-BR, es-ES, fr-FR, de-DE and it-IT. Unsupported languages and missing translations fall back to British English. Packaged native menus retain actions and shortcuts.
- [x] Missing/unsupported translations resolve through British English without crashes or raw internal identifiers.
- [x] Tests exercise the slice's actual behavioural seam and retain existing persistence and content invariants.
- [x] Record scoped validation evidence before completion.

## Validation

Foundation locale/fallback and resource-contract tests pass. Native language/menu checks pass in seven fresh processes; the final app bundle includes both translation resource sets. See [recorded evidence and limits](../validation.md).

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
