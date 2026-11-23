# Automation validation

Local implementation is delivered. This record distinguishes fixture tests, actual app-process behaviour and paid-provider evidence. Validation date: 23 November 2026.

## Automated checks

- `bun CLI/contract.ts --check`: passed. Generated native schema matches its TypeScript owner.
- `bun run typecheck` in `CLI`: passed with strict TypeScript checking and unchecked-index checking enabled.
- `bun test CLI/src`: four passed. Literal arguments, invalid options, fragmented socket responses and lost-response uncertainty.
- `swift test --no-parallel`: 71 XCTest cases with three opt-in model checks skipped, 55 ActCore Swift Testing cases, and 87 native Swift Testing cases; no failures. This is 210 passing cases plus three skips.
- The native automation suite contains 16 cases covering exact edits, atomic failures, independent undo/redo groups, review-state restoration, stale revisions, safe reversions, popup acceptance/rejection, persisted history, first-save/unsaved recovery, import boundaries, raster version history and compiled CLI interoperability.
- A configured local executable fixture proves that submission does not execute before approval, that approval imports a validated result, and that request replay executes the fixture once. This is not a paid-provider capability test.
- Existing parser, native typing, editor styling, storage, PDF, localisation and planning regressions passed alongside automation checks. All seven interface resources include Automation copy and pass matching-key/format checks.
- `zsh scripts/build-app.sh`: passed, producing `.build/Act.app` and its standalone CLI at `Contents/Helpers/act`. The separate directory avoids a case-insensitive collision with the native `Contents/MacOS/Act` executable.

## Native previews

Generate actual native views from isolated fixtures:

```sh
ACT_TEST_AUTOMATION_PREVIEW_DIRECTORY="$PWD/.scratch/ai-cli-preview" swift test --filter AutomationTests
```

The fixture includes replacements, deletion markers and paired move records. Light, dark, narrow, popup and Automation-window renders are separate images under `.scratch/ai-cli-preview`. The popup revision leaves the editor full width and adds explicit Accept/Reject controls. These are layout evidence; paid image generation has not been tested.

An isolated desktop bundle was also operated through actual accessibility controls. Its Automation request field accepted a JSON request through AX setValue; Submit command returned structured success. A reviewed replacement was applied through that UI, its changed source appeared in the real document, and the Review AI changes control exposed before/after cards. The original sidebar prototype was verified this way, then superseded by Leo's request for popup acceptance/rejection. The fixture was explicitly saved afterward. Record: `.scratch/ai-cli-desktop/validation.json`. Preview bundles use their own bundle IDs, project root and endpoints; installed app files and the writer's real documents were not changed.

The rebuilt popup revision was separately opened as an isolated native app. Its Review AI changes action presented an AX dialogue titled AI changes, with labelled Accept/Reject buttons and the exact before/after text. The editor remained a normal full-width document rather than opening a review side panel. Acceptance/rejection source effects are covered by the native regression case. `image-approval-popup.png` renders the real image-prompt component using a description fixture; it invokes no provider.

The marker interaction was refined on 23 November 2026. Clicking the native + button through accessibility opened an NSPopover beside the changed line, exposing the exact previous/current text and Accept/Reject buttons. Its height follows the content, capped for scrolling. Native tests cover both + and − activation, unchanged caret/scroll and decisions scoped to one operation. Linked move records share that operation. Multiple markers on one line receive separate hit targets. The final focused automation run passed all 16 cases after marker-spacing changes; the preceding full run passed 210 cases plus three opt-in skips. The preview remains open on the sample suggestion.

## Actual process integration

`bun CLI/integration.ts` passed. The bundled executable ran with PATH limited to `/usr/bin:/bin`, launched the actual app with an isolated project root/endpoint, observed `isActive:false`, created a project/screenplay, edited unsaved source, replayed a mutation without duplication, added a shot, exported an image request and explicitly saved. It terminated only its own process, relaunched, reopened the saved source, recovered review history/jobs, reverted the change and saved the restored source. It installed a command into a temporary bin directory and ran that command without separately installed Node or Bun in PATH.

Record: `.scratch/ai-cli-process-validation.json`. Native fixture tests independently prove unchanged caret/scroll/focus during an earlier-text edit.

## External generation

Raster import tests use a locally generated fixture. No paid agent has been invoked by this change. Existing per-account capability verification and exact-payload approval remain required.

## Remaining boundaries

- Actual paid accounts, provider billing, and successful live generation/editing for every supported agent remain unverified. The app requires their existing capability tests and per-request approval.
- Unix socket creation uses a private account-owned directory, a mode-0600 socket and `getpeereid` account checks. Same-account acceptance was verified. A second-user denial test was not performed; no account was created or impersonated.
- The app builds for macOS 15, but native OS checks ran on the current machine rather than a separate macOS 15 installation.
- Native crash/relaunch restoration remains subject to the existing platform-level recovery limits. Review-source matching and uncertain receipt/job recovery are independently covered.
- No repository commit, push, installed-app replacement, notarised release or production deployment was performed.
