# 10. Settings sidebar and live examples

Status: complete
Parent: [Act screenwriting v1](../spec.md)
Blocked by: none

## Delivered behaviour

Writing settings opens in a collapsible right sidebar with examples that update as preferences change.

## What to build

Route Act > Settings, Command-comma and the toolbar Settings action to the active document's right sidebar. Create a document if none is open. Keep settings hidden by default and provide a close control. The left outline and right settings sidebar are mutually exclusive to preserve writing width.

Show a read-only example of the selected font/size, system sans section heading, bold/regular slugline, one/two blank lines before it and repeated dialogue cue. Use the shared continuation presentation helper. The examples do not alter Fountain source. Preferences remain app-wide and persisted.

Adapt the native editor's dialogue indents when the available writing width changes. Keep the settings controls scrollable at small window heights.

## Acceptance checks

- [x] Settings routes to the right sidebar, without a separate settings window.
- [x] Preference mutation updates both the main editor and live example in the same hosting view.
- [x] Narrow 820-point layout remains readable without horizontal clipping.
- [x] Closing the sidebar restores the centred full-width writing layout.
- [x] Preview checks preserve exact Fountain source and leave live preferences untouched.
- [x] The app rebuilds successfully.

## Validation

```sh
scripts/build-app.sh
node .galicia/check.ts
```

Actual native views rendered offscreen under `.scratch/settings-sidebar-preview/`. `standard-wide.png` shows Courier 12, bold sluglines, two lines and CONT'D. After changing the same observed preferences, `menlo-wide.png` and `menlo-narrow.png` show Menlo 14, regular sluglines, one line and CONT'D disabled in both the editor and example. `menlo-panel-closed.png` verifies restored writing width. The harness asserts source equality and uses an isolated preferences suite.

No core parsing, persistence or inference logic changed. This UI revision was checked through compilation and actual-view rendering; earlier automated regression evidence remains in parent validation. Live desktop menu clicks were not rechecked.

## Context

- Parent spec: [Act screenwriting v1](../spec.md)
- ADRs: none
- Relevant code or domain context: [Context map](../../../../context.md)
- Validation: [Evidence](../validation.md)

## Out of scope

- Changing Fountain source or PDF layout.
- Per-document style preferences or new typography controls.
