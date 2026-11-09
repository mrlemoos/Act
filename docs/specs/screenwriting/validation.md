# Act v1 validation

Date: 2026-11-09
Build: local development app, macOS 15 minimum, Swift 6
Host: Apple M5 Pro, 48 GB memory, macOS 27.0

## Automated evidence

The initial v1 integrated run passed all 41 tests with no failures or skips: 22 XCTest cases and 19 Swift Testing cases. Both opt-in real-model checks were enabled.

```sh
ACT_TEST_MODEL="$PWD/.scratch/recommended-model/qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf" ACT_TEST_DOWNLOAD_DIRECTORY="$PWD/.scratch/recommended-model" swift test
scripts/build-app.sh
node .galicia/check.ts
```

The default test command does not download models and skips the two opt-in inference/download checks when their environment variables are absent.

Coverage includes byte-preserving UTF-8 Fountain documents, changed/missing backing files, UTF-16 element ranges, scene identities, hidden comments, Unicode PDF text, page bounds, dual dialogue, title overflow, separate shot JSON, stale/missing scene links, transactional replacement, recovery metadata, first-save/rename migration, unique untitled matching, failed recovery writes, structured model output and subprocess cancellation.

## Actual local inference

The production downloader fetched the official Qwen2.5 7B Instruct Q4_K_M model into `.scratch/recommended-model`. Both pinned artifact lengths and SHA256 values passed. Total model size is 4,683,073,632 bytes. The initial download-plus-generation test passed in 86.158 seconds. Subsequent explicit checks verified/reused those artifacts.

The production Swift adapter generated three complete scene-linked shots through the installed llama.cpp Metal runtime with `--offline`. A smaller official 0.5B model also proved the adapter path earlier. Raw recommended-model evidence is `.scratch/generation/recommended-test.log`. Generation is an editable suggestion: one 7B shot invented a door opening beyond the supplied action. This is not a claim of faithful coverage across arbitrary scripts.

## Native app observations

- App launched from `.build/Act.app`.
- Fountain file picker accepted and opened `Examples/FirstLight.fountain`, including when another editor registered a competing Fountain UTI.
- Native Courier formatting and scene outline population were inspected.
- Paste, document undo and redo worked.
- Synthetic screenplay save wrote the expected source bytes.
- Shot fields could be edited, survived workspace switching and saved separately as JSON.
- Corrected File menu exposed enabled Save/Close actions.
- Representative PDF title and body were visually inspected.

Synthetic save evidence is preserved in `.scratch/ui-checks/`.

## Compact interface revision

Following Leo's request to reduce screen information, the default editor hides the outline, removes branding/counters/footer/helper copy, and moves Source/PDF into a toolbar menu. Shot planning uses one scene/action bar, hides secondary file/setup controls in a menu and collapses camera/rationale under Details.

The actual current WorkspaceView and native NSTextView were rendered offscreen and visually inspected in `.scratch/compact-preview/screenplay.png`. This is a code-rendered preview, not a live desktop screenshot. The preview harness lives only in `.scratch/compact-preview` and did not show a window or generate system input.

## Remaining native checks

- Crash/relaunch recovery of named and untitled screenplays and shot lists.
- First save and rename recovery migration through the actual native document UI.
- Live external-file conflict, reload and save-copy interactions.
- Final compact Source, navigation, Details, keyboard focus and menu interactions.
- Download/generate/cancel/retry interaction through the actual compact UI.
- Dark appearance, minimum window width and accessibility review of the final interface.

Computer-use transport failed during native checks: inventory reported `Sky Computer Use native pipe closed before response` and `The browser access host is unavailable`. Read-only process sampling found Act's main thread waiting in NSApplication.run across 869 samples, with no close deadlock. Earlier successful native observations remain distinct from offscreen preview and unit-test evidence.

## Delivery boundary

`.build/Act.app` is locally ad-hoc signed. No publication or notarisation was performed. Restart any already-running Act process before reviewing the rebuilt bundle. The parent specification remains active; tickets 03, 04 and 08 retain the outstanding native checks.

