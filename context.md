# Context map

Read this map, then relevant domain context only. Follow ancestor AGENTS.md instructions. Do not recursively load every link.

| Scope | Context | Language | Decisions |
|---|---|---|---|
| Repository | This file | [Domain language](docs/Language.md) | [ADRs](docs/adr/README.md) |

Add one row per business domain when needed, pointing to its local context.md. Domain files own purpose, boundaries, contracts, test commands and links to active specs. Technical packages link to owning domain; they do not duplicate its definitions. Shared contracts have one owner.

Small repo: describe purpose, boundaries and validation here. Split only when independent domains need separate loading.

## Active changes

Link relevant [specs](docs/specs/README.md). Completed changes retain durable rationale through ADRs. No automatic deletion.

## Screenwriting

Act is a macOS-only Swift app for editing UTF-8 Fountain and planning shots with offline Apple Silicon inference. Raw Fountain remains authoritative. Shot lists are separate versioned JSON files; generation never edits screenplay source.

Active specification: [Act screenwriting v1](docs/specs/screenwriting/spec.md). Validation: `swift test`, `scripts/build-app.sh`, and `node .galicia/check.ts`. See [README](README.md) for native checks and model setup.

[Character reference sheets](docs/specs/screenwriting/character-sheets.md) adds manually marked action names, local MLX physical extraction and explicitly approved image-agent requests. Libraries live beside the screenplay; image generation never changes Fountain source.

[Project board](docs/specs/project-board.md) defines the implemented visual project organisation follow-up; native gesture/relaunch verification remains open.
