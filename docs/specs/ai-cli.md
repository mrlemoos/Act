# AI editing and automation

Status: active
Domain: Screenwriting
Owner: Leo Lemos
Related ADRs: [0001. Line-scoped editor styling](../adr/0001-line-scoped-editor-styling.md), [0002. App-owned automation](../adr/0002-app-owned-automation.md).
Tickets: Implementation tracked through the acceptance checks and [validation record](ai-cli/validation.md).

## Problem

Act owns open screenplay documents, native undo and autosave, but exposes no shared automation contract. Editing files independently cannot reliably operate on unsaved writing. Terminal agents and computer-use applications such as ChatGPT Work need precise editing, shot planning and storyboard image workflows. The writer needs to see what an agent changed without losing their place.

## Intended behaviour

### Projects and documents

Automation creates and operates within `~/Documents/Act/{project name}`. Import copies existing screenplays and their linked assets into that project while preserving originals. Projects support multiple screenplays, each with separate shot lists and character libraries. Storyboard images live with project files and use relative asset references with retained versions.

Automation mutations target documents inside this managed project root. An outside document must be imported before automation changes it. This boundary applies to automation; changing ordinary native opening and editing behaviour was not agreed.

A name collision fails with an actionable error and leaves both locations unchanged. The caller supplies a different destination name explicitly. Import never silently merges or overwrites projects. Root checks resolve filesystem paths so a symlink cannot silently redirect a mutation outside the managed project.

Commands discover and explicitly target open documents, including unsaved text. Images require a saved screenplay; asset commands against an unsaved screenplay return a structured save-required result. Other screenplay editing remains available. Existing native autosave and conflict checks still apply. A successful edit reports its persistence state separately from successful mutation.

### Shared commands

A standalone CLI written in TypeScript connects through a local socket to a minimal Swift command service inside Act. The same service backs a keyboard-accessible Automation window with labelled command input and result controls. Computer-use agents can submit operations and inspect results without a terminal.

The app process owns open document state and applies changes. The CLI starts Act when necessary without stealing focus. The command is bundled with Act and installed explicitly; using it does not require a separate Node installation.

Commands expose versioned JSON schemas, document discovery and structured errors. Every mutation supports request IDs for safe retries. Repeating a request returns its previous result without repeating changes. Socket access stays local to the current macOS account; no network listener is introduced.

V1 covers screenplay editing, shot lists, characters and storyboard images. Board automation is deferred. The command catalogue below and the canonical [TypeScript contract](../../CLI/contract.ts) define that coverage.

### Precise edits

Edits support preview and explicit apply without mandatory confirmation dialogues. An apply checks the expected document revision, validates the whole batch, and either applies all changes as one native undo step or applies none. A stale revision fails without modifying the document. Revisions must track native writing and undo/redo as well as automation.

Text edits match exact source within a scene. Missing and ambiguous matches fail. Insertions specify an unambiguous anchor and insertion side. Moves are explicit operations with a source and destination, rather than inferred delete/insert pairs. Fountain source remains authoritative; edits preserve untouched source and its encoding conventions.

CLI edits follow the existing native autosave lifecycle. Results distinguish an applied edit from a confirmed save, including pending or failed persistence.

### Writer feedback

AI changes show inline highlights and clickable +, − and move markers for inserted, edited, removed and moved text. Clicking a marker opens a popover beside the affected text. Accept/Reject applies to that operation, including both halves of a move. The toolbar retains a separate batch-history popup. The popup contains before/after cards and Accept/Reject controls, without opening a side panel or narrowing the screenplay. Accept retains the applied edits and dismisses their highlights. Reject safely reverts a batch; conflicting later writing remains protected. Closing the popup alone makes no decision. Deletions appear as text in review cards with markers at their source locations, rather than adding deleted lines to screenplay layout. Moves have linked origin and destination markers.

This popup presentation supersedes the initially agreed sidebar following Leo's implementation feedback on 22 November 2026, refined to text-anchored marker popovers on 23 November 2026. The command preview/apply contract remains noninteractive; text review does not block IPC.

Feedback persists until dismissed. Incoming edits do not activate the app, steal keyboard focus or scroll the writer to another location. Review navigation happens on demand. Caret and selection positions must track surviving source appropriately.

Review history survives relaunch outside Fountain. Individual changes can be reverted, but a reversion that overlaps subsequent writing stops and shows the conflict instead of overwriting the writer's text. Review history persistence does not promise that native undo survives app termination.

History remains until explicitly cleared. Dismissing highlights does not clear history. No automatic pruning occurs, so project storage may grow. A history record whose saved source lineage cannot be verified remains inspectable, but cannot silently restore text or enable an unsafe reversion. Unsaved documents recover uniquely matching history; ambiguous matches remain archived and inspectable. The first managed save writes active history beside the screenplay.

### Images and generation

Storyboard images link to shot-list entries and can reuse selected character reference sheets. Every successful generation/import retains earlier image versions.

Act supports configured image agents and external generation through exported requests and imported results. For example, ChatGPT Work can read an exported request, generate an image with its own tools and submit the result for attachment. Exporting a request does not itself execute generation.

