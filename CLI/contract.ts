import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

type Field = Record<string, unknown>;
const string = { type: 'string', minLength: 1 };
const text = { type: 'string' };
const boolean = { type: 'boolean' };
const edit = {
  type: 'object', additionalProperties: false, required: ['kind', 'sceneID'],
  properties: {
    kind: { enum: ['insert', 'replace', 'remove', 'move'] }, sceneID: string,
    match: text, text, side: { enum: ['before', 'after'] },
    destinationSceneID: string, destinationAnchor: string,
    destinationSide: { enum: ['before', 'after'] },
  },
};
type Operation = { summary: string; mutation: boolean; revision: 'none' | 'source' | 'shots' | 'characters'; parameters: Field };
function operation(summary: string, revision: Operation['revision'], required: string[] = [], properties: Record<string, Field> = {}, mutation = revision !== 'none'): Operation {
  return { summary, mutation, revision, parameters: { type: 'object', additionalProperties: false, required, properties } };
}

export const operations: Record<string, Operation> = {
  status: operation('Inspect server health and managed project root.', 'none'),
  schema: operation('Discover this versioned contract without opening Act.', 'none'),
  'projects.list': operation('List managed projects.', 'none'),
  'projects.create': operation('Create a project; refuse name collisions.', 'none', ['name'], { name: string }, true),
  'projects.import': operation('Copy a Fountain file and linked sidecars into a new project, preserving originals.', 'none', ['name', 'path'], { name: string, path: string }, true),
  'documents.list': operation('List live document IDs, source/planning revisions and persistence status.', 'none'),
  'documents.open': operation('Open a managed Fountain file without activation.', 'none', ['path'], { path: string }, true),
  'documents.import': operation('Copy a screenplay and linked sidecars into an existing project, then open the copy. Refuse collisions and preserve originals.', 'none', ['project', 'path'], { project: string, path: string, name: string }, true),
  'documents.create': operation('Create a Fountain file in an existing project; refuse overwrite.', 'none', ['path'], { path: string, source: text }, true),
  'documents.inspect': operation('Inspect one live document and prepare linked metadata.', 'none'),
  'documents.save': operation('Save source through native conflict checks; optional path first-saves an untitled document to a new managed .fountain path.', 'source', [], { path: string }),
  'source.read': operation('Read unsaved source and scene IDs; $document explicitly addresses the whole source.', 'none', [], { sceneID: string }),
  'edits.preview': operation('Resolve an atomic batch against one revision; no source mutation.', 'source', ['edits'], { edits: { type: 'array', minItems: 1, maxItems: 500, items: edit } }),
  'edits.apply': operation('Apply a reviewed preview once, as one native undo step.', 'source', ['previewID'], { previewID: string }),
  'edits.discard': operation('Discard an unused preview without altering source or review history.', 'none', ['previewID'], { previewID: string }, true),
  'reviews.list': operation('Read persistent AI changes, conflict and dismissal state.', 'none'),
  'reviews.archives': operation('Inspect retained unsaved-document review archives without restoring or overwriting source.', 'none'),
  'reviews.navigate': operation('Explicitly navigate to a change; only this action moves the selection.', 'none', ['changeID'], { changeID: string }, true),
  'reviews.dismiss': operation('Dismiss batch/all highlights without erasing history.', 'source', [], { batchID: string }),
  'reviews.clear': operation('Explicitly clear review history; requires confirm:true.', 'source', ['confirm'], { confirm: { const: true } }),
  'reviews.revert': operation('Safely revert a change/operation/batch; refuse overlap with later writing.', 'source', ['changeID'], { changeID: string }),
  'shots.list': operation('Read shot entries and their current shotRevision.', 'none'),
  'shots.add': operation('Add a shot anchored to a current scene.', 'shots', ['sceneID'], { sceneID: string, framing: text, action: text, cameraMovement: text, rationale: text }),
  'shots.update': operation('Update explicitly supplied shot fields.', 'shots', ['shotID'], { shotID: string, framing: text, action: text, cameraMovement: text, rationale: text }),
  'shots.remove': operation('Remove one shot; retain image history.', 'shots', ['shotID'], { shotID: string }),
  'shots.generate': operation('Start offline shot generation; retain existing shots until explicit apply.', 'shots', ['sceneID'], { sceneID: string }),
  'shots.apply': operation('Explicitly apply a ready generation result to its unchanged scene.', 'shots', ['jobID'], { jobID: string }),
  'characters.list': operation('Read characters, marks, physical evidence and image versions.', 'none'),
  'characters.create': operation('Create a character without discovering or marking occurrences.', 'characters', ['name'], { name: string }),
  'characters.mark': operation('Mark one exact action-name occurrence; optional characterID links an existing character.', 'characters', ['sceneID', 'match'], { sceneID: string, match: string, characterID: string }),
  'characters.update': operation('Update a character name and/or authored image prompt.', 'characters', ['characterID'], { characterID: string, name: string, prompt: text }),
  'characters.extract': operation('Start local MLX physical extraction; preserve details on stale source/failure.', 'characters', ['characterID'], { characterID: string }),
  'images.prepare': operation('Prepare the exact outgoing prompt and selected reference versions, without sending it.', 'source', ['targetKind', 'targetID', 'prompt'], {
    targetKind: { enum: ['shot', 'character'] }, targetID: string, prompt: string,
    references: { type: 'array', maxItems: 8, items: { type: 'object', additionalProperties: false, required: ['characterID', 'versionID'], properties: { characterID: string, versionID: string } } },
  }),
  'images.export': operation('Export the prepared payload and reference paths for an external image tool.', 'none', ['jobID'], { jobID: string }),
  'images.submit': operation('Queue an exact payload for native user approval; never approve it through the wire API.', 'source', ['jobID', 'agent'], { jobID: string, agent: { enum: ['codex', 'claude', 'grok', 'cursor'] } }),
  'images.import': operation('Validate/copy an external raster result; stale results are retained for review.', 'source', ['jobID', 'path'], { jobID: string, path: string }),
  'images.attach': operation('Attach a retained result; stale inputs require explicit acknowledgement.', 'source', ['jobID'], { jobID: string, acknowledgeStale: boolean }),
  'images.list': operation('Read storyboard version history and active versions.', 'none'),
  'images.agents': operation('Inspect configured agent generation/reference-edit capabilities without invoking a provider.', 'none'),
  'images.select': operation('Select an existing storyboard or character image version.', 'source', ['versionID'], { versionID: string, targetKind: { enum: ['shot', 'character'] }, targetID: string }),
  'jobs.list': operation('List durable generation jobs.', 'none'),
  'jobs.status': operation('Inspect job status and retained result paths.', 'none', ['jobID'], { jobID: string }),
  'jobs.cancel': operation('Cancel a job without promising provider billing cancellation.', 'none', ['jobID'], { jobID: string }, true),
  'jobs.retry': operation('Prepare a new image attempt; paid requests require fresh approval. Local jobs use their original generate/extract operation.', 'none', ['jobID'], { jobID: string }, true),
};

