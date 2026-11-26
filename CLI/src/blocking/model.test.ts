import { test, expect } from 'bun:test';
import { BlockingWorkspace, copy, decodePlan, encodePlan, restoreSession, reviewLayout, stale, validatePlan, type SceneInput, type Layout } from './model';
import { generate } from './generate';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
export const scene: SceneInput = { sceneID: 'kitchen', heading: 'INT. KITCHEN - DAY', source: 'Mara waits by a table.', shots: [
  { id: 'wide', sceneID: 'kitchen', framing: 'Wide', action: 'Mara by the table.', cameraMovement: 'Static', rationale: 'Geography' },
  { id: 'close', sceneID: 'kitchen', framing: 'Close-up', action: 'Mara listens.', cameraMovement: 'Static', rationale: 'Reaction' },
] };
export const layout: Layout = { items: [
  { id: 'mara', kind: 'actor', label: 'Mara', x: 420, y: 180, width: 30, height: 30, inferred: true },
  { id: 'table', kind: 'set', label: 'Table', x: 480, y: 230, width: 160, height: 80, inferred: true },
], overlays: scene.shots.map(shot => ({ shotID: shot.id, camera: { x: 100, y: 450 }, target: { x: 435, y: 195 }, cameraEnd: null, actors: [], warning: '' })), notes: 'Proposed positions. No measurements supplied.' };
const workspace = () => new BlockingWorkspace(copy(scene));
function acceptInitial(w: BlockingWorkspace) { w.receive(copy(layout), w.begin()); w.accept(); }

test('draft rejection, acceptance, edits, shot selection data and reopen preserve separate source', () => {
  const w = workspace(), original = JSON.stringify(w.scene);
  const request = w.begin(); w.receive(copy(layout), request);
  expect(w.session.plan).toBeNull(); w.reject(); expect(w.visible).toBeNull();
  w.receive(copy(layout), request); w.accept();
  w.edit(p => { p.layout.items[0]!.x = 300; p.layout.overlays[1]!.camera.x = 700; });
  const reopened = decodePlan(encodePlan(w.session.plan!), scene.sceneID);
  expect(reopened.layout.items[0]!.x).toBe(300);
  expect(reopened.layout.overlays[0]!.camera.x).toBe(100);
  expect(reopened.layout.overlays[1]!.camera.x).toBe(700);
  expect(JSON.stringify(w.scene)).toBe(original);
  expect(w.session.dirty).toBe(true);
});

test('changed inputs or manual edits during inference prevent draft acceptance', () => {
  const w = workspace(); acceptInitial(w);
  const request = w.begin(), accepted = copy(w.session.plan);
  w.edit(p => { p.layout.items[0]!.label = 'User correction'; });
  w.receive(copy(layout), request);
  expect(w.canAccept).toBe(false); expect(() => w.accept()).toThrow('changed');
  w.undo(); w.redo();
  expect(w.canAccept).toBe(false);
  expect(w.session.plan!.layout.items[0]!.label).toBe('User correction');
  w.reject(); expect(w.session.plan).not.toEqual(accepted);
  const fresh = w.begin(); w.scene.shots[0]!.action = 'Changed'; w.receive(copy(layout), fresh);
  expect(w.canAccept).toBe(false); expect(stale(w.session.plan!, w.scene)).toBe(true);
});

test('missing, duplicate and regenerated shot IDs cannot silently remap overlays', () => {
  const w = workspace(); acceptInitial(w); const bytes = encodePlan(w.session.plan!);
  const duplicate = copy(layout); duplicate.overlays[1]!.shotID = duplicate.overlays[0]!.shotID;
  expect(() => w.receive(duplicate, w.begin())).toThrow('Duplicate');
  const missing = copy(layout); missing.overlays.pop();
  expect(() => w.receive(missing, w.begin())).toThrow('Every shot');
  w.scene.shots[0]!.id = 'new-id'; expect(stale(w.session.plan!, w.scene)).toBe(true);
  expect(encodePlan(w.session.plan!)).toBe(bytes);
});

test('invalid and future files fail without touching accepted work', () => {
  const w = workspace(); acceptInitial(w); const original = encodePlan(w.session.plan!);
  const future = JSON.parse(original); future.version = 2;
  expect(() => decodePlan(JSON.stringify(future), scene.sceneID)).toThrow('Unsupported');
  const outside = JSON.parse(original); outside.layout.items[0].x = 2000;
  expect(() => validatePlan(outside)).toThrow();
  const badActor = JSON.parse(original); badActor.layout.overlays[0].actors = [{ actorID: 'ghost', x: 0, y: 0, end: null }];
  expect(() => validatePlan(badActor)).toThrow('unknown actor');
  expect(() => decodePlan(original, 'other-scene')).toThrow('another scene');
  expect(encodePlan(w.session.plan!)).toBe(original);
});

