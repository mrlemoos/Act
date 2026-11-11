# App localisation

Status: active
Domain: Screenwriting
Owner: Leo
Related ADRs: none
Tickets: [01. Native language selection and menus](localisation/tickets/01-native-language-selection.md), [02. Writing, settings and PDF interface](localisation/tickets/02-writing-interface.md), [03. Shot planning interface](localisation/tickets/03-shot-planning.md), [04. Character interface](localisation/tickets/04-character-interface.md), [05. Project board interface](localisation/tickets/05-project-board.md), [06. Completeness and native verification](localisation/tickets/06-native-verification.md)

## Problem

Act's interface is hard-coded in English. Writers need native macOS app language selection and a consistently translated interface.

## Intended behaviour

Support British English, US English, Brazilian Portuguese, European Spanish, European French, German and Italian. Follow macOS preferred app language settings on launch; language changes require relaunch. Unsupported languages and missing keys fall back to British English. Localise all app-authored interface text, native menus, errors, tooltips, accessibility labels and bundled style examples.

## Acceptance checks

- [x] The packaged app resolves all seven supported locales and British fallback through native language preferences.
- [x] All interface areas, including dynamic statuses and core error descriptions, use translated resources.
- [x] Substitutions, count forms, menus, shortcuts and accessibility labels work in each locale.
- [x] Native layouts remain usable in each locale, including longer translations.
- [x] Changing interface language does not change Fountain, user content, PDF screenplay content, sidecar contracts, prompts or generated output.

## Decisions and contracts

Approved in the rubberduck and breakdown discussion. Locale identifiers: en-GB, en-US, pt-BR, es-ES, fr-FR, de-DE, it-IT. Use system language preferences rather than an in-app selector. Swift follows the existing [native product contract](screenwriting/spec.md). Translate bundled display examples while preserving Fountain control syntax. Existing user-authored names, notes, evidence and other document content are literal. Localise app-authored error wrappers; external diagnostics remain literal. No translation service or inference changes.

New board notes, groups and linked planning cards receive translated default titles at creation. Once stored, those titles remain document content and do not change with the interface language. Display labels for card kinds, physical attribute keys and paper sizes are separate from their persisted identifiers.

## Test seam

Resource completeness and substitution checks plus actual native menus, view rendering, document operations and packaged bundle language resolution. Tests must distinguish app-authored text from stored/generated content.

## Validation

```sh
swift test
scripts/build-app.sh
node .galicia/check.ts
```

See [recorded validation and limits](localisation/validation.md) for the integrated regression run, seven-locale native renders, packaged-app smoke check and remaining manual boundaries. Build success alone does not prove native language selection or absence of clipping.

## Exclusions

- Screenplay translation, generated-output translation and localisation of user documents.
- In-app language picker, live language switching, deployment, publication and automatic commits.

## Unresolved decisions

- None for the approved scope.
