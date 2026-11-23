# Act automation

Act exposes one command service through a standalone TypeScript CLI and the native Automation window. Both operate on live documents, including unsaved source. New source edits have visible review history and native undo.

## Install and discover

Build the app with Swift 6 and Bun installed:

```sh
zsh scripts/build-app.sh
.build/Act.app/Contents/Helpers/act install
```

Installation creates `~/.local/bin/act` as a symlink to the CLI inside that app. An existing different command is never replaced. Add that directory to your shell's PATH yourself, or use the absolute command path. Move the app to its intended location before installing the command. The installed executable needs neither Node nor Bun.

The CLI lives in `Contents/Helpers` because `Act` and `act` collide on standard macOS filesystems. Building requires Bun; runtime does not.

```sh
act help
act schema
act status
act projects list
act documents list
```

All output is JSON. Successful commands exit 0; errors exit 1. `schema` works without launching Act. Other commands connect to Act or launch it in the background. Documents are explicitly addressed by ID; the focused window is never an implicit edit target.

## Managed projects

Automation writes only beneath `~/Documents/Act/{project name}`. Import preserves originals and refuses collisions, including linked assets. Multiple screenplays can occupy one project.

```sh
act projects create --json '{"name":"First Light"}'
act documents import --json '{"project":"First Light","path":"/absolute/path/FirstLight.fountain"}'
```

`projects.import` creates a new project directly from a screenplay and its sidecars. `documents.import` imports another screenplay into an existing project. Its optional `name` parameter selects a new `.fountain` filename. Paths inside JSON must be absolute; shell `~` expansion does not happen inside JSON strings.

## Exact editing

Use `documents.list` or `documents.inspect` to obtain the document ID and source revision. Use `source.read` to read current unsaved source and scene identities. `source.read --json '{"sceneID":"SCENE_ID"}'` reads a selected scene instead of the whole source.

```sh
act source read --document DOCUMENT_ID
act edits preview --document DOCUMENT_ID --revision SOURCE_REVISION --json @edits.json
act edits apply --document DOCUMENT_ID --revision SOURCE_REVISION --json '{"previewID":"PREVIEW_ID"}' --request-id UNIQUE_APPLY_ID
```

An example `edits.json`:

```json
{
  "edits": [
    {
      "kind": "replace",
      "sceneID": "SCENE_ID",
      "match": "A single bulb swings above the table.",
      "text": "A bare bulb swings. Its shadow crosses the table."
    }
  ]
}
```

Supported kinds are `insert`, `replace`, `remove` and `move`. Insertions use `match` as their anchor, with `side` set to `before` or `after`, plus `text`. Moves use `match` for their source and `destinationSceneID`, `destinationAnchor` and `destinationSide` for their destination. Moves preserve the exact supplied source text; include its desired separators in that text. The preview resolves every operation against the same source revision and rejects overlapping or ambiguous edits.

`$document` explicitly scopes matching to the complete document, including title-page metadata. It is also used to populate an empty document with an insert whose `match` is empty. Prefer scene scope for ordinary screenplay work.

Preview returns a preview ID and precise before/after changes, without repeating the entire screenplay. Apply is a separate command and creates one native undo step. A changed revision invalidates the preview even if native undo returned the source to identical text. Discard unused previews with `edits.discard`.

After apply, `persistence` distinguishes `unsaved`, `pending` and `saved`. Native autosave still runs. `documents.save` explicitly saves source through existing conflict checks, regardless of the selected workspace. Its optional `path` first-saves an untitled document to a new managed location. Use import to copy existing screenplays and all their sidecars.

Every new mutation uses a unique request ID. If transport fails after submission, inspect state and retry the same request ID with identical parameters. Do not invent a new ID for an uncertain mutation. Reused IDs with different parameters are refused. After app relaunch, rediscover live document IDs and create a fresh preview; old receipts describe prior outcomes, not a current document handle.

## Review changes

The writer sees additions/replacements in green, removals through orange gutter markers, and linked move origins/destinations in blue. Symbols and labelled review cards provide distinctions beyond colour. Deleted text stays in review cards, preserving screenplay layout.

Click a +, − or move marker to open a popover beside that text, with its before/after text and Accept/Reject controls. Each decision affects that operation, including both halves of a move. Choose **Review AI changes** to inspect all batches in a separate popup. The screenplay stays full width; no review side panel opens. Accept keeps the applied edits and dismisses their highlights. Reject safely reverts the batch and closes its popup; overlapping later writing blocks rejection without overwriting source. Native undo remains available. Closing the popup alone leaves the applied edits and their undecided history intact.

Applying edits does not move the writer's caret, scroll or focus. Review navigation and opening its popup are explicit actions. History remains until explicitly cleared. Reversion of either move marker reverts both halves.

`reviews.list`, `reviews.navigate`, `reviews.dismiss`, `reviews.revert` and `reviews.clear` expose the same review state. Clearing requires `confirm:true`. Native undo remains available; persistent review history does not imply that native undo survives quitting.

