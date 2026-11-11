# Regression tests

Run the complete deterministic suite on macOS with a Swift 6 toolchain and an available WindowServer session:

```sh
swift test
```

`ActCoreTests` covers parsing, storage, formatting and the local runtime adapter. `ActAppTests` imports the actual app module and hosts native views in hidden windows. It sends no system input, opens no visible windows and does not use the running Act app. Tests own their temporary files and isolated preference suites.

## Coverage

Current suite: 93 core tests and 32 native app tests. The character-sheet validation run passed 123 of 125, with actual MLX extraction enabled and the two older GGUF inference checks skipped. The default command skips all three real-model checks. Native preview rendering runs only when its output directory is configured. [Character-sheet evidence](../docs/specs/screenwriting/character-sheets-validation.md).

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
| Manual action-name marks, comment exclusion, physical evidence, linked traits and stale anchors | CharacterSheetTests |
| Offline MLX arguments, literal prompts, raster validation and subprocess-group cancellation | CharacterSheetTests |
| Native highlight/source/caret/undo preservation, portable libraries, prompts and Save As | CharacterWorkspaceTests |
| Source changes during extraction preserve previous details and edited prompts | CharacterWorkspaceTests |

The tests make assertions against saved bytes, native document state, attributed text and glyph bounds. Live example tests compare renders before and after each style change within the same run, using the actual observed view. They use no stored snapshot goldens or implementation-source comparisons.

## Actual local AI

The two GGUF tests are skipped by default. Enable them explicitly using existing compatible GGUF files:

```sh
ACT_TEST_MODEL=/absolute/path/to/model.gguf swift test --filter GenerationTests
```

The recommended-model check verifies pinned shard sizes/SHA256, reuses valid downloaded shards and may download missing files. It requires about 4.68 GB of model storage and working space:

```sh
ACT_TEST_DOWNLOAD_DIRECTORY="$PWD/.scratch/recommended-model" swift test --filter GenerationTests.testRecommendedModelDownloadAndOfflineInferenceWhenExplicitlyConfigured
```

Both opt-in tests were run against the existing Qwen2.5 7B model during this change. A schema-valid result is not proof of faithful or useful cinematography.

## Character extraction and previews

Actual local MLX extraction can be enabled independently of GGUF tests:

```sh
ACT_TEST_MLX_RUNTIME=/absolute/path/mlx_lm.generate ACT_TEST_MLX_MODEL=/absolute/path/mlx-model swift test --filter CharacterSheetTests.testRealMLXExtractionWhenExplicitlyConfigured
```

To render the actual character workspace in light/dark modes, including a narrow layout and marked editor:

```sh
ACT_TEST_CHARACTER_PREVIEW_DIRECTORY="$PWD/.scratch/character-sheets-preview" swift test --filter CharacterWorkspaceTests.renderActualCharacterWorkspaceWhenRequested
```

Image-agent tests use local fixture subprocesses. Actual external generation and reference-image editing require explicit in-app prompt approval and result inspection for each configured account. Fixture raster output is not evidence of live agent capability.

## Localisation

The default suite checks all seven resource sets for matching keys, compatible format arguments, plural rules and document-type names. Native editor, board and planning tests keep user content, source bytes and persisted identifiers literal.

To verify one language in a fresh test process and render its actual workspaces, settings and PDF preview:

```sh
ACT_TEST_EXPECTED_LANGUAGE=pt-BR ACT_TEST_LOCALISATION_DIRECTORY="$PWD/.scratch/localisation" swift test --filter LocalisationPresentationTests
```

Run separately for `en-GB`, `en-US`, `pt-BR`, `es-ES`, `fr-FR`, `de-DE` and `it-IT`. The harness uses temporary process preferences and restores them; it does not change saved macOS language settings. See [localisation evidence](../docs/specs/localisation/validation.md).

## Manual and untested boundaries

Native crash/relaunch restoration, system input-method composition, OS file dialogs, accessibility/button/menu actions and physical keyboard shortcuts still require desktop checks. Store-level recovery and direct native editor/document APIs are tested independently. Network interruption, checksum mismatch and disk exhaustion during model download are not currently fault-injected. Distribution signing and notarisation remain outside this project phase.