export const contract = {
  version: 1,
  protocol: 'One UTF-8 JSON request and response, each newline terminated, per Unix socket connection. Maximum request: 4 MiB.',
  requestSchema: {
    $schema: 'https://json-schema.org/draft/2020-12/schema', type: 'object', additionalProperties: false,
    required: ['version', 'requestID', 'operation', 'parameters'],
    properties: {
      version: { const: 1 }, requestID: { type: 'string', minLength: 1, maxLength: 128 },
      operation: { enum: Object.keys(operations) }, documentID: string, expectedRevision: string, parameters: { type: 'object' },
    },
  },
  responseSchema: {
    type: 'object', required: ['version', 'requestID', 'operation', 'ok'],
    properties: { version: { const: 1 }, requestID: { type: ['string', 'null'] }, operation: { type: ['string', 'null'] }, ok: boolean, result: {}, error: { type: 'object', required: ['code', 'message', 'retryable'], properties: { code: string, message: string, retryable: boolean } } },
  },
  operations,
};

if (import.meta.main) {
  const destination = fileURLToPath(new URL('../Sources/ActCore/Resources/automation-v1.json', import.meta.url));
  const data = JSON.stringify(contract, null, 2) + '\n';
  if (process.argv.includes('--check')) {
    if (readFileSync(destination, 'utf8') !== data) throw new Error('Regenerate native contract: bun CLI/contract.ts --write');
  } else if (process.argv.includes('--write')) writeFileSync(destination, data);
  else process.stdout.write(data);
}
