# Project board

Status: active
Domain: Screenwriting
Owner: Leo
Related ADRs: none
Tickets: [Approved slices](project-board/tickets/01-slice.md), [validation evidence](project-board/validation.md)

## Problem

Act opens individual Fountain documents and their planning views. Writers need a project-level space to arrange drafts, outline ideas and see related character reference sheets and shot lists together.

## Intended behaviour

A project opens on one pannable, zoomable Board tab in the main writing window, alongside Screenplay, Shot list and Characters. Creating or opening a project selects that tab without creating a separate board window. Board saves and undo remain independent of the screenplay; closing the host window protects both documents. Opening a standalone Fountain file continues to open its editor directly. Cards reference existing files without moving them on disk. Each Fountain file represents a draft, not a revision managed by Act.

Users position draft cards, selectively add linked scene cards from a draft outline, and create standalone text notes for beats before scenes exist. Board order never changes screenplay order. Notes do not become Fountain automatically.

Character reference sheets and shot lists belong to a specific draft. Sharing across drafts requires explicit linking. Opening an asset enters its existing editor or planning view. Draft cards show filenames and scene counts; character reference sheets show image thumbnails when available.

Named spatial groups organise cards. Moving a group moves its cards. A local project board file automatically saves layout and references so reopening restores the board. Removing a card removes only its board reference and supports undo. Source files remain intact. Missing files offer relinking. Changed or missing scenes retain their notes and positions and require review; they never silently attach elsewhere.

External changes to a board file require explicit conflict handling. Failed writes must remain visible and must not be presented as saved. Invalid or inaccessible linked assets must preserve the board and offer a recoverable failure.

## Acceptance checks

- [ ] Project files open on the board; standalone Fountain files retain direct editor opening.
- [x] Drafts can be linked and moved visually without moving or modifying their source files.
- [ ] Trackpad pan and zoom permit navigation and accurate card placement at different zoom levels.
- [x] Save/reopen restores cards, layout, groups, notes and draft ownership links.
- [ ] Selected scenes become cards; scene-card order and positions never rewrite Fountain.
- [x] Text notes can be created and edited without an existing scene.
- [ ] Moving a named group moves its contained cards together.
- [ ] Draft cards display filename and scene count; character cards display available thumbnails.
- [ ] Opening cards reaches the corresponding existing editor or planning view.
- [ ] Cross-draft sharing requires an explicit link and preserves provenance.
- [x] Removing cards leaves referenced files intact; undo restores removed cards and their board state.
- [ ] Missing files can be relinked; changed/missing scenes retain notes and positions with a review flag.
- [x] Autosave failure and external board-file conflict preserve unsaved work and never silently overwrite it.
- [ ] Existing writing, shot-list and character-library behaviour remains covered by regression checks.

## Decisions and contracts

The sixteen decisions confirmed in the design discussion define this scope. Existing raw Fountain and sidecar authority remain unchanged. Project state owns visual organisation and references, not duplicate screenplay or planning content. Existing character-library and shot-list files remain authoritative for those assets.

The native Swift product contract remains the existing baseline. This specification does not introduce an implementation-language migration. Project persistence needs a versioned format, stable card identity and recoverable references; version-1 JSON uses `.actboard`, UUID card/group identities and absolute local paths. Missing paths require explicit relinking; project files do not promise portability. Asset sharing records additional draft references while retaining the original owner and editing its original workspace. Group membership uses an explicit menu, not geometric overlap. These implementation choices follow the approved reference-only scope.

No ADR is accepted by this specification. Before settling durable project storage and file-identity tradeoffs, recommend a scoped small-model review of existing native document lifecycle, sidecar contracts and portable-reference options. Delegation requires separate authorisation.

## Test seam

Use the existing ActCore persistence/scene-link tests and ActApp native-document/workspace seam. Extend them through observable project save/reopen, source-byte preservation, undo, relinking and conflicts. Existing prior art includes `DocumentTests`, `ShotListTests`, `OutlineTests`, `NativeDocumentTests`, `ShotWorkspaceTests` and `CharacterWorkspaceTests`.

The agreed delivery checks include save/reopen, undo, relinking, conflict handling and trackpad navigation. Native desktop inspection must additionally demonstrate pan/zoom, dragging, group movement, asset opening and readable previews. Automated state tests alone do not prove physical trackpad interaction.

## Validation

```sh
swift test
scripts/build-app.sh
node .galicia/check.ts
```

Record automated results and actual native interaction evidence before completion. Build success alone is insufficient. No implementation or runtime validation has occurred for this change yet.

## Exclusions

- Creating Fountain drafts from notes or converting beats into screenplay content.
- Connectors and nested boards.
- Automatic reordering or rewriting of screenplay source.
- Moving source files when arranging or removing cards.
- Packaged project portability, pending a separate decision; references alone do not promise portability.
- Release, signing, notarisation or publication.

## Unresolved decisions

- Physical card/group dragging, pinch gestures and crash/relaunch recovery still require successful desktop evidence. CUA screenshot capture failed during drag attempts; no physical gesture pass is claimed.
- Packaged portability remains excluded. Absolute references require relinking after moving linked files.
- No storage ADR or delegated review was authorised or created.

## Implementation evidence

See [validation](project-board/validation.md). Implementation is present; parent remains active until outstanding native acceptance evidence is complete.
