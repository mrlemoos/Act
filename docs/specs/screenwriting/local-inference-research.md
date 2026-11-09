# Local shot generation research

Date: 2026-11-09
Owner: implementation team
Scope: ticket 06, runtime and model choice. This is implementation research, not an accepted ADR.

## Selected implementation

Act invokes the installed `llama-completion` companion directly using Foundation `Process`, with a GGUF selected by the user or explicitly downloaded by Act. The runtime's Metal backend supports Apple Silicon. Act supplies `--offline`, a local model path, a bounded context/output budget and a JSON schema. Screenplay text is passed through a private temporary prompt file. Inference makes no URLSession call and has no cloud fallback. Temporary input/output files are removed after success, failure or cancellation.

The installed runtime includes `/opt/homebrew/bin/llama-cli` and `/opt/homebrew/bin/llama-completion`, version 0.9.0, build 12110, commit cd959bae9. Its local `--help` confirms `--offline`, `--json-schema-file`, `--single-turn`, `--gpu-layers` and `--simple-io`. Current llama-cli uses a server-oriented UI and echoes prompts despite `--no-display-prompt`; Act prefers llama-completion and resolves a selected llama-cli to its installed companion when available. JSON wire keys use snake case because current schema conversion generates invalid grammar rules for camelCase cameraMovement. Runtime installation remains explicit; Act can locate Homebrew installations or accept a selected executable. Runtime packaging/signing is outside v1.

The recommended model is the official Qwen2.5 7B Instruct Q4_K_M GGUF, 4,683,073,632 bytes across two shards. It has Apache 2.0 licensing. Act pins repository revision `bb5d59e06d9551d752d08b292a50eb208b07ab1f`, verifies artifact sizes and SHA256 before installing each shard and passes the first shard to llama.cpp. Existing shards are checked before reuse during download. App startup does not download anything. The UI owns download activity/cancellation and displays size before the explicit action. A failed second shard remains visibly incomplete and can be retried without downloading the verified first shard again.

This is a conservative compatibility choice, not a claim that Qwen2.5 is the newest or best model. Its published instruction-following/JSON support and stable GGUF path make it suitable for the initial structured-output contract. Creative usefulness still needs human review. Small test-model inference does not prove 7B output quality.

## Alternatives

- Apple Foundation Models offers a native on-device framework, but introduces Apple Intelligence availability and OS/model eligibility constraints. The initial implementation uses explicit model files so setup and model choice remain under user control. No claim about its comparative quality was measured.
- Ollama is installed on this Mac. A direct llama.cpp subprocess avoids dependence on an already-running service and a configurable HTTP endpoint.
- MLX Swift would embed an Apple Silicon stack directly but adds package and runtime integration work before this app's editing flow is verified. It remains a future packaging option.

## Limits and failure behaviour

- Selected scene only, at most 12,000 UTF-8 source bytes. Larger scenes fail visibly rather than truncate silently.
- One to sixteen requested shots, eight by default. Output must contain non-empty framing, action, camera movement and rationale fields. Act assigns trusted scene IDs rather than accepting model IDs.
- Output schema and validation do not guarantee correct cinematography or faithful story coverage. Shot text remains editable.
- Cancellation terminates the subprocess, escalating to SIGKILL after two seconds if needed; a 180-second deadline also stops it. No partial generated shots are committed.
- Imported GGUF files require the `GGUF` magic bytes; llama.cpp performs full compatibility checks. An Ollama-specific Gemma4 blob on this machine failed loading with `wrong number of tensors; expected 2131, got 720`. The source model was read only.
- Recommended-model download UI interaction still requires separate visual integration evidence. Actual download and Qwen 7B inference have now passed through the Swift implementation. A compiler pass or fixture subprocess alone would be insufficient.

## Primary sources

- [llama.cpp repository](https://github.com/ggml-org/llama.cpp), Apple Silicon, Metal and supported runtime paths.
- [llama.cpp CLI reference](https://github.com/ggml-org/llama.cpp/blob/master/tools/cli/README.md), subprocess and single-turn parameters.
- [llama.cpp grammar reference](https://github.com/ggml-org/llama.cpp/blob/master/grammars/README.md), JSON-schema constrained output and its limits.
- [Official Qwen2.5 7B GGUF model card](https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-GGUF), model licence, context, download and split-file guidance.
- [Official model metadata](https://huggingface.co/api/models/Qwen/Qwen2.5-7B-Instruct-GGUF?blobs=true), exact revision, artifact lengths and SHA256 values queried during implementation.
- [Apple Foundation Models documentation](https://developer.apple.com/documentation/foundationmodels), alternative native framework.

## Verification

Real CLI inference passed on this Apple M5 Pro using llama-completion, Metal, `--offline`, and the official Qwen2.5 0.5B Instruct Q4_K_M development model. The 491,400,032-byte model was downloaded into `.scratch/generation/`, pinned to revision `9217f5db79a29953eb74d5343926648285ec7e67`, and SHA256 matched `74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db`. Output contained two schema-valid shots. The tiny model repeated generic example text, so this proves the runtime and structured-output path, not useful creative quality. The subsequent recommended-model test below verifies the full 7B path separately.

Raw prompt, schema, stdout and stderr are in `.scratch/generation/`. Swift adapter tests include fixture subprocess success, cancellation, malformed output and an opt-in real test using `ACT_TEST_MODEL`. Root integration ran the full 30-test suite successfully before the additional opt-in recommended-model test was added. Earlier app NSDocument actor-isolation compile errors were resolved by the app owner.

[Official development-model card](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF).

### Recommended-model verification

The opt-in XCTest `GenerationTests.testRecommendedModelDownloadAndOfflineInferenceWhenExplicitlyConfigured` passed on 2026-11-09. It called the production `LocalModelStore.download()` with `.scratch/recommended-model` as its destination, verified both pinned shard SHA256 values and lengths, asserted `isDownloaded`, then called the production Swift generation adapter with the downloaded first shard and the installed Metal runtime.

Result: one test, zero failures, 86.158 seconds including download, checksum validation and generation. The model files total 4,683,073,632 bytes and remain in `.scratch/recommended-model`. The generated output contained three shots with trusted `recommended-model-scene` IDs and complete framing/action/movement/rationale fields. Raw test output and generated shot JSON are in `.scratch/generation/recommended-test.log`.

The recommended model produced scene-specific shot suggestions, but one shot described the door opening where the source only said the handle turns. This demonstrates why generation remains an editable draft requiring the writer's review. It is not evidence of faithful coverage across arbitrary screenplays.

Reproduce explicitly, without making the default test suite download a model:

```sh
ACT_TEST_DOWNLOAD_DIRECTORY="$PWD/.scratch/recommended-model" swift test --filter GenerationTests.testRecommendedModelDownloadAndOfflineInferenceWhenExplicitlyConfigured
```

Existing shards are checksum-verified and reused on subsequent explicit runs. The GUI download button invokes this same production store, but its visual interaction remains a separate integration check.