Act-started image generation requires user approval of the exact prompt and selected references in a popup. Accept starts generation and Reject cancels the pending request. One request is shown at a time, with an immutable displayed payload. Dismissed popups can be reopened from the job list. CLI submission returns an approval-required state without blocking on the popup. Requests contain only reviewed shot details and selected references. Act never automatically sends a whole screenplay.

Generation exposes job identity, status, cancellation and duplicate-request protection. Changed shots or references make outstanding results stale. Generated files remain available, but stale results require review before attachment. Failure and cancellation preserve existing writing and image versions.

An interrupted job or uncertain external outcome is reported explicitly. It is never automatically resubmitted. Retrying is an explicit operation; if it starts a new external request, that request follows the same approval requirements. Cancellation does not promise that a provider stopped work or that a charge was avoided.

## Acceptance checks

Leo approved this scope, command coverage, defaults and the native/CLI test seam before implementation. Checkmarks require evidence in the [validation record](ai-cli/validation.md).

- [x] Create/import a managed project containing two screenplays. Originals remain unchanged, linked assets are copied, and each screenplay retains separate planning metadata.
- [x] Outside-root mutation fails explicitly. An unsaved document can be edited, while image operations return save-required.
- [x] Discover a document, inspect its unsaved source and submit the same operation through both CLI and Automation window with equivalent results.
- [x] CLI output is valid versioned JSON with stable structured errors and explicit persistence status. Diagnostics do not corrupt result output.
- [x] Background launch and command handling do not activate the app, steal focus or scroll the writer away from their current position.
- [x] Preview is non-mutating. Applying a batch validates its revision and all anchors before changing source, then creates one native undo step.
- [x] Missing/ambiguous text, stale revisions and invalid move destinations leave source unchanged. Repeating a mutation request does not duplicate its effects.
- [x] Native typing and undo/redo invalidate older expected revisions. Save conflicts and autosave failures remain visible in command results.
- [x] Insert, replace, remove and move produce accurate inline markers and review cards. Review navigation is deliberate and works without relying on colour alone.
- [x] Review history remains inspectable after relaunch. A disjoint later edit permits safe reversion; overlapping writing produces a conflict without losing text.
- [x] Dismissing feedback retains review history. History is never automatically pruned, and unverified recovery records cannot overwrite writing.
- [x] Export a shot image request and import an externally supplied raster into the correct shot with version history preserved. Local fixtures establish import behaviour; live paid generation remains unverified.
- [x] An Act-started request cannot execute before approval of its exact payload. Replayed submission executes the approved local provider fixture once.
- [x] Cancelled, failed and stale image jobs preserve prior versions. Stale attachments require review.
- [x] An interrupted or uncertain external outcome never causes automatic resubmission. Explicit retry follows applicable approval requirements.
- [x] Moving a complete project preserves relative image references.
- [x] A machine without separately installed Node can run the bundled CLI after explicit installation.
- [ ] A different macOS account cannot submit commands through the local endpoint.

## Decisions and contracts

The interview accepted decisions 1–35 and the final assembled scope. In particular, the project-root follow-up replaces the initial assumption that assets simply remain beside arbitrary externally located screenplays. They remain alongside the screenplay within its managed project. Leo confirmed the command catalogue, import/recovery defaults and test seam before authorising implementation.

The approved Luna review recommended the implemented per-user Unix-domain socket and shared app-owned Swift dispatcher, with a TypeScript client. This reuses the document ownership, native undo and save-conflict logic in [FountainDocument](../../Sources/Act/FountainDocument.swift), separate planning state in [ShotWorkspace](../../Sources/Act/ShotWorkspace.swift), and existing image-agent handling in [CharacterWorkspaceModel](../../Sources/Act/CharacterWorkspaceModel.swift). Actual process and desktop accessibility checks are recorded in the validation document.

The Swift bridge is an explicitly accepted exception to the general TypeScript preference. It owns native state and validation, rather than duplicating mutable document state in TypeScript. Both entry points obey the same contract.

Existing character request approval and local inference boundaries remain applicable. Automation review records and storyboard images add separate metadata/assets; they are not embedded into Fountain. The [wire contract](../../CLI/contract.ts), [review types](../../Sources/ActCore/Automation.swift) and [native storage types](../../Sources/Act/AutomationService.swift) own their exact schemas.

### Command catalogue

These operation families define v1 coverage. Exact operation names and parameters are discoverable through `act schema` and documented in the [CLI guide](../../CLI/README.md). Every operation is also available through the Automation window; humans use the ordinary editor and review controls for everyday writing.

