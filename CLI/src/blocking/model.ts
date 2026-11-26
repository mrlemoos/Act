export type Point = { x: number; y: number };
export type Shot = { id: string; sceneID: string; framing: string; action: string; cameraMovement: string; rationale: string };
export type SceneInput = { sceneID: string; heading: string; source: string; shots: Shot[] };
export type Reference = { id: string; name: string; dataURL: string; notes: string };
export type Item = Point & { id: string; kind: 'actor' | 'set'; label: string; width: number; height: number; inferred: boolean; facing?: number };
export type ActorPosition = Point & { actorID: string; end: Point | null; facing?: number };
export type Overlay = { shotID: string; camera: Point; target: Point; cameraEnd: Point | null; actors: ActorPosition[]; warning: string };
export type Layout = { items: Item[]; overlays: Overlay[]; notes: string };
export type Plan = { version: 1; scene: SceneInput; references: Reference[]; layout: Layout };
export type Draft = { plan: Plan; inputKey: string; revision: number };
export type Session = { plan: Plan | null; draft: Draft | null; references: Reference[]; revision: number; dirty: boolean };
export const emptySession = (): Session => ({ plan: null, draft: null, references: [], revision: 0, dirty: false });
export const copy = <T>(value: T): T => structuredClone(value);
export const sceneKey = (scene: SceneInput): string => JSON.stringify(scene);
// Images are immutable reference assets. Replacing one creates a new ID; every
// reference edit separately advances the workspace revision.
export const generationKey = (scene: SceneInput, references: Reference[]): string => JSON.stringify([scene, references.map(({ id, name, notes }) => ({ id, name, notes }))]);
export const stale = (plan: Plan, scene: SceneInput): boolean => sceneKey(plan.scene) !== sceneKey(scene);
export const clamp = (n: number, max: number): number => Math.max(0, Math.min(max, n));