## Outline, settings and heading colours follow-up

The follow-up suite passed 56 tests, with the two unchanged opt-in AI checks skipped. Twelve PDF tests passed again after the final long-cue pagination adjustment. New coverage includes outline synopsis ownership/navigation, preference persistence and invalid values, repeated character cues, font-dependent wrapping, exact heading spacing/weight and ordinary/dual page continuations.

Actual current native views were rendered offscreen and inspected in `.scratch/outline-settings-preview/`: `settings.png`, `editor-settings.png`, `outline.png` and `outline-dark.png`. The editor preview demonstrates Menlo 14, regular sluglines, one blank line and a generated CONT'D. The outline previews show pink first-level, blue second-level and orange third-level section headings in editor and outline, in light and dark appearance. A seven-page PDF was visually inspected with Menlo 14, regular headings and continuation cues. These are offscreen/native rendering checks, not desktop interaction proof.

Settings opens through Act > Settings, Command-comma and the existing toolbar menu. Preferences affect editor/PDF presentation only. Raw Fountain remains unchanged, including explicit CONT'D and whitespace. Live Settings interaction remains a manual desktop check; no already-running Act process was terminated or restarted during this change.

## Right settings sidebar follow-up

The app rebuilt successfully after moving settings into the active document's trailing sidebar. Same-hosting-view offscreen checks verified live Courier-to-Menlo, size, slugline weight/spacing and CONT'D changes in both the editor and sample. Narrow 820-point layout and closing the sidebar were visually inspected. The harness asserts unchanged source and cleans up only its isolated preferences suite. Images are in `.scratch/settings-sidebar-preview/`. No separate settings window remains. This revision did not change core algorithms; no redundant unit-test rerun was performed.

## Return spacing follow-up

Seven focused FountainEditingTests passed for context detection, pending character cues, dialogue boundaries, Unicode selections, malformed selections and line endings. Seven offscreen native editor cases also passed: actual delegate insertion updated text and document source, moved the caret correctly and reverted with one undo. The integration harness is `.scratch/return-check/check.sh`; it created no visible windows and did not interact with live documents. Modified Return and IME commands remain delegated to native behaviour.

## Curly apostrophe follow-up

The app rebuilt successfully. Eight offscreen native typing cases passed for apostrophe conversion, contractions/possessives, accented text, selection replacement, source mode, literal loading/paste, double quotes and existing curly apostrophes. Each case verified document source, single-step undo and redo. The harness is `.scratch/apostrophe-check/check.sh`. It did not show windows or generate system input.

## Persistent regression-suite follow-up

The final complete package test run passed 105 tests with zero failures or skips: 79 core cases and 26 native app cases. Both real-model checks ran against the existing verified Qwen2.5 7B shards. The default command leaves those two expensive checks opt-in. Forty persistent tests were added beyond the previous 65 core cases.

Native tests cover actual Return and apostrophe insertion, selection/caret behaviour, undo/redo, source mode, UTF-8 BOM preservation, successful safe saves, refreshed conflict baselines, external edits and deleted backing files. Presentation tests cover the selected font, system semibold/coloured section headings, exact spacing behaviour with surplus raw whitespace, continuation annotations, synopsis caret navigation, sidebar reflow and live examples. The observed example component is rendered in memory before/after each setting change; no cross-machine screenshot goldens are stored. Preference tests use isolated suites. Shot workspace tests preserve manual work through busy guards and runtime failures.

The core expansion covers malformed settings and output, trusted scene IDs, Unicode/CRLF boundaries, large fonts/long cues, explicit continuation semantics and safe shot replacement/writes. Generation cancellation waits for a fixture-start marker before cancelling and requires it to stop promptly. The real model check accepts the actual one-to-four shot contract rather than assuming narrative quality or an exact count.

Hidden SwiftUI hosting windows did not expose accessibility nodes in this test environment. Physical menu/button/keyboard actions, assistive-technology integration, OS crash/relaunch restoration and download fault injection remain explicit manual or future integration boundaries. See [test coverage](../../../Tests/README.md). The parent specification remains active.