test('recovery retains draft and manual work; undo and redo retain provenance', () => {
  const w = workspace(); acceptInitial(w);
  w.edit(p => { p.layout.items[0]!.inferred = false; p.layout.items[0]!.x = 200; });
  w.undo(); expect(w.visible!.layout.items[0]!.x).toBe(420);
  w.redo(); expect(w.visible!.layout.items[0]!.x).toBe(200);
  w.receive(copy(layout), w.begin());
  const recovered = restoreSession(JSON.stringify(w.session), scene.sceneID);
  expect(recovered.plan!.layout.items[0]!.inferred).toBe(false);
  expect(recovered.draft!.plan.layout.items[0]!.inferred).toBe(true);
  const r = workspace(); r.session = recovered; expect(r.canAccept).toBe(true);
  r.edit(p => { p.layout.items[0]!.x = 330; }); expect(r.canAccept).toBe(true); r.accept();
  expect(r.visible!.layout.items[0]!.x).toBe(330);
});

test('references remain embedded and changing notes invalidates an existing draft', () => {
  const w = workspace();
  const refs = [{ id: 'floor', name: 'Kitchen.png', dataURL: 'data:image/png;base64,YWJj', notes: 'Door on left.' }];
  w.setReferences(refs); w.receive(copy(layout), w.begin());
  w.setReferences([{ ...refs[0]!, notes: 'Door on right.' }]);
  expect(w.canAccept).toBe(false);
  expect(() => w.accept()).toThrow();
});

test('removing every shot invalidates pending work while retaining its original layout', () => {
  const w = workspace(); acceptInitial(w);
  const before = encodePlan(w.session.plan!), request = w.begin();
  w.scene.shots = []; w.receive(copy(layout), request);
  expect(w.canAccept).toBe(false);
  expect(() => w.accept()).toThrow();
  expect(stale(w.session.plan!, w.scene)).toBe(true);
  expect(encodePlan(w.session.plan!)).toBe(before);
  w.reject(); expect(() => w.begin()).toThrow('shot list');
});

test('spatial warnings flag camera obstructions and wrong subjects without correcting geometry', () => {
  const input = copy(scene), spatial = copy(layout);
  spatial.items.push({ id: 'joel', kind: 'actor', label: 'Joel', x: 100, y: 100, width: 30, height: 30, inferred: true });
  spatial.overlays[1]!.camera = { x: 520, y: 260 };
  spatial.overlays[1]!.target = { x: 115, y: 115 };
  const reviewed = reviewLayout(spatial, input);
  expect(reviewed.overlays[1]!.warning).toContain('inside Table');
  expect(reviewed.overlays[1]!.warning).toContain('nearer Joel than Mara');
  expect(reviewed.overlays[1]!.camera).toEqual(spatial.overlays[1]!.camera);
  expect(spatial.overlays[1]!.warning).toBe('');
});

test('real subprocess boundary supports offline flags, failures and cancellation', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'act-blocking-test-'));
  try {
    const runtime = join(dir, 'runtime'), model = join(dir, 'model.gguf');
    await writeFile(model, 'GGUFfixture');
    const geography = { items: layout.items.map(({ id, inferred, ...item }) => item), notes: layout.notes };
    const cameras = Object.fromEntries(layout.overlays.map(({ shotID, actors, ...o }, index) => [`S${index + 1}`, { ...o, actors: {} }]));
    const first = join(dir, 'geography.json'), second = join(dir, 'overlays.json');
    await writeFile(first, JSON.stringify(geography)); await writeFile(second, JSON.stringify(cameras));
    await writeFile(runtime, `#!/bin/sh
case " $* " in *" --offline "*) ;; *) exit 42;; esac
case "$*" in *geography*) cat '${first}' ;; *) cat '${second}' ;; esac
`, { mode: 0o700 });
    const result = await generate({ runtime, model, scene, references: [] });
    expect(result.items.map(i => i.id)).toEqual(['actor-1', 'set-2']);
    expect(result.overlays.map(o => o.shotID)).toEqual(scene.shots.map(s => s.id));
    expect(result.overlays.every(o => o.actors.some(a => a.actorID === 'actor-1'))).toBe(true);
    await writeFile(runtime, '#!/bin/sh\nprintf \'not a plan\'\n', { mode: 0o700 });
    await expect(generate({ runtime, model, scene, references: [] })).rejects.toThrow('no complete');
    await writeFile(runtime, '#!/bin/sh\nexit 7\n', { mode: 0o700 });
    await expect(generate({ runtime, model, scene, references: [] })).rejects.toThrow('failed (7)');
    await writeFile(runtime, '#!/bin/sh\nsleep 30\n', { mode: 0o700 });
    const abort = new AbortController();
    const pending = generate({ runtime, model, scene, references: [] }, abort.signal);
    setTimeout(() => abort.abort(), 100);
    await expect(pending).rejects.toThrow('cancelled');
  } finally { await rm(dir, { recursive: true, force: true }); }
});
