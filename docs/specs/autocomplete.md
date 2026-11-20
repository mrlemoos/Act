# Character, slugline and transition autocomplete

Status: draft
Domain: Screenwriting
Owner: Leo
Related ADRs: none
Tickets: none

## Problem

The formatted editor already classifies Fountain cues, scene headings and transitions, but the writer still types every name, location, time of day and transition in full. Competitors offer inline completions for these repeating elements. Without them, Act is slower for everyday drafting and more prone to inconsistent spelling of the same character or slugline.

## Intended behaviour

Autocomplete offers completions only for character cues, scene headings and transitions while the writer types in the screenplay editor. It applies in formatted view and in source mode. Suggestions insert into the authoritative Fountain source as ordinary typed text. They never rewrite other lines, normalise whitespace, or alter shot lists, character libraries or the project board.

### When the list appears

The list may open only on a line that could become one of those three element kinds, using the same classification rules as `FountainParser`, including the existing probe-text pattern in `FountainEditing` so an unfinished cue can be recognised without writing the probe into the document.

A line is eligible when the preceding visible line is blank (or the caret is at the start of the screenplay body) and the caret sits on that line with a collapsed selection, or a selection confined to that line. Forced prefixes remain eligible on that same line: `@` for a character, `.` for a scene heading, and `>` for a transition.

The list does not appear in the title page, inside notes or boneyard, in dialogue or parentheticals, or on a non-blank action line. It stays closed during IME composition (`hasMarkedText()`). It opens once the current line has at least one typable character, or immediately after a forced prefix, and only if at least one candidate matches. If filtering leaves no matches, the list dismisses and typing continues normally.

### Characters

Primary candidates are the unique speaking-cue names already present in the current screenplay, taken from elements of kind `character`. Use `FountainParser.displayText`, which strips a leading `@` and a trailing dual-dialogue `^`. The name is the text before the first `(`, matching `isCharacter`. Unicode letters are kept as written, for example `ÉVA`.

Names from the current screenplay's character library (action marks) are a secondary source, and only when the writer is already typing the name in uppercase. The completable name span, excluding a leading `@` and any parenthetical extension, must contain at least one letter, and every letter in that span must be uppercase under the same Unicode rules as `isCharacter` (`name == name.uppercased()`). In that situation the line can become a character cue above dialogue that has not yet been written. Library names are not offered when the prefix is mixed-case or lowercase, including after `@`. Accepting a library name inserts it in uppercase, so a mark stored as `Orleans` becomes `ORLEANS`. If the same character already exists as a speaking cue, the cue spelling is used and the library name is not listed separately.

When the line is a name, optionally followed by `(` or a partial extension, also offer character extensions. The built-in set is `(V.O.)`, `(O.S.)` and `(O.C.)`, plus any other extensions already used on cues in this screenplay, except `(CONT'D)`. `(CONT'D)` is never offered as a completion: not as a built-in, not harvested from explicit source cues, and not because Settings has automatic dialogue continuations enabled. `ScreenplayPresentation.characterCues` may still draw that suffix as presentation-only text. Filter any extension that matches the existing continuation pattern, including straight and curly apostrophes (`\(\s*CONT\s*['’]?\s*D\s*\)`). Accepting an allowed extension completes `NAME (V.O.)` as source text.

### Scene headings

Offer the prefixes the parser already treats as scene headings: `INT.`, `EXT.`, `EST.`, `INT./EXT.`, `INT/EXT.` and `I/E.`, including the space-after-token forms such as `INT ROOM`. These prefixes stay in English in every locale, as they do in Act's bundled writing examples and in `FountainParser`.

Also offer complete headings, locations and times of day harvested from existing `sceneHeading` elements in this screenplay. The parser does not split a heading into parts; the suggestion engine may split display text on ` - ` only as a writing convention for location and time candidates.

Ship a built-in time-of-day list, localised to the app interface language. Act has no per-document language field. Use `L10n.language`, resolved from macOS preferred languages through `L10n.resolvedLanguage`, with fallback `en-GB`, as in [App localisation](localisation.md). There is no in-app language picker; a language change takes effect on relaunch, like the rest of the interface. Store the built-in terms as app-authored localisable strings. Once a term is accepted it becomes literal Fountain and does not change if the app language later changes. Times already used in the screenplay are always offered, in the form the writer typed, regardless of app language, and they rank above unused built-in terms.