| Family | Operations and boundary |
|---|---|
| Discovery | Health/version, schema lookup, project listing, open-document listing and current revisions. |
| Projects | Create and import under the managed root. Imports preserve originals and reject destination collisions. No project deletion in v1. |
| Documents | Create, open, inspect and explicitly save managed screenplays. Closing unsaved documents or discarding writing is outside v1 automation. |
| Source | Read current source, scene identities and selected scene text from the app-owned document, including unsaved writing. |
| Edits | Preview and apply exact anchored insert, replace, remove and move operations, with revision and request identity. |
| Reviews | List batches and individual changes, navigate, dismiss visual feedback, inspect persisted history and revert an individual change or batch safely. Clearing history requires an explicit operation. |
| Shots | Read, add, update and remove shot entries; request existing offline local shot-list generation with status and cancellation. Generated replacement of existing shots uses explicit preview/apply semantics. |
| Characters | Read/create characters, mark/link exact name occurrences, update editable metadata/prompts and invoke existing local physical extraction. Existing evidence and stale-anchor rules remain applicable. |
| Image requests | Prepare reviewed payloads for a shot or character, export for external generation, or submit an Act-started request into pending approval. |
| Image results | Validate/import raster results, inspect image versions and select an active version. Verify request identity and input freshness before attachment. |
| Jobs | Inspect job status, cancel, and explicitly retry eligible failed/interrupted jobs. No automatic paid-request retries. |

### Wire and mutation contract

Requests carry a protocol version, request ID, operation and typed parameters. Document mutations explicitly name the document and expected revision. Planning metadata uses its own revision, so an unrelated edit does not needlessly invalidate every operation. Image requests bind the exact selected text, shot details and reference assets used in their approved payload.

Responses identify their request and operation, report the resulting revision and persistence state, and contain either a typed result or structured error. Stable error categories include unsupported version, invalid parameters, unknown document, outside project root, save required, revision conflict, missing/ambiguous anchor, approval required, stale result, cancelled and uncertain outcome. Results go to stdout; diagnostics go to stderr. The Automation window exposes the same fields in readable, accessible controls.

Preview returns the proposed changes and a preview identity. Apply names that preview and its expected revision, making the reviewed edit reproducible without an interactive confirmation dialogue. Reusing a request ID with different parameters is an error. Native writing that occurs between preview and apply invalidates that preview.

Within a batch, anchors resolve against the same original revision. Overlapping changes, incompatible insertion positions and moves into their own source ranges fail before mutation. No command silently chooses the first of multiple exact matches. Reversion is a new validated edit with its own undo step; it does not rewind unrelated native undo history.

Application support contains version-1 `state.json`, with request fingerprints, pending/completed receipts and durable job records. A pending receipt after interruption reports uncertainty rather than repeating a mutation. Saved review ledgers use version-1 `<screenplay>.ai-review.json`; unsaved ledgers remain in `UnsavedReviews` under the automation support directory. Storyboard `versions.json` is a version-1 object containing image version records and relative asset paths. Unknown storage versions fail without overwriting existing assets.

A crash must not be reported as a proven successful or failed mutation without evidence. If recovery cannot establish the outcome, report uncertainty and require reconciliation instead of blindly repeating the change. Normal app quit cancels automation tasks and retains uncertain external outcomes.

## Test seam

The approved highest useful seam is the actual bundled CLI connected to an isolated running Act instance, combined with native tests against real document and editor objects. The Automation window is also exercised through its actual accessibility controls. Shared command-service tests cover operation semantics, while process-level journeys prove transport, output and lifecycle behaviour that mocks cannot establish.

Use isolated fixture projects and application state, never the writer's real open documents. Prior art includes `ActCoreTests`, `ActAppTests` and the native document/editor checks described in [Tests/README.md](../../Tests/README.md).

Visual acceptance includes a populated screenplay with insertions, deletions and linked moves, deliberate review navigation, no unwanted scrolling, and overlapping later writing. Cover keyboard access, accessible labels, non-colour distinctions and reduced motion. Incoming changes use no unsolicited animation.

Real external import can use an existing raster fixture. A live paid provider test remains separately authorised and must not be implied by mocked subprocess tests.

## Validation

Existing checks:

```sh
swift test
scripts/build-app.sh
node .galicia/check.ts
bun CLI/contract.ts --check
bun test CLI/src
bun CLI/integration.ts
```

Run strict TypeScript checking through `bun run typecheck` in `CLI`. Local implementation has passed automated checks, actual CLI/app integration, native visual/AX checks and standalone packaging. Paid-provider behaviour remains explicitly unverified. The remaining separate-account check keeps this specification active.

## Exclusions

- Board automation in v1.
- Remote/network automation endpoints.
- Direct CLI writes that bypass open-document ownership and native conflict handling.
- Unapproved Act-started external image requests or automatic whole-screenplay transmission.
- Silent modification of imported originals.
- Unauthorised paid-provider tests, distribution, deployment, commits or pushes.

## Unresolved decisions

- No unresolved product decisions. Leo confirmed the assembled scope and authorised implementation.
- Separate-account denial and a distinct macOS 15 runtime remain untested. Current-machine launch, socket authentication, endpoint recovery and standalone Bun packaging are verified locally.
- Actual paid image-provider capabilities remain account-specific and require the existing explicit capability tests and payload approval.
- The app-owned boundary is recorded in ADR 0002. Evidence and remaining platform/account limits are tracked in the validation record.
