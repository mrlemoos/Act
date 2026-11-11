# Localisation validation

Date: 11 November 2026
Scope: [App localisation](../localisation.md)

## Automated regression

The integrated `swift test` run completed with 164 tests, zero failures and three opt-in real-inference checks skipped. This comprises 66 XCTest tests, 52 ActCore Swift Testing tests and 46 native app Swift Testing tests.

Coverage includes seven-locale resource key and format-argument completeness, plural rules, British fallback, US/British spelling, app language declarations, document-type names, source bytes, paper metadata, native editor accessibility, board persistence and literal planning content. Duplicate character marks and the 16 MB character metadata boundary produce translated app-authored errors.

The real GGUF inference, recommended-model download/inference and local MLX checks remain opt-in. This change preserves their prompts and output contracts; it does not claim another real-model run.

## Native language and layout checks

A fresh test process for each of `en-GB`, `en-US`, `pt-BR`, `es-ES`, `fr-FR`, `de-DE` and `it-IT` applies an app-language preference in a volatile argument domain. The harness restores that domain and never changes the user's saved language settings.

```sh
ACT_TEST_EXPECTED_LANGUAGE=pt-BR ACT_TEST_LOCALISATION_DIRECTORY="$PWD/.scratch/localisation" swift test --filter LocalisationPresentationTests
```

Repeat separately for each locale. Each successful process produces native menu evidence and 13 actual view renders:

- Screenplay, shots, characters and board at 1280 × 900 points in light appearance and 820 × 700 points in dark appearance.
- Writing settings at both sizes, including translated bundled examples alongside literal screenplay content.
- The real shared PDF toolbar at 1280 and 820 points, plus the minimum 580-point width. OCR checks that the translated Paper, Export and Print controls appear in the rendered image and fit within its bounds.

Generated evidence lives in `.scratch/localisation/<locale>/`; process logs are `.scratch/localisation/<locale>.log`. Use `preview-toolbar-*.png` for PDF toolbar evidence. Earlier `preview-desktop-light.png` and `preview-narrow-dark.png` files are invalid, stale captures from the initial hidden PDFKit host and are excluded from this evidence.

Visual review covered all seven languages through workspace contact sheets and full-size checks of longer German/French labels. Italian workspace wording was shortened to “Inquadrature”; Portuguese board terminology and shared menu labels were made consistent. Stored filenames, screenplay examples used as user fixtures and user-authored card titles remain literal.

## Packaged app

```sh
scripts/build-app.sh
/usr/bin/codesign --verify --deep --strict .build/Act.app
node .galicia/check.ts
git diff --check
```

The build packages the SwiftPM ActCore resource bundle and the app's seven InfoPlist translation sets. Native desktop inspection of `.build/Act.app` verified the default English workspace, native menu actions, Settings sidebar, accessible labels and Command-P PDF preview controls. No user screenplay was opened or changed.

## Boundaries

Full PDFKit view capture in a hidden test window produced invalid images. The harness now captures the actual shared toolbar, with the complete preview checked separately in the running app. Full preview desktop inspection used English; toolbar rendering covers all seven locales.

The macOS System Settings language picker itself was not changed during validation. Tests exercise the same per-process AppleLanguages preference mechanism and the app bundle declares all supported languages. Native OS permission/file dialogs and paid external agent actions were not exhaustively replayed in every language. External diagnostics and user/model content remain literal.

The parent specification remains active; completing implementation tickets does not automatically close it. Commit and push are separately authorised delivery steps. Publication and distribution release remain outside this change.