The English source list, used for en-GB and en-US, is DAY, NIGHT, DAWN, DUSK, MORNING, EVENING, LATER, CONTINUOUS and SAME. The table below is the shipped list for each supported locale. Terms marked "for review" are omitted until confirmed; do not invent a substitute.

| Locale | Shipped built-in times of day | For review, not shipped |
|---|---|---|
| en-GB, en-US | DAY, NIGHT, DAWN, DUSK, MORNING, EVENING, LATER, CONTINUOUS, SAME | None. |
| es-ES | DÍA, NOCHE, AMANECER, ATARDECER, MAÑANA, MÁS TARDE, CONTINUO | EVENING (no single conventional equivalent distinct from TARDE or ATARDECER); SAME (for example MISMO MOMENTO, unconfirmed). |
| pt-BR | DIA, NOITE, AMANHECER, ENTARDECER, MANHÃ, MAIS TARDE, CONTÍNUO | EVENING (unconfirmed); ENTARDECER versus CREPÚSCULO for DUSK; CONTÍNUO versus CONTÍNUA; SAME (Scripta uses MESMO INSTANTE, unconfirmed as the usual heading form). |
| fr-FR | JOUR, NUIT, AUBE, CRÉPUSCULE, MATIN, SOIR, PLUS TARD, CONTINU, MÊME MOMENT | None of the core list. PEU APRÈS and AU MÊME MOMENT appear in some French guides as extras, not shipped here. |
| de-DE | TAG, NACHT, MORGENGRAUEN, ABENDDÄMMERUNG, MORGEN, ABEND, SPÄTER, DURCHGEHEND, GLEICHZEITIG | MORGENGRAUEN versus MORGENDÄMMERUNG for DAWN; DURCHGEHEND versus FORTLAUFEND for CONTINUOUS; MORGEN versus MORGENS or VORMITTAG. |
| it-IT | GIORNO, NOTTE, ALBA, CREPUSCOLO, MATTINA, SERA, PIÙ TARDI, CONTINUO | CREPUSCOLO versus TRAMONTO for DUSK; SAME (no conventional heading form confirmed). |

Forced headings that begin with `.` are included through display text, which strips the leading dot. Completing a heading must not add, remove or rewrite a trailing `#n#` scene number on the current line. Writer-controlled scene numbers remain a separate change.

### Transitions

Offer transitions already used in this screenplay, using display text (which strips a leading `>`), together with a small built-in set whose unforced form the parser would classify as a transition: a preceding blank line, uppercase text, and a `TO:` suffix, for example `CUT TO:`, `DISSOLVE TO:`, `BACK TO:`, `SMASH CUT TO:` and `MATCH CUT TO:`. Forms that need a forced `>` prefix to classify as a transition, such as `FADE OUT.`, are inserted with that prefix unless the current line already has one.

### Ranking

Only the list for the current context is shown. Rank case-insensitive prefix matches on the current completable span ahead of substring matches. For times of day, values already used in this screenplay rank above unused built-in terms. Then rank by frequency in this screenplay, then by most recent use, then alphabetically. Built-in items that already occur in the document appear once. The visible list stays short.

### Keyboard and insertion

Up and down move the highlight. Tab or Return accepts the highlighted item. Escape, or a click outside the list, dismisses it and leaves the source unchanged. A click on an item accepts it. While the list is visible, Return does not run `FountainEditing.returnInsertion`. Modified Return commands remain native. IME composition is not intercepted.

Acceptance replaces only the current line's completable span (the typable prefix of the cue, heading or transition, including a forced `@`, `.` or `>` already typed). The rest of the document, the line ending, and any existing `#n#` suffix on that line are left intact. The caret is left at the end of the inserted text, or immediately before a preserved scene-number suffix. The insertion is one document undo step, through the existing document undo manager rather than the text view's own undo. The inserted bytes are literal Fountain, including any accents in a localised time of day; the editor must not then rewrite them.

## Acceptance checks

