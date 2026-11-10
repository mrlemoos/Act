# Act screenwriting v1

Status: active
Domain: Screenwriting
Owner: Leo
Related ADRs: none
Tickets: see below

## Problem

This repository has no screenwriting application. Leo needs a macOS-only Swift app for Fountain writing and local Apple Silicon shot planning, with a cohesive writing experience inspired by Slugline 2.

## Intended behaviour

Keep the writing screen quiet: hide the scene outline by default, omit branding, counters and status footers, and put secondary actions in menus. Shot rows show framing and action, with movement and rationale behind Details. Open, edit and save Fountain directly. Use Courier, formatted screenplay text with fading syntax, optional source view and scene navigation. Export paginated PDFs. Protect work with autosave, undo, recovery and explicit external-file conflicts. After explicit model download, generate shots entirely offline, without cloud fallback. Store editable shot lists separately, linked to scenes. Generation supports cancellation, retry and visible failures without changing screenplay text.

## Acceptance checks

- [ ] Fountain open/save preserves source content and Unicode.
- [ ] Formatted editing and scene navigation preserve caret and undo behaviour.
- [ ] Autosave, recovery and external changes do not silently lose writing.
- [ ] Courier PDFs paginate representative scripts without clipped text.
- [ ] Local generation produces validated shots, supports cancellation and has no cloud fallback.
- [ ] Editable shot lists persist separately and flag stale or missing scenes.
- [ ] Actual app UI and supported offline inference are verified, with limitations recorded.

## Decisions and contracts

Swift overrides the repository's general TypeScript preference for this product. macOS only. Source Fountain is authoritative. Never normalise raw source during parsing. Shot fields are framing, action, camera movement and rationale. Runtime/model selection requires evidence and may remain unresolved during independent writing work. Native SwiftUI/AppKit implementation is the initial integration direction. No proprietary font copying. Courier first; custom font deferred.

## Test seam

Swift package unit tests cover parsing, persistence, generation contracts and PDF layout. Native app inspection covers editor selection, document lifecycle and interactions. Actual downloaded-model inference is separate evidence from mocked tests.

## Validation

```sh
swift build
swift test
node .galicia/check.ts
```

Completion requires recorded behavioural checks and an app bundle. Building alone does not prove UI or offline model operation.

## Exclusions

- Custom font, collaboration and AI prose rewriting.
- Cloud inference, signing, notarisation and publication.

The approved [character reference sheets](character-sheets.md) follow-up permits explicit external image-agent requests. This does not change offline shot generation or authorise cloud character extraction.

## Unresolved decisions

- Local runtime and model, implementation team, blocks actual inference only.
- Minimum macOS version, implementation team, check runtime compatibility before finalising packaging.

## Tickets

- [01. Open and save screenplays](tickets/01-open-save.md)
- [02. Interpret Fountain scenes](tickets/02-fountain-scenes.md)
- [03. Write in formatted screenplay view](tickets/03-formatted-editor.md)
- [04. Protect writing](tickets/04-protect-writing.md)
- [05. Export screenplay PDFs](tickets/05-pdf-export.md)
- [06. Generate shots locally](tickets/06-local-shots.md)
- [07. Edit scene-linked shot lists](tickets/07-shot-documents.md)
- [08. Integrate and verify release](tickets/08-integration.md)

## Outline and presentation settings

Follow-up request: [09. Outline bodies and screenplay settings](tickets/09-outline-settings.md). Fountain `=` synopsis bodies appear below their scene or section in the optional outline. App-wide saved settings control font family/size, one or two blank lines before sluglines, bold sluglines and automatic dialogue continuations. They affect formatted editing and PDFs while source view and saved Fountain remain literal. Settings opens in a collapsible right sidebar with read-only live style examples.

Hashtag section headings use pink, blue and orange for levels one, two and three-or-deeper in formatted editing and the outline. Colours adapt to appearance.

Section heading typography uses the macOS system sans font at semibold weight in both formatted editing and the outline, retaining level colours. Screenplay text continues to use the selected writing font.

[10. Settings sidebar and live examples](tickets/10-settings-sidebar.md) replaces the separate Settings window. The main editor and examples update together; the left outline closes while settings is open.

[11. Context-aware Return spacing](tickets/11-return-spacing.md) makes Return insert two line breaks outside character/dialogue blocks and one inside them, preserving local line endings and native undo.

[12. Automatic curly apostrophes](tickets/12-curly-apostrophes.md) converts single typed apostrophes to U+2019 through native insertion, preserving existing files and multi-character paste.

[13. Persistent regression coverage](tickets/13-regression-suite.md) adds repeatable native app tests alongside the core suite. [Test coverage](../../../Tests/README.md) records verified behaviours and remaining manual boundaries.
