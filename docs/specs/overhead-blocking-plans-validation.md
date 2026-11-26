# Overhead blocking plans validation

Date: 2026-11-26
Scope: [Overhead blocking plans](overhead-blocking-plans.md)

## Automated evidence

- TypeScript typecheck: `bun run --cwd CLI typecheck`.
- Workspace and subprocess regressions: `bun test CLI/src`. Tests cover draft rejection/acceptance, separate source preservation, per-shot overlays, manual edits, persistence, unsupported data, stale input and planning revisions, undo/redo guards, references, missing shot IDs, spatial warnings, malformed output, runtime failure and cancellation.
- Full native suite: `swift test --no-parallel`. There were 243 native cases, with three existing opt-in model checks skipped and zero failures. The revised TypeScript suite adds 16 passing tests, including proposal clearance, described entrances and orientation persistence. The new `BlockingPlanTests` hosts the actual bundled WebKit editor with the native bridge and standalone helper. A fixture runtime supplies both geography and overlay passes; the test accepts a draft, edits a position by keyboard, adds an embedded PNG through a file-panel fixture, verifies its actual pixels in the exported PNG, flags changed shot input and recreates the native host to verify recovery. Fountain and shot bytes remain unchanged.
- Packaged build: `zsh scripts/build-app.sh`, including compiled TypeScript helper, bundled local editor and ad-hoc signatures.
- Repository metadata and whitespace: `node .galicia/check.ts` and `git diff --check`.

## Actual model evidence

The installed Qwen2.5 7B Q4_K_M GGUF ran with `/opt/homebrew/bin/llama-completion` and `--offline`. The two-pass check produced four shared physical objects and three valid shot overlays in approximately 16 seconds for a kitchen scene with Mara, Joel, a table and a left-hand door. Stable actor IDs and original shot UUIDs survived validation. A separate run through the compiled standalone helper produced three physical objects, three overlays and one spatial review warning in approximately 15 seconds.

Earlier single-pass attempts confused shot identifiers with physical objects or repeated actor IDs. The implementation now separates shared geography from keyed camera overlays, validates both and rejects malformed output. A fresh seed makes retry meaningful. Numeric validity does not establish correct blocking: the observed model can aim at the wrong actor. Deterministic review warnings flag obvious subject/aim mismatches, cameras inside set rectangles and actor-axis crossings, without modifying the proposal.

No cloud fallback or paid provider was used.

## Native interaction and output evidence

The packaged app was opened with a disposable kitchen screenplay and manually entered shot. Its Blocking plan sheet generated a real local draft, displayed inferred geography and supported explicit acceptance. The generated actor could be selected through accessibility, its X coordinate changed from 450 to 550 and the updated geometry saved. Closing and reopening the sheet restored the plan. Keyboard editing and recovery are additionally covered by the native integration test.

Native save panels produced an editable `.blocking.json`, a 2800 by 2125 PNG and a single-page PDF. The PNG was inspected directly. The PDF was rasterised with Poppler and inspected; it contains the plan, shot/framing labels and inferred-geography legend. These outputs are local verification artifacts under `.scratch/blocking/`, not published assets.

The initial chart-like presentation was rejected by Leo. The revised interface uses a full scene canvas with named, coloured overhead people, furniture shapes and a camera/tripod piece. Actor orientation is visible and editable with turn handles and a facing control. A compact contextual control replaces the permanent coordinate inspector; numeric fields live behind disclosure controls. The final visual retouch uses translucent glass pill buttons, unified floating properties, unboxed review/status rows and reduced-transparency/high-contrast fallbacks. Native inspection confirmed readable controls and unobscured draft acceptance actions.

Physical CUA mouse drags moved Mara and the camera on the native canvas. The camera aim handle was dragged separately. The integration test verifies person movement, turning to 90 degrees, recovery of both position and facing, and reference-image export. The revised compiled helper generated a three-shot proposal in approximately 15 seconds, with three physical objects and no current spatial warnings. A subsequent entrance regression ensures a described left/right door is present and the entering character is placed beside it; wide camera proposals keep both named characters in front of the lens. Human spatial review remains necessary.

## Limits

- Existing local text inference does not analyse reference pixels. Images guide manual placement; entered notes guide generation. The first image is fitted beneath the schematic plane without registration controls.
- Plans are schematic, with no lens calibration, physical scale or guarantee of valid production coverage. Heuristic warnings supplement human review.
- Exports contain one selected shot. PDF embeds a high-resolution raster and does not preserve editable vector objects. The JSON file is the editable master.
- All scene/shot snapshot changes conservatively flag review. Missing or regenerated IDs are retained in the original plan rather than guessed or automatically relinked.
- Undo/redo history is session-local. Recovery is keyed by screenplay identity and scene; Save As/rename migration and reopening an unsaved screenplay in a new document identity are not established. Explicit saved plans can be reopened for their original scene.
- Light appearance was not separately exercised on the desktop. Reference-image PNG composition is covered by the actual native WebKit integration test. Physical dragging, position editing, saved geometry and desktop exports were exercised.
- Local validation does not establish a release or deployment.