- [ ] After a blank line, typing a prefix of an existing cue, heading or transition shows a ranked list in both formatted and source modes.
- [ ] Forced `@`, `.` and `>` prefixes, unfinished cues (classified only with probe text), Unicode names and mixed-case extensions such as `(V.O.)` complete correctly.
- [ ] Built-in scene-heading prefixes and harvested locations and times of day can be accepted; an existing `#n#` suffix on the line is preserved.
- [ ] Built-in and harvested transitions insert text that the current parser classifies as a transition.
- [ ] Character-library names appear only when the current name prefix is uppercase; mixed-case or lowercase typing does not offer them; accepting a library name inserts it in uppercase and can classify as a cue above as-yet-unwritten dialogue.
- [ ] Built-in times of day follow the app locale for all seven supported locales, with en-GB fallback; times already used in the screenplay are offered in the writer's form, in every locale, and rank above unused built-in terms; accepting a term does not rewrite it if the app language later changes.
- [ ] `(CONT'D)` never appears as a completion, including when an explicit source continuation already exists or automatic presentation continuations are enabled.
- [ ] Tab or Return accepts the highlighted completion as one undo step; Escape dismisses; IME and modified Return are untouched; with the list closed, Return spacing is unchanged.
- [ ] Title page, notes, boneyard, dialogue, parentheticals and mid-action lines show no list. Probe text is never written to the document.
- [ ] Completing a suggestion does not normalise, reorder or otherwise rewrite any other Fountain source, and does not modify shot lists, character libraries or the project board.
- [ ] Relevant automated checks pass; native keyboard and list presentation are recorded as evidence.

## Decisions and contracts

Raw Fountain remains authoritative, as in [Act screenwriting v1](screenwriting/spec.md) and `docs/Language.md`. Autocomplete is a typing aid, not a formatter. Classification must stay aligned with `FountainParser` (`FountainElement.Kind` of `character`, `sceneHeading` and `transition`, including `isCharacter`, `isSceneHeading`, and the `>` / uppercase-`TO:` transition rules). Unfinished cues use the same probe approach as `FountainEditing.returnInsertion`; probe text is never stored.

Insertion uses the existing native editor path (`ScreenplayTextView` / document `replaceSource` and the document undo manager), so caret, selection replacement, UTF-16 ranges, local line endings and one-step undo stay consistent with Return spacing and curly apostrophes. The text view already disables its own undo and intercepts `insertNewline`; the completion list must participate in that command path rather than bypass it.

Suggestion data comes from the current document's parse, the same `parsedScreenplay` already used to format the editor, plus the current screenplay's character library when the uppercase rule above is met, and the localised built-in heading and transition lists. This specification does not change parser rules, presentation continuations, or Settings. Locale resolution follows the existing `L10n` contract; document content remains literal.

Agreed on 20 November 2026: library names are a secondary source only while typing uppercase; built-in times of day are localised to the app language; `(CONT'D)` is never offered as a completion.

No ADR is accepted by this draft. A durable tradeoff would arise only if completions were later sourced from other drafts or from a shared project index; that is out of scope here.

Recommend [breakdown](../../.galicia/templates/ticket.md) into two slices if implementation proceeds: an ActCore suggestion engine (context, candidates, ranking and replacement range) with unit tests, then native list presentation and keyboard behaviour in the editor. Each slice should be independently verifiable. Do not create tickets until authorised.

## Test seam

Highest useful seam for ranking, eligibility, locale lists, uppercase library gating and insertion text is a new ActCore API tested in isolation, following `FountainEditing` and `FountainParser`. Prior art: `FountainTests`, `FountainEditingTests`, `ScreenplayPresentationTests` and the existing localisation resource checks.

Highest useful seam for keyboard, undo, source mode, IME non-interception, line endings and byte-for-byte source preservation is the existing `TestEditorHost` / `NativeEditorTests` AppKit harness. Automated state tests do not by themselves prove the on-screen list, so a short native inspection record is still required before completion.

## Validation

```sh
swift test
scripts/build-app.sh
node .galicia/check.ts
```

Record unit results for context, ranking, locale lists, library gating and replacement ranges, plus native evidence for accept, dismiss, undo and Return-spacing coexistence. Build success alone is insufficient. No implementation or runtime validation has occurred for this change yet.

## Exclusions

- Autocomplete for action, dialogue, parentheticals, title-page fields, sections, synopses, notes or boneyard.
- AI prose rewriting, cloud lookup, or suggestions from other documents or project-board drafts.
- Offering `(CONT'D)` as a completion, or writing presentation-only `(CONT'D)` into Fountain.
- Inserting, locking or renumbering `#n#` scene numbers.
- Changing `FountainParser` classification rules or `ScreenplayPresentation` continuation drawing.
- A per-document language, an in-app language picker, or rewriting inserted times of day when the app language changes.
- Localising `INT.` / `EXT.` prefixes.
- Real-time co-writing and collaboration.

## Unresolved decisions

- Final wording of the built-in time-of-day terms marked "for review" in the locale table. Owner: Leo. Does not block the suggestion engine, eligibility, ranking contract, or the already-shipped terms.