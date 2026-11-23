# 0002. App-owned automation

Status: accepted
Date: 2026-11-22
Deciders: Leo Lemos

## Context

Terminal agents and computer-use applications need precise screenplay editing and image workflows. The authoritative working source can contain unsaved changes inside `FountainDocument`. Independent filesystem editing cannot participate in native undo or reliably observe that state. Leo approved the complete automation scope and authorised implementation after a scoped Luna architecture review.

## Decision

Use one main-actor command service inside the native application. A standalone TypeScript CLI connects through a per-account Unix-domain socket. An accessible Automation window submits the same versioned requests to the same service. Swift owns native document state and validates mutations. TypeScript owns the wire schema and CLI; its generated JSON resource is checked for drift before packaging.

The app launches with an explicit background argument for automation. Commands name documents and expected revisions rather than relying on the focused window. Edit preview and apply are separate operations. Request receipts are persisted before mutation so interrupted requests cannot be blindly repeated. Review history and image assets stay outside Fountain.

Automation writes are restricted to managed projects beneath `~/Documents/Act`. Source revisions cover native writing and undo/redo. Planning workspaces retain separate revisions. External image requests enter an approval queue, with no approval operation exposed over the command API.

## Alternatives

### Direct filesystem edits

Rejected because unsaved source, native undo and open-document conflict handling would diverge.

### XPC from TypeScript

Would require native bindings or a second Swift helper. The socket uses existing TypeScript networking and avoids that additional process boundary.

### Apple Events or URL commands

Do not provide the same direct bounded request/result contract and would add an independent scripting interface to maintain.

### Local HTTP

Rejected because the approved scope excludes network listeners.

## Consequences

- The CLI requires no separately installed Node runtime. Bun is a development/build dependency for its standalone executable.
- The app remains the single owner of mutations, whether requests arrive through IPC or the Automation window.
- Socket permissions and peer-account checks limit access to the local account. This is not isolation from other authorised processes running as that same account.
- Journal failure and uncertain process outcomes must remain explicit; a timeout cannot establish whether an edit happened or whether a provider charged for work.
- macOS launch/focus behaviour, endpoint recovery and actual native interactions need integration evidence in addition to unit tests.

## Evidence

- Approved interview decisions and [scope](../specs/ai-cli.md).
- Luna read-only review identified existing `FountainDocument` ownership, native undo, safe saves and image process adapters as the reuse points.
- Native integration tests and standalone packaging evidence are recorded in the [validation record](../specs/ai-cli/validation.md).

## Linked specs

- [AI editing and automation](../specs/ai-cli.md)