function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Expected an object.');
  return value as Record<string, unknown>;
}
function text(value: unknown, limit = 2000): string {
  if (typeof value !== 'string' || value.length > limit) throw new Error('Invalid or oversized text.');
  return value;
}
function array(value: unknown, limit: number): unknown[] {
  if (!Array.isArray(value) || value.length > limit) throw new Error('Invalid or oversized collection.');
  return value;
}
function number(value: unknown, max: number): number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > max) throw new Error('Geometry is outside the plan.');
  return value;
}
function identifier(value: unknown): string {
  const result = text(value, 160);
  if (!result.trim()) throw new Error('Missing identifier.');
  return result;
}
function unique(values: string[]): void {
  if (new Set(values).size !== values.length) throw new Error('Duplicate identifiers.');
}
export function point(value: unknown): Point {
  const v = object(value);
  return { x: number(v.x, 1000), y: number(v.y, 600) };
}
export function validateScene(value: unknown): SceneInput {
  const v = object(value);
  const sceneID = identifier(v.sceneID);
  const shots = array(v.shots, 64).map(raw => {
    const s = object(raw);
    if (s.sceneID !== sceneID) throw new Error('A shot belongs to another scene.');
    return { id: identifier(s.id), sceneID, framing: text(s.framing), action: text(s.action, 12000), cameraMovement: text(s.cameraMovement), rationale: text(s.rationale, 12000) };
  });
  unique(shots.map(s => s.id));
  return { sceneID, heading: text(v.heading), source: text(v.source, 32000), shots };
}
export function validateReferences(value: unknown): Reference[] {
  const refs = array(value, 4).map(raw => {
    const r = object(raw);
    const dataURL = text(r.dataURL, 2_800_000);
    if (!/^data:image\/(png|jpeg);base64,[A-Za-z0-9+/]+=*$/.test(dataURL)) throw new Error('References must be embedded PNG or JPEG images.');
    return { id: identifier(r.id), name: text(r.name, 300), notes: text(r.notes, 4000), dataURL };
  });
  unique(refs.map(r => r.id));
  if (refs.reduce((size, r) => size + r.dataURL.length, 0) > 5_400_000) throw new Error('References exceed the combined 4 MB limit. Use smaller images.');
  return refs;
}
export function validateLayout(value: unknown, scene: SceneInput): Layout {
  const v = object(value);
  const items: Item[] = array(v.items, 48).map(raw => {
    const i = object(raw);
    if (i.kind !== 'actor' && i.kind !== 'set') throw new Error('Unknown plan symbol.');
    if (typeof i.inferred !== 'boolean') throw new Error('Missing geography provenance.');
    const p = point(i), width = number(i.width, 1000), height = number(i.height, 600);
    if (width < 10 || height < 10 || p.x + width > 1000 || p.y + height > 600) throw new Error('A symbol extends beyond the plan.');
    return { ...p, id: identifier(i.id), kind: i.kind, label: text(i.label, 120), width, height, inferred: i.inferred, ...(i.facing === undefined ? {} : { facing: number(i.facing, 360) }) };
  });
  unique(items.map(i => i.id));
  const actorIDs = new Set(items.filter(i => i.kind === 'actor').map(i => i.id));
  const shotIDs = new Set(scene.shots.map(s => s.id));
  const overlays = array(v.overlays, 64).map(raw => {
    const o = object(raw);
    const shotID = identifier(o.shotID);
    if (!shotIDs.has(shotID)) throw new Error('An overlay refers to an unknown shot.');
    const actors = array(o.actors, 48).map(rawActor => {
      const a = object(rawActor);
      const actorID = identifier(a.actorID);
      if (!actorIDs.has(actorID)) throw new Error('An overlay refers to an unknown actor.');
      return { actorID, ...point(a), end: a.end === null ? null : point(a.end), ...(a.facing === undefined ? {} : { facing: number(a.facing, 360) }) };
    });
    unique(actors.map(a => a.actorID));
    return { shotID, camera: point(o.camera), target: point(o.target), cameraEnd: o.cameraEnd === null ? null : point(o.cameraEnd), actors, warning: text(o.warning) };
  });
  unique(overlays.map(o => o.shotID));
  if (overlays.length !== scene.shots.length) throw new Error('Every shot needs exactly one overlay.');
  return { items, overlays, notes: text(v.notes, 4000) };
}
export function validatePlan(value: unknown): Plan {
  const v = object(value);
  if (v.version !== 1) throw new Error('Unsupported blocking-plan version. Existing files have not been changed.');
  const scene = validateScene(v.scene);
  return { version: 1, scene, references: validateReferences(v.references), layout: validateLayout(v.layout, scene) };
}
export function decodePlan(source: string, sceneID: string): Plan {
  if (source.length > 12_000_000) throw new Error('Plan exceeds the 12 MB limit.');
  const plan = validatePlan(JSON.parse(source));
  if (plan.scene.sceneID !== sceneID) throw new Error('This plan belongs to another scene. Open that scene before loading it.');
  return plan;
}
export function encodePlan(plan: Plan): string { return JSON.stringify(validatePlan(plan), null, 2); }
export function restoreSession(source: string, sceneID: string): Session {
  const v = object(JSON.parse(source));
  const plan = v.plan === null ? null : validatePlan(v.plan);
  const references = validateReferences(v.references);
  const revision = number(v.revision, Number.MAX_SAFE_INTEGER);
  let draft: Draft | null = null;
  if (v.draft !== null) {
    const d = object(v.draft);
    draft = { plan: validatePlan(d.plan), inputKey: text(d.inputKey, 12_000_000), revision: number(d.revision, Number.MAX_SAFE_INTEGER) };
  }
  if ((plan && plan.scene.sceneID !== sceneID) || (draft && draft.plan.scene.sceneID !== sceneID)) throw new Error('Recovery belongs to another scene.');
  if (typeof v.dirty !== 'boolean') throw new Error('Invalid recovery state.');
  return { plan, draft, references, revision, dirty: v.dirty };
}