Saved review history uses `Draft.ai-review.json`. A source fingerprint mismatch leaves history inspectable but disables unsafe reversions. Preserve an unreadable history file before repairing it; new AI edits refuse to overwrite corrupt history.

Unsaved documents retain review archives in application support. A uniquely matching source fingerprint recovers their history without changing source. Ambiguous matches remain untouched and inspectable through `reviews.archives` or **Review archives** in Automation. The first managed save copies active history alongside the screenplay.

## Shot lists and characters

`shots.list` returns the current shot revision; shot mutations require that revision rather than the source revision. Supported operations include add, update, remove, offline generation and explicit application of generated results. Generation preserves existing shots until `shots.apply` and refuses stale scene results. Configure Local AI in Act first.

`characters.list` returns the character revision. Create characters, mark exact action-name occurrences, link a mark using its `characterID`, edit names/prompts and invoke local physical extraction. Existing marked-paragraph/evidence constraints apply. Configure MLX in Act before extraction. Local inference never falls back to a cloud provider.

## Storyboard and character images

1. Prepare a request using `images.prepare` with a source revision, `targetKind` of `shot` or `character`, `targetID`, and `prompt`.
2. Optionally select reference sheets through `references`, an array of `{characterID, versionID}` pairs. Shot requests append the selected shot's reviewed details to the complete outgoing prompt.
3. Use `images.export` to read the complete request, including its `jobID`, exact prompt and reference paths. An external tool such as ChatGPT Work can generate from this payload and return a local raster file.
4. Import with `images.import`, supplying the job ID and absolute raster path. Valid PNG, JPEG and WebP images are copied into the project; originals are preserved. Existing raster size/dimension limits apply.

For configured terminal providers, `images.submit` queues a prepared request and opens an approval popup in Act. The result state is `approval_required`; CLI submission returns without waiting for a decision. The popup displays the exact prompt and references. Accept starts generation; Reject cancels that pending request. Requests are reviewed individually, and the payload never changes underneath an open approval popup. **Review request** reopens a dismissed popup from the job list. No approval command is exposed through IPC. Existing generation/reference-edit capability checks still apply. Multiple selected references are supplied to the provider as one labelled contact sheet; external request export retains the individual reference paths.

`images.agents` reports the document's configured generation/reference-edit capabilities without invoking an agent.

No screenplay file is attached. Act supplies only the reviewed prompt, shot details and selected images. The external tool's own account permissions and instructions remain its responsibility.

`jobs.list`, `jobs.status` and `jobs.cancel` expose durable job status. Interrupted external work becomes `uncertain_outcome`; no request is automatically resubmitted. `jobs.retry` creates a new eligible image attempt and requires fresh approval for Act-started external work. Retry local jobs using their generate/extract operation and a current workspace revision.

Normal app termination cancels running subprocess tasks and records uncertain external outcomes. Cancellation cannot establish whether a provider already charged for work.

Changed input makes an image result stale. Results remain in the project for review. `images.attach` can attach a retained stale result only with explicit `acknowledgeStale:true`, provided its target still exists. `images.list` and `images.select` expose storyboard versions; the shot workspace includes an image version picker. Character image versions remain in their existing library.

Storyboard assets use `Draft.storyboards/images`, with relative paths in `versions.json`. Retained intermediate results use its `results` directory. Move the complete project to preserve these references. Pending jobs retain their original document locations and are not automatically retargeted after a move.

## Computer-use applications

Open **Act > Automation** or the workspace menu's **Automation** action. The window has labelled request and result controls, a Submit command button, discovery shortcuts and a job list. Accept/reject approvals use separate popups. JSON field names, identifiers, prompts and screenplay text remain literal in every interface language.

To submit a raw envelope through the window or stdin:

```json
{
  "version": 1,
  "requestID": "a-new-unique-request-id",
  "operation": "documents.list",
  "parameters": {}
}
```

For source mutations, add `documentID` and `expectedRevision`. For shot/character mutations, use the corresponding workspace revision. A terminal agent can use `act call --stdin < request.json` to submit the identical envelope.

## Development and validation

```sh
cd CLI
bun install --frozen-lockfile
bun run typecheck
bun test
cd ..
bun CLI/contract.ts --check
swift test
zsh scripts/build-app.sh
bun CLI/integration.ts
```

`contract.ts` owns the versioned schema. After an intentional contract change, regenerate its native resource using `bun CLI/contract.ts --write`. App packaging checks for drift.

The integration script launches an isolated app process with temporary project and endpoint directories, tests real CLI editing/save/relaunch/reversion and explicit installation, and invokes no paid provider. `ACT_AUTOMATION_DIRECTORY`, `ACT_PROJECT_ROOT` and `ACT_APP_PATH` support isolated validation. A custom endpoint disables ordinary native session restoration for that validation launch; normal launches preserve ordinary session recovery.

See [validation evidence](../docs/specs/ai-cli/validation.md) for measured checks and remaining OS/account boundaries.
