# Regression tests

Run the complete deterministic suite on macOS with a Swift 6 toolchain and an available WindowServer session:

```sh
swift test
```

`ActCoreTests` covers parsing, storage, formatting and the local runtime adapter. `ActAppTests` imports the actual app module and hosts native views in hidden windows. It sends no system input, opens no visible windows and does not use the running Act app. Tests own their temporary files and isolated preference suites.

## Coverage

Current suite: 79 core tests and 26 native app tests. The final full run passed all 105 with both real-model checks enabled and no skips. The default command skips those two opt-in checks.

| Behaviour | Evidence |
|---|---|
| Fountain syntax, comments, raw bytes and Unicode ranges | FountainTests, DocumentTests, OutlineTests |
| `=` outline bodies, section ownership and native caret navigation | OutlineTests, PresentationTests |
| Contextual Return, blank dialogue boundaries and local line endings | FountainEditingTests, NativeEditorTests |
| Curly apostrophes, selection replacement, literal paste and source mode | NativeEditorTests |
| Caret placement, undo/redo and UTF-8 byte order markers | NativeEditorTests, NativeDocumentTests |
| Native safe saves, conflict baseline refresh, external changes and deleted files | NativeDocumentTests |
| Font/size, heading weight/spacing and stored settings validation | ScreenplaySettingsTests, WritingPreferencesTests, PresentationTests |
| System sans semibold section headings and pink/blue/orange levels | PresentationTests |
| Right sidebar, live example updates, narrow editor bounds and closing/reflow | PresentationTests |
| Repeated dialogue CONT'D, explicit cues and page continuations | ScreenplayPresentationTests, PDFTests, PresentationTests |
| PDF font fallback, Unicode, title/body bounds, long cues and dual dialogue | PDFTests |
| Separate shot JSON, scene links, stale/missing scenes and transactional replacement | ShotListTests, ShotWorkspaceTests |
| Recovery metadata, first-save/rename migration, unique matching and write failure | ShotRecoveryTests |
| Generation locks, missing setup, asynchronous failure and preserved manual work | ShotWorkspaceTests |
| Local process success/failure/cancellation, trusted scene IDs and malformed output | GenerationTests |

The tests make assertions against saved bytes, native document state, attributed text and glyph bounds. Live example tests compare renders before and after each style change within the same run, using the actual observed view. They use no stored snapshot goldens or implementation-source comparisons.

## Actual local AI

The two real-model tests are skipped by default. Enable them explicitly using existing compatible GGUF files:

```sh
ACT_TEST_MODEL=/absolute/path/to/model.gguf swift test --filter GenerationTests
```

The recommended-model check verifies pinned shard sizes/SHA256, reuses valid downloaded shards and may download missing files. It requires about 4.68 GB of model storage and working space:

```sh
ACT_TEST_DOWNLOAD_DIRECTORY="$PWD/.scratch/recommended-model" swift test --filter GenerationTests.testRecommendedModelDownloadAndOfflineInferenceWhenExplicitlyConfigured
```

Both opt-in tests were run against the existing Qwen2.5 7B model during this change. A schema-valid result is not proof of faithful or useful cinematography.

## Manual and untested boundaries

Native crash/relaunch restoration, system input-method composition, OS file dialogs, accessibility/button/menu actions and physical keyboard shortcuts still require desktop checks. Store-level recovery and direct native editor/document APIs are tested independently. Network interruption, checksum mismatch and disk exhaustion during model download are not currently fault-injected. Distribution signing and notarisation remain outside this project phase.
