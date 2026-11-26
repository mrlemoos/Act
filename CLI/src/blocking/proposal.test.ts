import { test, expect } from 'bun:test';
import { prepareGeography, prepareCameras } from './proposal';
import { BlockingWorkspace, decodePlan, encodePlan, type Layout, type SceneInput } from './model';
const scene: SceneInput = { sceneID: 'kitchen', heading: 'INT. KITCHEN - DAY', source: 'MARA waits at a table. JOEL stands opposite her.', shots: [
  { id: 'one', sceneID: 'kitchen', framing: 'Close-up', action: 'Mara listens.', cameraMovement: 'Static', rationale: '' },
] };
const layout: Layout = { items: [
  { id: 'mara', kind: 'actor', label: 'Mara', x: 400, y: 250, width: 30, height: 30, inferred: true },
  { id: 'joel', kind: 'actor', label: 'Joel', x: 410, y: 250, width: 30, height: 30, inferred: true },
  { id: 'table', kind: 'set', label: 'Table', x: 400, y: 250, width: 30, height: 30, inferred: true },
], overlays: [{ shotID: 'one', camera: { x: 410, y: 260 }, target: { x: 430, y: 265 }, cameraEnd: null, actors: [], warning: '' }], notes: 'Inferred geography.' };

test('new proposals place distinct people beside furniture with clear camera space', () => {
  const original = JSON.stringify(layout);
  const result = prepareCameras(prepareGeography(layout), scene);
  const table = result.items.find(i => i.id === 'table')!;
  const actors = result.overlays[0]!.actors;
  expect(table.width >= 150 && table.height >= 90).toBe(true);
  for (const person of [...actors, result.overlays[0]!.camera]) {
    expect(person.x < table.x - 35 || person.x > table.x + table.width + 35 || person.y < table.y - 35 || person.y > table.y + table.height + 35).toBe(true);
  }
  expect(Math.hypot(actors[0]!.x - actors[1]!.x, actors[0]!.y - actors[1]!.y)).toBeGreaterThanOrEqual(76);
  const mara = actors.find(a => a.actorID === 'mara')!;
  expect(result.overlays[0]!.target).toEqual({ x: mara.x, y: mara.y });
  expect(JSON.stringify(layout)).toBe(original);
});

test('turning a person persists per shot, survives reopen and remains undoable', () => {
  const workspace = new BlockingWorkspace(scene);
  workspace.receive(prepareCameras(prepareGeography(layout), scene), workspace.begin()); workspace.accept();
  workspace.edit(p => { p.layout.overlays[0]!.actors[0]!.facing = 135; });
  const plan = decodePlan(encodePlan(workspace.session.plan!), scene.sceneID);
  expect(plan.layout.overlays[0]!.actors[0]!.facing).toBe(135);
  workspace.undo(); expect(workspace.visible!.layout.overlays[0]!.actors[0]!.facing).toBeUndefined();
  workspace.redo(); expect(workspace.visible!.layout.overlays[0]!.actors[0]!.facing).toBe(135);
});

test('a described left-door entrance supplies its missing set piece and positions the entering character there', () => {
  const entryScene = structuredClone(scene); entryScene.shots[0]!.framing = 'Wide';
  entryScene.shots[0]!.action = 'Mara waits by the table. Joel enters through the left door.';
  const result = prepareCameras(prepareGeography(layout, entryScene), entryScene);
  const door = result.items.find(i => /door/i.test(i.label))!;
  expect(door.x).toBe(25);
  const joel = result.overlays[0]!.actors.find(a => a.actorID === 'joel')!;
  expect(joel.x).toBeLessThan(door.x + 150);
  expect(joel.y).toBe(300);
  const o = result.overlays[0]!;
  for (const a of o.actors) expect((a.x - o.camera.x) * (o.target.x - o.camera.x) + (a.y - o.camera.y) * (o.target.y - o.camera.y)).toBeGreaterThan(0);
});
