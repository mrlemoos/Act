# Character sheet validation

Date: 2026-11-10
Scope: manually marked action names, local physical extraction, external image-agent adapters, native workspace and portable assets.

## Automated checks

The final full `swift test` run discovered 125 tests: 123 passed, two existing GGUF inference/download checks were skipped, and none failed. This run enabled the new actual MLX test and optional native renders. The default run also skips the actual MLX check. The native preview test renders only when its output-directory environment variable is set.

Evidence is in `.scratch/character-sheets-validation.log`. The run contains 60 XCTest core checks, 33 Swift Testing core checks and 32 native app checks. Fourteen core checks and six native checks cover the character feature.

Covered behaviours include action-only selection, multiline/CRLF paragraphs, Unicode range rebasing, hidden comments, duplicate marks, linked identity, contradictions, stale and detached anchors, prompt preservation, external manifest conflicts, Save As, relative image paths, output decoding, malformed raster rejection, shell-literal prompts, local-only MLX arguments and process-group cancellation. A native asynchronous test changes the source during extraction and confirms the old result cannot overwrite current details or the edited prompt.

`node .galicia/check.ts` passed without metadata flags. This is record validation, not a semantic or runtime check.

## Actual MLX inference

Installed a project-local Python 3.11 environment at `.scratch/mlx-runtime` for validation. Dependencies include MLX-LM 0.32.2, MLX/MLX Metal 0.32.4 and transformers 5.22.2. No inference model was downloaded. The test reused the existing `mlx-community/Qwen3.5-4B-MLX-8bit` snapshot `5319bbbe4f1cbe6c0b3c80f4f7de4f0338c3906d` from the local Hugging Face cache.

The first run exhausted its token budget in model reasoning and was rejected as invalid output. Disabling thinking through MLX-LM's chat-template configuration produced the intended bounded JSON. The production adapter uses that setting, `--temp 0`, `--seed 42`, a 1,024-token cap, local model paths and offline Hugging Face/transformers environment flags.

The ORLEANS action paragraph returned exactly:

```json
{"traits":[{"attribute":"hands","value":"calloused","evidence":"calloused fingers"}]}
```

This confirms actual MLX execution and evidence validation for the example. It does not establish semantic accuracy for arbitrary screenplays. Writers still review attributed details and resolve conflicting descriptions in their prompts.

## Native rendering and package

Character-menu performance regression coverage observes actual `NSTextStorage` edits through the menu handler and subsequent SwiftUI refresh. Adding a mark must change attributes only inside the selected name. Linked occurrences retain their colour; detaching a mark restores its underlying foreground colour and preserves emphasis. Cached selection tests reject a parsed screenplay whose source no longer matches.

The native benchmark on a disposable copy of a 115,951-byte screenplay with 15 existing characters measured 15.7 ms in the synchronous menu handler in a debug build. This includes marking, persistence and immediate highlighting, but excludes host setup and deferred SwiftUI updates. It is a local measurement, not an end-to-end latency guarantee. Run with `ACT_CHARACTER_BENCHMARK_SOURCE=/absolute/path/Draft.fountain swift test --filter benchmarkCharacterMenuWhenScreenplayConfigured`. The benchmark copies the character library into a temporary directory and leaves the original untouched.

Rendered and visually inspected the actual SwiftUI workspace and AppKit editor in hidden native test windows:

- `.scratch/character-sheets-preview/characters-light.png`, 1,280-point workspace.
- `.scratch/character-sheets-preview/characters-narrow-dark.png`, 820-point dark workspace.
- `.scratch/character-sheets-preview/editor-mark-light.png`, 1,000-point editor with a coloured ORLEANS mark.
- `.scratch/character-sheets-preview/characters-layout-fixture-narrow.png`, 820-point image-history/iteration layout using a synthetic raster solely for layout inspection. This is not generated character artwork or evidence of agent capability.

The inspected controls fit at the minimum window width. Fountain text and the native caret/undo contract are covered separately by assertions. `scripts/build-app.sh` produced an ad-hoc signed `.build/Act.app`. No distribution release, notarisation, installation or publishing occurred.

## Agent evidence and remaining boundaries

Read-only inspection confirmed the installed noninteractive CLI flags for Codex 0.167.0, Claude Code 2.1.311, Grok Build 1.0.77 and Cursor Agent 2026.11.05-86047df. Cursor's desktop launcher differs from `cursor-agent`, and the generic `agent` name resolves to Grok on this Mac.

Grok documents native `image_gen` and `image_edit` tools, including absolute image-output paths. Its [headless tool allowlist](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/14-headless-mode.md), [generation implementation](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-tools/src/implementations/grok_build/image_gen/mod.rs) and [editing implementation](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-tools/src/implementations/grok_build/image_edit/mod.rs) informed the adapter. Actual account entitlement is unverified. Act restricts each Grok call to the chosen image tool, denies MCP meta-tools and disables subagents before enabling approval for that restricted tool set.

The other adapters use their observed headless interfaces and preserve permission policies. No native image-generation claim is made for Codex, Claude or Cursor. A configured plugin or MCP image tool may make a connection usable. Missing capabilities, permissions or authentication must fail visibly. Cursor's native reference attachment contract was not established; its agent is instructed to use the explicit reference file in its temporary workspace and must pass the separate editing test.

The subprocess/import seams were tested with controlled local executables. No actual paid image generation, cloud screenplay request, sign-in or credential mutation was performed. All four connections start unverified and remain absent from the generation picker until their actual sample-image test succeeds and the user confirms the result. Reference editing requires its own test. Per-account generation, iterative image editing, agent-specific interactive permission failures, sign-in expiry, cancellation of vendor-owned remote jobs and full desktop dialog interactions remain live checks. Local cancellation stops the subprocess group; it cannot guarantee cancellation of a request already running on a provider's servers.

See the [approved scope](character-sheets.md) and [MLX-LM source](https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/generate.py) for the request and extraction contracts.
