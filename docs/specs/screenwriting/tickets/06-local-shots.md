# 06. Generate shots locally

Status: complete
Parent: [Act screenwriting v1](../spec.md)
Blocked by: [02. Interpret Fountain scenes](02-fountain-scenes.md)

## Delivered behaviour

Offline shot generation with model setup, cancellation and recoverable errors.

## What to build

Research an Apple Silicon local runtime with primary sources before implementation. Implement explicit model acquisition/status and offline inference with no cloud fallback. Structured shots contain framing, action, camera movement and rationale. Validate output and constrain generation to selected scenes. Never mutate screenplay. Expose cancellation and actionable unavailable/model/output errors.

## Acceptance checks

- [x] Offline shot generation with model setup, cancellation and recoverable errors.
- [x] Failures are visible and preserve existing user content.
- [x] Relevant automated checks pass; manual evidence and remaining limits are recorded.

## Validation

```sh
swift test --filter Generation
```

Use behavioural tests at the relevant parser, document, PDF or runtime seam. Record evidence before marking complete. UI and real inference require separate manual checks.

## Context

- Parent spec: [Act screenwriting v1](../spec.md)
- ADRs: none
- Domain context: [Context map](../../../../context.md)

## Out of scope

- Other tickets' owned implementation, except agreed integration changes.
- Signing, notarisation, publication and custom font.

## Implementation evidence

Production recommended-model downloader fetched both official shards and verified exact sizes/SHA256. Production Swift subprocess adapter generated scene-linked shots offline with Metal and Qwen2.5 7B; cancellation and invalid-output checks pass. Final full suite enabled both real-model checks with no skips. Model quality still needs editorial review; one suggestion invented a door opening. See [validation](../validation.md).