export class BlockingWorkspace {
  session: Session = emptySession();
  scene: SceneInput;
  private history: Session[] = [];
  private future: Session[] = [];
  constructor(scene: SceneInput) { this.scene = validateScene(scene); }
  get visible(): Plan | null { return this.session.draft?.plan ?? this.session.plan; }
  get canAccept(): boolean {
    const d = this.session.draft;
    return !!d && d.inputKey === generationKey(this.scene, this.session.references) && d.revision === this.session.revision;
  }
  private checkpoint(): void {
    this.history.push(copy(this.session));
    if (this.history.length > 20) this.history.shift();
    this.future = [];
  }
  begin(): { scene: SceneInput; references: Reference[]; revision: number; inputKey: string } {
    if (!this.scene.shots.length) throw new Error('Create a shot list for this scene first.');
    if (this.session.draft) throw new Error('Accept or reject the current draft before generating another.');
    return { scene: copy(this.scene), references: copy(this.session.references), revision: this.session.revision, inputKey: generationKey(this.scene, this.session.references) };
  }
  receive(layout: unknown, request: ReturnType<BlockingWorkspace['begin']>): void {
    const plan = validatePlan({ version: 1, scene: request.scene, references: request.references, layout });
    // Generated provenance cannot claim a location was measured or user-confirmed.
    plan.layout.items.forEach(item => { item.inferred = true; });
    this.checkpoint();
    this.session.draft = { plan, inputKey: request.inputKey, revision: request.revision };
  }
  accept(): void {
    if (!this.canAccept) throw new Error('Inputs or accepted plan changed. Reject this draft and generate again.');
    this.checkpoint();
    this.session.plan = copy(this.session.draft!.plan);
    this.session.draft = null;
    this.session.dirty = true;
    this.session.revision++;
  }
  reject(): void { this.checkpoint(); this.session.draft = null; }
  edit(change: (plan: Plan) => void): void {
    if (!this.visible) return;
    const changed = copy(this.visible);
    change(changed);
    const valid = validatePlan(changed);
    this.checkpoint();
    if (this.session.draft) this.session.draft.plan = valid;
    else { this.session.plan = valid; this.session.dirty = true; this.session.revision++; }
  }
  setReferences(refs: Reference[]): void {
    const valid = validateReferences(refs);
    this.checkpoint();
    this.session.references = valid;
    if (this.session.plan && !this.session.draft) {
      this.session.plan.references = copy(valid);
      this.session.dirty = true;
    }
    this.session.revision++;
  }
  load(plan: Plan): void {
    const valid = validatePlan(plan);
    if (valid.scene.sceneID !== this.scene.sceneID) throw new Error('Plan belongs to another scene.');
    this.session = { plan: valid, draft: null, references: copy(valid.references), revision: this.session.revision + 1, dirty: false };
    this.history = []; this.future = [];
  }
  undo(): void {
    const previous = this.history.pop();
    if (!previous) return;
    this.future.push(copy(this.session));
    const revision = this.session.revision + 1;
    const draftWasCurrent = previous.draft?.revision === previous.revision;
    this.session = previous; this.session.revision = revision;
    // Undoing a visible edit to a draft preserves its original input guard.
    if (draftWasCurrent && this.session.draft && generationKey(this.scene, this.session.references) === this.session.draft.inputKey) this.session.draft.revision = revision;
    if (this.session.plan) this.session.dirty = true;
  }
  redo(): void {
    const next = this.future.pop();
    if (!next) return;
    this.history.push(copy(this.session));
    const revision = this.session.revision + 1;
    const draftWasCurrent = next.draft?.revision === next.revision;
    this.session = next; this.session.revision = revision;
    if (draftWasCurrent && this.session.draft && generationKey(this.scene, this.session.references) === this.session.draft.inputKey) this.session.draft.revision = revision;
    if (this.session.plan) this.session.dirty = true;
  }
}

/** Flags observable spatial problems without silently correcting the director's choices. */
export function reviewLayout(layout: Layout, scene: SceneInput): Layout {
  const result = copy(layout);
  const actors = result.items.filter(i => i.kind === 'actor');
  let previousSide = 0;
  for (const [index, shot] of scene.shots.entries()) {
    const o = result.overlays.find(v => v.shotID === shot.id);
    if (!o) continue;
    const warnings = o.warning ? [o.warning] : [];
    const positions = actors.map(actor => ({ label: actor.label, ...(o.actors.find(a => a.actorID === actor.id) ?? { x: actor.x + actor.width / 2, y: actor.y + actor.height / 2 }) }));
    if (Math.hypot(o.camera.x - o.target.x, o.camera.y - o.target.y) < 10) warnings.push('Camera and aim overlap. Review view direction.');
    for (const item of result.items.filter(i => i.kind === 'set' && !/^(room|floor|kitchen|hall|courtyard|street|location)( plan)?$/i.test(i.label))) {
      if (o.camera.x > item.x && o.camera.x < item.x + item.width && o.camera.y > item.y && o.camera.y < item.y + item.height) warnings.push(`Camera is inside ${item.label}. Review placement.`);
    }
    const named = positions.filter(actor => {
      const name = actor.label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      return new RegExp(`(?<![\\p{L}\\p{N}])${name}(?![\\p{L}\\p{N}])`, 'iu').test(shot.action);
    });
    if (named.length === 1 && positions.length > 1) {
      const subject = named[0]!, distance = (p: Point) => Math.hypot(p.x - o.target.x, p.y - o.target.y);
      const nearest = [...positions].sort((a, b) => distance(a) - distance(b))[0]!;
      if (nearest.label !== subject.label && distance(nearest) + 30 < distance(subject)) warnings.push(`Aim is nearer ${nearest.label} than ${subject.label}. Check the intended subject.`);
    }
    if (positions.length === 2) {
      const [a, b] = positions as [typeof positions[number], typeof positions[number]];
      const side = (b.x - a.x) * (o.camera.y - a.y) - (b.y - a.y) * (o.camera.x - a.x);
      if (Math.abs(side) > 100) {
        if (previousSide && Math.sign(side) !== Math.sign(previousSide)) warnings.push(`Camera crosses the actor axis from shot ${index}. Check screen direction.`);
        previousSide = side;
      }
    }
    o.warning = warnings.join(' ').slice(0, 2000);
  }
  return result;
}
