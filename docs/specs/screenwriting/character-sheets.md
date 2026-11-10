# Character reference sheets

Status: active
Domain: Screenwriting
Owner: Leo
Related ADRs: none
Tickets: none

## Problem

Writers need visual references for selected characters without scanning every character in the screenplay or altering Fountain source.

## Intended behaviour

In the editor, select a name inside an action paragraph and use the context menu to create a character or link to an existing character. Each character has a persistent, distinct colour. Only explicitly marked occurrences participate. The containing action paragraph includes contiguous action lines, ending at a blank line or another Fountain element type. Dialogue cues, headings and hidden notes cannot become character marks.

Characters is a workspace beside Screenplay and Shot list. Local MLX extracts explicit physical attributes from marked paragraphs. Each attribute retains a verbatim evidence quote. Missing traits remain unspecified; props, status and personality are not appearance. Linked occurrences contribute to one character, with differing values for the same attribute flagged for review. Extraction fills an empty prompt but never overwrites an existing prompt. Rebuilding a non-empty prompt from extracted details requires confirmation.

The writer edits the prompt and chooses when to generate. The default asks for front, profile, back and facial expressions on a neutral background. A generation request always previews the exact description and any reference image before transmission. Act supplies no screenplay file to the external agent. The agent may have its own account, instructions, hooks and image tools.

Act starts a terminal executable as a background subprocess, waits for completion, validates its raster output and imports it into the character library. Codex, Claude Code, Grok Build and Cursor Agent have distinct adapters. Only connections which pass an explicit, user-approved sample image generation test appear in the generation picker. The user inspects that result before confirming capability. Reference editing has a separate test; generation-only connections can generate new sheets but cannot iterate. No automatic fallback, tool installation, credential changes or account changes occur.

Iteration sends the active sheet plus the current edited prompt. Each success creates a new version and selects it. Previous images, prompts, agents and reference-version links remain available. Failure and cancellation preserve existing details, images and the current prompt. Cancellation stops the subprocess group. A local deadline bounds MLX to 180 seconds and external generation to 600 seconds.

## Acceptance checks

- [x] Only selected names inside action paragraphs can be marked; Fountain text, selection and writing undo remain unchanged.
- [x] Linked marks share identity and colour; marks rebase through edits outside the name and flag changed paragraphs.
- [x] Missing or edited names detach rather than silently attaching to another occurrence. Reopened libraries with changed screenplay fingerprints require relinking.
- [x] MLX runs with an existing local model, offline environment switches and validated evidence JSON. No cloud fallback occurs.
- [x] Existing editable prompts survive extraction, paragraph edits and failures.
- [x] Generation connections remain hidden until a real raster test succeeds and the user confirms its content. Reference editing is independently gated.
- [x] Images have bounded size/dimensions and decode as PNG, JPEG or WebP. SVG, old reference copies, arbitrary external paths and malformed output are rejected.
- [x] Libraries persist beside the screenplay and protect against external manifest changes. Save As preserves the original folder.
- [ ] All four installed agent accounts have passed actual generation and reference-edit tests. These tests can incur charges and require explicit payload approval in the app.
- [ ] Full desktop interaction, including permission dialogs and paid agent output, has been verified in the running app.

## Decisions and contracts

This approved change extends the original v1 exclusion of cloud inference only for explicit image-agent requests. Existing shot inference stays unchanged. MLX character extraction remains local. Swift follows the native application contract in the parent spec.

`Draft.fountain` uses `Draft.characters/characters.json` plus `images/<UUID>.<extension>`. The version-1 JSON owns characters, colours, UTF-16 name anchors, marked action text, extracted evidence, prompt, image history and active image. Assets use relative paths; no image file is overwritten on regeneration. Metadata autosaves independently of Fountain, with a dirty-close guard on write failure. Save As copies the folder and refuses to overwrite an existing destination library.

MLX uses a separately installed `mlx_lm.generate` executable and an existing model directory containing `config.json` and safetensors weights. Each marked paragraph is capped at 12,000 UTF-8 bytes. JSON contains `traits`, each with `attribute`, `value` and an exact `evidence` quote. Unsupported attributes, absent evidence, malformed/truncated JSON and overlong fields reject the whole extraction, preserving previous details. Semantic attribution still needs editorial review.

External prompts are capped at 32,000 UTF-8 bytes. Each invocation gets a fresh temporary working directory, explicit argv and stdin, with no shell interpolation. Cursor uses `cursor-agent`, never the ambiguous `agent` alias. Grok exposes only the requested image tool, denies MCP and disables subagents. Its approval flag is limited to that restricted tool set after Act's explicit request approval. Other adapters preserve agent permission policies; missing tool permissions cause a visible failure instead of bypassing them.

Generation capability is recorded against the selected executable path, resolved path, modification date and size. An executable update requires verification again. Account/tool changes can still invalidate that record; a subsequent failure preserves work and requires correcting the agent configuration. Capability tests establish actual returned-image behaviour, not a general claim about a vendor or subscription.

## Test seam

Core tests cover action paragraph selection, raw source, linked identity, stale anchors, evidence contracts, sidecar validation, offline process arguments, image import, literal prompts and process-group cancellation. Native tests use the actual editor and document to verify highlights, caret/undo preservation, persisted prompts, image history, conflicts and Save As. Optional native renders and real MLX inference provide separate visual and runtime evidence.

## Validation

```sh
swift test
scripts/build-app.sh
node .galicia/check.ts
ACT_TEST_MLX_RUNTIME=/absolute/path/mlx_lm.generate ACT_TEST_MLX_MODEL=/absolute/path/model swift test --filter CharacterSheetTests.testRealMLXExtractionWhenExplicitlyConfigured
ACT_TEST_CHARACTER_PREVIEW_DIRECTORY="$PWD/.scratch/character-sheets-preview" swift test --filter CharacterWorkspaceTests.renderActualCharacterWorkspaceWhenRequested
```

See [character validation](character-sheets-validation.md) for measured results and remaining live-agent boundaries. Acceptance checkmarks describe implementation plus automated evidence; the unchecked live checks keep this spec active.

## Exclusions

- Automatic discovery of characters, whole-screenplay extraction and inferred physical traits.
- Automatic model downloads, third-party image API credentials and unapproved external requests.
- Provider fallback, direct API billing integration, signing, notarisation and publication.

## Unresolved decisions

- None for the approved behaviour. Per-account image tool availability remains a runtime capability check.
