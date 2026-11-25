# Screenplay pinch zoom

Status: active
Domain: Screenwriting
Owner: Leo
Related ADRs: [Line-scoped editor styling](../adr/0001-line-scoped-editor-styling.md)
Tickets: none

## Problem

The screenplay editor has no explicit pinch zoom or visible magnification control. Writers need to enlarge or reduce the screenplay without changing its typography preferences, Fountain source or exported PDF. The project Board already has separate zoom behaviour and is outside this change.

## Intended behaviour

Spreading two fingers on a trackpad over the screenplay zooms in. Pinching them together zooms out. Magnification changes continuously during the gesture, between 50% and 200%, with the document position beneath the pointer held stable where scroll bounds permit.

Zoom scales the whole screenplay presentation. It does not change the logical text column, font settings, paragraph geometry or line wrapping at a given window size. Normal window resizing may retain its existing layout behaviour. Enlarged content can scroll horizontally when it exceeds the viewport. Vertical scrolling continues to work.

A control containing a zoom icon and the current percentage stays at the bottom-right corner of the screenplay viewport. It stays fixed while the document scrolls and remains outside the scaled content. Clicking it opens a popover with minus, plus and Reset to 100% controls. Minus and plus change magnification by 10 percentage points, clamped to the same bounds. The percentage updates during gestures and button changes.

Each writing window owns its zoom for its lifetime. Switching between formatted screenplay and Fountain source preserves the value. Recreating the editor during the same window session must not reset it. A newly opened or reopened window starts at 100%. Zoom is not a saved document setting or an app-wide preference.

Zoom never edits Fountain, marks the document modified, adds an undo entry or changes PDF output. Selection, caret position and existing undo history survive zoom. Pointer-based editing and selection remain aligned with the displayed text at every supported scale.

## Acceptance checks

- [ ] A physical trackpad spread enlarges the screenplay continuously; a pinch reduces it.
- [ ] Zoom stops at 50% and 200%; reversing direction responds immediately at either bound.
- [ ] The document position beneath the pointer remains stable during a gesture, except where scrolling must clamp at a document edge.
- [x] The bottom-right icon and percentage remain fixed and visible during scrolling and zooming.
- [x] The popover supports minus, plus and Reset to 100%; buttons use 10-percentage-point steps and obey the bounds.
- [x] At a fixed window size, zoom preserves logical wrapping and formatting. Overflow remains reachable by horizontal and vertical scrolling.
- [ ] Typing, clicking, selecting text and navigating to a scene work at 50%, 100% and 200% without offset errors.
- [x] Fountain source, document modified state, selection and undo history remain unchanged by zoom alone; PDF output retains its existing layout.
- [x] Source-mode switches preserve zoom. Editor reconstruction within a window preserves zoom. A separate or reopened window starts at 100%.
- [ ] The zoom control works by keyboard, exposes accessible names and its current value, and remains usable in light and dark appearances.
- [ ] Ending or cancelling a gesture leaves a valid bounded value; ordinary two-finger scrolling continues to scroll.

## Decisions and contracts

The agreed scope is the screenplay editor, including its Fountain source presentation. Board zoom, other workspace tabs and window chrome do not scale.

Use one window-owned magnification value for gestures, the percentage display and popover actions. This is presentation state, separate from screenplay preferences and document content. Preserve ADR 0001's line-scoped styling contract. A magnification update must not masquerade as a font-setting or logical column-width change that reparses or restyles the entire screenplay on every gesture event.

Current integration points are `Sources/Act/ScreenplayEditor.swift`, which hosts the native text and scroll views, and `Sources/Act/WorkspaceView.swift`, which owns writing-window presentation. These paths describe ownership, not a required implementation recipe.

Accessible labels and visible control text follow the existing localisation system. No durable process boundary or storage format changes are required, so this change does not require a new ADR or ticket breakdown.

## Test seam

Use the existing `ActAppTests` native editor seam, agreed during discussion. `Tests/ActAppTests/TestEditorHost.swift` hosts the actual editor in a hidden native window. Extend this seam only as needed to exercise magnification and inspect displayed geometry and document state. Existing `NativeEditorTests`, `LineStylingTests`, `PresentationTests` and `EditorPerformanceTests` provide editing and layout regression coverage.

Automated checks must cover bounds, button steps, displayed percentage, preserved source and selection, undo isolation, logical layout, pointer anchoring and window-session ownership. Use actual hosted views for layout and editing outcomes rather than tests that merely repeat a scale formula. Existing PDF checks protect export behaviour.

Hidden-window tests do not prove physical trackpad event routing or gesture feel. A visible native app check must demonstrate spread, pinch, reversal at limits, scrolling, text selection at scale and use of the bottom-right controls. Record physical evidence separately from automated results.

## Validation

```sh
zsh scripts/build-cli.sh
swift test --no-parallel
scripts/build-app.sh
node .galicia/check.ts
```

Run the native app checks on macOS with a trackpad, including a narrow window, a feature-length screenplay, both editor modes, both appearances and multiple writing windows. Completion requires recorded automated results and successful physical gesture checks.

### Evidence recorded on 25 November 2026

- `swift test --no-parallel` passed with 216 tests passing and three opt-in model tests skipped. This includes six new `ScreenplayZoomTests` against the actual native editor, plus existing editor performance, layout, PDF and localisation coverage.
- Native zoom regressions cover synthetic spread/pinch events, cancellation, immediate reversal at limits, non-finite input, pointer anchoring after text layout, unchanged attributed content and column geometry, selection and undo isolation, text hit testing and editing at 50%, 100% and 200%, model steps, source-mode changes, editor reconstruction and independent session state.
- `scripts/build-app.sh` built and signed `.build/Act.app`. `node .galicia/check.ts` and `git diff --check` passed. Native builds and the full suite required normal macOS service access outside the tool's filesystem sandbox.
- The built app was inspected visibly in dark appearance with a temporary Fountain fixture. Its fixed bottom-right control opened the popover, advanced in 10-percentage-point steps, reached 200% with Zoom in disabled, reached 50% with Zoom out disabled, and reset to 100%. Reopening the fixture started at 100%. A final build screenshot showed the screenplay and controls at 110%.
- Physical trackpad event delivery and gesture feel remain unverified. Full manual coverage of narrow windows, light appearance, keyboard operation and scene navigation at scale also remains open. Synthetic events and hidden-window tests do not substitute for those checks.

## Exclusions

- Board gesture fixes or changes to its persisted zoom.
- Zoom for shot lists, character views, sidebars or the whole application window.
- Font-size preference changes or altered PDF pagination.
- Persistent zoom preferences or synchronisation across windows.
- New keyboard zoom shortcuts, smart double-tap zoom or mouse-wheel zoom modifiers.
- Commit, push, installation or release work.

## Unresolved decisions

None. Leo confirmed implementation on 25 November 2026. The control uses the system magnifying-glass icon, a locale-formatted whole-number percentage and viewport-centred zoom for popover actions. Remaining work is the manual validation listed above, not a product decision.
