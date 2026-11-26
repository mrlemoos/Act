# Overhead blocking plans

Status: complete
Domain: Screenwriting and shot planning
Owner: Leo Lemos
Related ADRs: [0002. App-owned automation](../adr/0002-app-owned-automation.md), relevant if automation is extended; storage and generation ADR not yet proposed
Tickets: None

## Problem

Act stores scene-linked shot lists with framing, action and camera movement, but these fields do not establish spatial geography. A filmmaker needs overhead blocking diagrams, also called camera plots, to review actor placement, camera positions and movement after a shot list is ready. Independently generated drawings can contradict one another or conceal invented geography.

Current shot documents use stable shot UUIDs and scene anchors. They do not contain floor-plan geometry. Existing storyboard images are raster assets for individual shots, a different output from an editable overhead scene plan.

## Intended behaviour

Once a scene has a shot list, the user can request an overhead plan for that scene. One editable scene plan supplies shared geography; selecting a shot reveals its camera, framing and movement overlay. Plans show wide, medium or close framing as shot information rather than claiming that an overhead drawing proves the final photographed composition.

Generation proposes location geometry, actor positions and camera positions for review. Optional floor plans and location photographs guide the proposal. Missing geography remains visibly labelled as inferred. References are optional; their absence must not prevent drafting a plan.

Actors appear as named overhead people with visible bodies and facing direction. Cameras appear as recognisable camera/tripod pieces. People, cameras and furniture can be dragged directly on a scene-sized floor canvas; handles turn people and aim the camera. Numeric fields are secondary contextual controls. Framing and movement remain editable planning information rather than a flattened generated image. The user can adjust the plan and select shot overlays without regenerating the scene. Generation runs locally, with no cloud fallback. Complex or ambiguous spatial relationships can require manual correction.

Every generation produces a reviewable draft. It does not replace an existing accepted plan until the user explicitly accepts it. Rejecting or cancelling preserves manual work. Conflicting shot directions remain visible for review rather than silently rewriting the shot list.

Changed shot lists flag affected diagrams for review. Existing layouts remain available until the user explicitly regenerates them. Editable plans persist across save and reopen. PDF and PNG exports support printing and sharing with crew.

## Acceptance checks

- [x] A scene with shots can produce a draft plan with shared geography and selectable overlays linked to its shots.
- [x] Switching shots preserves shared geometry and displays the selected shot's camera position, framing and movement.
- [x] The user can directly drag people, furniture and camera pieces, turn people, aim the camera, save and reopen the resulting positions, orientation and shot associations.
- [x] Generation without references identifies inferred geography. Supplied floor plans or photographs are available to the local drafting workflow; unsupported references produce an explicit limitation.
- [x] Draft review exposes proposed geography and conflicting shot directions before acceptance.
- [x] Accepting a draft updates only its intended scene plan. Rejecting it preserves the previous plan and manual edits.
- [x] Cancellation, missing runtime/model, invalid generated geometry and generation failures leave accepted plans and source documents unchanged and allow retry.
- [x] A shot-list change identifies affected diagrams as needing review without silently regenerating, deleting or remapping their layouts.
- [x] Results generated against an older input or plan revision cannot overwrite newer manual work without renewed review.
- [x] Local generation works offline after required setup; screenplay content, shot data and reference assets are not sent to external services.
- [x] PDF and PNG exports remain legible and preserve the chosen plan's geography, shot identification, framing, movement and inferred-geography labels. Export selection and page rules remain to be agreed.
- [x] Opening invalid or unsupported plan data reports the problem without overwriting the existing file.
- [x] Generating, editing, accepting and exporting plans never changes Fountain source or shot-list text.

## Decisions and contracts

### Agreed scope

The planning unit is one editable plan per scene, with selectable shots sharing its geography. Location, actor and camera positions begin as proposals requiring approval. Reference assets are optional. Local generation, reviewable replacement, preservation of manual adjustments, change flags, editable persistence and PDF/PNG export are in scope.

Fountain remains authoritative. Overhead plans are planning assets separate from screenplay text and distinct from storyboard raster images. Existing shot UUIDs and scene anchors are the available association points; identifiers must not be inferred from display order alone.

### Proposed implementation safeguards

These safeguards make the agreed preservation and review behaviour testable; exact mechanisms remain open:

- Record the input scene/shot revision and plan revision used for generation. Recheck them before accepting a replacement.
- Validate locally generated structured geometry before exposing an acceptable draft. Rendering must preserve editable objects.
- Retain enough provenance to distinguish inferred geography from supplied references and user corrections.
- Preserve accepted work when save, decode or export fails. Unsupported formats must not be rewritten automatically.
- Keep draft acceptance explicit and scoped to the selected scene. Do not grant automation an implicit approval capability.

Implementation uses version-1 `.blocking.json` files, one scene per document. Existing shot JSON is unchanged. The document stores the original scene and shot snapshot, embedded references, shared objects, per-shot camera/actor geometry and review warnings. Coordinates occupy a schematic 1000 by 600 plane; measurements and view cones are not calibrated. Actor rectangles define shared starting positions; per-shot centre positions and optional movement endpoints override them. Optional facing angles in degrees persist both shared and per-shot actor orientation without changing the format version; older files remain readable. Without an explicit facing angle, two actors face one another. Shot UUIDs remain the association contract. Missing or regenerated UUIDs flag review rather than automatically remapping overlays.

TypeScript owns the planning model, validation, SVG editor and local generation helper. A native WebKit sheet supplies file panels, revision-aware recovery and process execution. Assets are bundled locally with a content policy that permits no network connections. This preserves the existing native app and TypeScript implementation requirement; no automation command or approval capability is added.

The local helper performs two offline GGUF passes using the selected runtime/model: shared physical geography first, camera overlays second. Host-assigned actor IDs and short shot handles separate spatial reasoning from persistent UUIDs. Before draft review, inferred proposals reserve body clearance around solid furniture, prevent overlapping people, give furniture usable schematic dimensions and aim named-subject shots at the proposed person. These adjustments apply only to newly generated proposals, never to accepted work or manual edits. Structured geometry is validated between passes and before draft review. Generation supports up to 16 shots and 32,000 bytes of scene/shot/reference-note input, with a three-minute timeout per pass, process-group cancellation and fresh retry seeds. Invalid output remains a visible error, never a replacement plan.

Up to four embedded PNG/JPEG references are supported, with 2 MB per image and 4 MB combined limits. The first reference can appear beneath the editable plan. The existing text model does not interpret pixels; reference notes guide inference and images guide manual placement. Other reference formats require conversion. Every generated object begins as inferred; only the user can confirm its geography.

All scene or shot snapshot changes conservatively flag the existing plan. Missing scenes or an empty shot list invalidate pending acceptance. Draft acceptance additionally checks the planning revision and reference metadata, including through undo/redo. Draft and accepted work remain distinct. Undo/redo is session-local; recovery retains accepted work, draft state and reference notes. File saves use atomic writes and compare the previous on-disk baseline; external changes offer Save Copy rather than overwriting.

Exports contain the selected shot only. PNG output is 2800 by 2125 pixels. PDF is one 840 by 637.5 point landscape page embedding that raster output. Draft and stale exports are labelled. Plan JSON remains the editable master; exports are presentation assets.

## Test seam

Implementation uses the native planning workspace boundary, following [ShotWorkspaceTests](../../Tests/ActAppTests/ShotWorkspaceTests.swift), as the highest useful behavioural seam. The implementation instruction proceeded with this proposed seam. Drive draft generation, review, acceptance, manual edits and changed-input handling through the workspace with a fixture local generator at the process boundary. Retain real validation and persistence below it. TypeScript workspace tests cover rejection, revision guards, format validation, warnings and process cancellation; native `BlockingPlanTests` loads the real bundled editor, exercises the helper bridge, accepts and edits a plan, changes shot input and reopens recovery. This proves preservation outcomes without depending on live model output.

Use [ShotListTests](../../Tests/ActCoreTests/ShotListTests.swift) as prior art for persistence, identifiers and unsupported-version handling. Add focused geometry/store checks where workspace outcomes cannot prove malformed-data handling.

Native visual verification is additionally required for selecting overlays, manipulating symbols and inspecting printed/exported output. Existing shot tests do not establish diagram usability or local spatial reasoning quality.

## Validation

Existing repository commands, to run during implementation:

```sh
bun run --cwd CLI typecheck
bun test CLI/src
zsh scripts/build-cli.sh
swift test --no-parallel
zsh scripts/build-app.sh
node .galicia/check.ts
```

Before completion, record behavioural evidence for the acceptance checks, native interaction evidence, inspected PDF/PNG exports and an actual offline model run. Fixture generation alone does not prove spatial quality, reference interpretation or offline inference capability. See [validation and limits](overhead-blocking-plans-validation.md) for implementation evidence. Completion remains subject to the limits recorded there.

## Exclusions

- Photorealistic storyboards or replacement of existing storyboard images.
- Cloud generation or automatic external image-agent requests.
- Automatic screenplay or shot-list rewriting to resolve spatial conflicts.
- Silent replacement of accepted plans or automatic regeneration after shot changes.
- Survey-grade measurements, lens calibration or guaranteed physical feasibility from unspecified geography.
- Publishing, external tracker changes, new automation commands and release work.

## Unresolved decisions

- No implementation-blocking decision remains for this scope. Automatic pixel interpretation, multi-page export and automatic relinking of regenerated shot IDs remain excluded follow-ups.
- Local model output still requires human spatial review. Numeric validity and warning heuristics cannot establish correct camera coverage or production feasibility.
- Reference alignment currently uses the first image fitted beneath the full schematic plane. Image registration, rotation and perspective correction are not implemented.
- Scoped small-model architecture review was recommended in the draft. No delegation was authorised or performed; no ADR has been represented as accepted.

The implementation has independently verifiable persistence, generation/review and export responsibilities. No external tracker or local ticket set was created.
