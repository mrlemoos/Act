import { BlockingWorkspace, copy, decodePlan, encodePlan, restoreSession, stale, clamp, validateScene, type Plan, type Point, type Reference } from './model';
import { renderPlan, escape, actorPosition, actorFacing, facingHandle } from './render';

type Context = { scene: unknown; runtime: string | null; model: string | null; recovery: string | null; initialError?: string };
type Host = { messageHandlers: { blocking: { postMessage(value: unknown): void } } };
declare global { interface Window { webkit?: Host; blocking: { start(context: Context): void; update(scene: unknown): void; invalidate(message: string): void; reply(id: string, value: unknown, error?: string): void } } }
const element = <T extends HTMLElement = HTMLElement>(id: string): T => document.getElementById(id) as T;
const button = (id: string) => element<HTMLButtonElement>(id);
let workspace: BlockingWorkspace;
let configuration: Context;
let selectedShot = '', selected = '', showReference = true, actorScope = 'shot';
let busy = false;
let referencesOpen = false;
let activeGeneration = 0;
let drag: { start: Point; key: string; before: Plan; preview: Plan } | null = null;
const pending = new Map<string, { resolve(value: any): void; reject(error: Error): void }>();
function host<T = any>(action: string, payload: unknown = {}): Promise<T> {
  const id = crypto.randomUUID();
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject });
    if (!window.webkit) { pending.delete(id); reject(new Error('Open this editor inside Act to use file and generation tools.')); return; }
    window.webkit.messageHandlers.blocking.postMessage({ id, action, payload });
  });
}
function error(e: unknown): void { element('error').textContent = e instanceof Error ? e.message : String(e); }
function attempt(action: () => void | Promise<void>): void {
  element('error').textContent = '';
  try { Promise.resolve(action()).catch(error); } catch (e) { error(e); }
}
function persist(): void {
  void host('recovery', { state: JSON.stringify(workspace.session), dirty: workspace.session.dirty || !!workspace.session.draft || (!workspace.session.plan && workspace.session.references.length > 0) }).catch(error);
}
function changed(): void { render(); persist(); }
function displayPlan(): Plan | null { return workspace?.visible ?? null; }
function overlay(plan: Plan) { return plan.layout.overlays.find(o => o.shotID === selectedShot); }
function chooseShot(): void {
  const shots = displayPlan()?.scene.shots ?? workspace.scene.shots;
  if (!shots.some(s => s.id === selectedShot)) selectedShot = shots[0]?.id ?? '';
}
function render(): void {
  if (!workspace) return;
  chooseShot();
  const plan = displayPlan();
  element('heading').textContent = workspace.scene.heading;
  const shotSelect = element<HTMLSelectElement>('shot');
  shotSelect.innerHTML = (plan?.scene.shots ?? workspace.scene.shots).map((s, i) => `<option value="${escape(s.id)}">${String(i + 1).padStart(2, '0')} · ${escape(s.framing)} · ${escape(s.action.slice(0, 60))}${plan?.layout.overlays.find(o => o.shotID === s.id)?.warning ? ' · Review direction' : ''}</option>`).join('');
  shotSelect.value = selectedShot;
  const isStale = plan ? stale(plan, workspace.scene) : false;
  const conflicts = plan?.layout.overlays.filter(o => o.warning).length ?? 0;
  element('notice').textContent = isStale ? 'Scene or shot list changed. This plan retains its original shot associations. Review it and explicitly regenerate when ready.' : workspace.session.draft ? 'Draft proposal. Review inferred geography and camera directions before accepting.' : '';
  if (conflicts) element('notice').textContent += ` ${conflicts} shot direction${conflicts === 1 ? '' : 's'} need review.`;
  element('progress').textContent = busy ? 'Planning locally…' : workspace.session.dirty ? 'Unsaved plan' : '';
  button('generate').disabled = busy || !!workspace.session.draft || !workspace.scene.shots.length;
  button('start').disabled = busy || !workspace.scene.shots.length;
  button('generate').textContent = plan ? 'Regenerate draft' : 'Generate draft';
  button('cancel').hidden = !busy;
  button('save').disabled = !workspace.session.plan || !!workspace.session.draft;
  button('open').disabled = busy;
  button('exportPNG').disabled = !plan || busy;
  button('exportPDF').disabled = !plan || busy;
  element('empty').hidden = !!plan;
  element('canvas').hidden = !plan;
  element('hint').hidden = !plan;
  element('review').innerHTML = workspace.session.draft ? `<div class="review"><span>${workspace.canAccept ? 'Review draft. Accept replaces this scene’s plan.' : 'Inputs changed. Reject this draft and generate again.'}</span><button id="reject">Reject</button><button id="accept" class="primary" ${workspace.canAccept ? '' : 'disabled'}>Accept draft</button></div>` : '';
  button('accept')?.addEventListener('click', () => attempt(() => { workspace.accept(); changed(); }));
  button('reject')?.addEventListener('click', () => { workspace.reject(); selected = ''; changed(); });
  paint(); inspector(); references(); cast();
}
function paint(preview?: Plan): void {
  const plan = preview ?? displayPlan();
  if (plan) element('canvas').innerHTML = renderPlan(plan, selectedShot, selected, showReference, workspace.session.draft ? 'DRAFT · Inferred geography. Review before acceptance.' : stale(plan, workspace.scene) ? 'REVIEW REQUIRED · Scene or shot list changed. Original layout retained.' : '', true);
}
function field(label: string, key: string, value: string | number, type = 'text', max?: number): string {
  return `<label>${label}<input data-field="${key}" type="${type}" value="${escape(String(value))}" ${type === 'number' ? `min="0" max="${max ?? 1000}" step="1"` : 'maxlength="120"'}></label>`;
}
function panelState(): void {
  document.body.classList.toggle('properties-open', !!selected || referencesOpen);
  element('referencePanel').hidden = !referencesOpen;
  element('inspector').hidden = !selected;
}
function cast(): void {
  const plan = displayPlan();
  element('cast').innerHTML = plan ? plan.layout.items.filter(i => i.kind === 'actor').map(i => `<button class="cast-person ${selected === `item:${i.id}` ? 'active' : ''}" data-select="${escape(i.id)}"><svg viewBox="0 0 20 20" aria-hidden="true"><circle cx="10" cy="5" r="3"/><path d="M4 17 V13 Q4 9 10 9 Q16 9 16 13 V17"/></svg>${escape(i.label)}</button>`).join('') : '';
  button('placeActor').disabled = !plan;
  button('placeTable').disabled = !plan;
}
function inspector(): void {
  panelState();
  const plan = displayPlan(), o = plan ? overlay(plan) : undefined;
  if (!plan || !selected) { element('inspector').innerHTML = ''; return; }
  const item = plan.layout.items.find(i => `item:${i.id}` === selected || `facing:${i.id}` === selected);
  const selectedTitle = item?.label ?? (selected === 'cameraEnd' ? 'Camera movement' : selected === 'camera' || selected === 'cameraFacing' || selected === 'target' ? 'Camera' : 'Movement');
  let fields = `<div class="inspector-title"><strong>${escape(selectedTitle)}</strong><button id="closeProperties" aria-label="Close properties">×</button></div>`;
  if (item) {
    const p = item.kind === 'actor' && actorScope === 'shot' ? actorPosition(item, o) : item;
    fields += `${field('Name', 'label', item.label)}${item.kind === 'actor' ? `<label>Position in<select id="actorScope"><option value="shot" ${actorScope === 'shot' ? 'selected' : ''}>This shot</option><option value="shared" ${actorScope === 'shared' ? 'selected' : ''}>Shared scene</option></select></label><label>Facing <output id="facingValue">${Math.round(actorFacing(item, plan, o))}°</output><input id="facing" type="range" min="0" max="359" value="${actorFacing(item, plan, o)}"></label>` : ''}<details><summary>Position and size</summary><div class="row">${field('X', 'x', p.x, 'number')}${field('Y', 'y', p.y, 'number', 600)}</div>${item.kind === 'set' ? `<div class="row">${field('Width', 'width', item.width, 'number')}${field('Depth', 'height', item.height, 'number', 600)}</div>` : ''}<label class="check"><input type="checkbox" data-field="confirmed" ${!item.inferred ? 'checked' : ''}>Position confirmed</label></details><div class="row">${item.kind === 'actor' ? '<button id="actorMovement">Movement path</button>' : ''}<button id="removeItem">Remove</button></div>`;
  } else if (o) {
    const p = selected === 'cameraEnd' ? o.cameraEnd : o.camera;
    fields += `<p class="small">${escape(plan.scene.shots.find(s => s.id === selectedShot)?.framing ?? '')}</p><p class="small">Drag the camera to move. Pull its small handle to aim.</p><button id="cameraMovement">Movement path</button>${p ? `<details><summary>Position</summary><div class="row">${field('X', 'x', p.x, 'number')}${field('Y', 'y', p.y, 'number', 600)}</div></details>` : ''}`;
  }
  if (o?.warning) fields += `<p class="direction-warning">${escape(o.warning)}</p>`;
  element('inspector').innerHTML = fields;
  button('closeProperties')?.addEventListener('click', () => { selected = ''; paint(); inspector(); cast(); });
  element('actorScope')?.addEventListener('change', event => { actorScope = (event.target as HTMLSelectElement).value; inspector(); });
  element<HTMLInputElement>('facing')?.addEventListener('input', event => {
    const value = Number((event.target as HTMLInputElement).value), preview = copy(plan);
    if (item) { turnActor(preview, item.id, value); paint(preview); element('facingValue').textContent = `${Math.round(value)}°`; }
  });
  element<HTMLInputElement>('facing')?.addEventListener('change', event => attempt(() => {
    if (item) workspace.edit(p => turnActor(p, item.id, Number((event.target as HTMLInputElement).value))); changed();
  }));
  button('removeItem')?.addEventListener('click', () => attempt(() => {
    if (!item) return;
    workspace.edit(p => { p.layout.items = p.layout.items.filter(i => i.id !== item.id); p.layout.overlays.forEach(o => { o.actors = o.actors.filter(a => a.actorID !== item.id); }); }); selected = ''; changed();
  }));
  button('cameraMovement')?.addEventListener('click', () => attempt(() => {
    workspace.edit(p => { const o = overlay(p); if (o) o.cameraEnd = o.cameraEnd ? null : { x: clamp(o.camera.x + 100, 1000), y: o.camera.y }; }); changed();
  }));
  button('actorMovement')?.addEventListener('click', () => attempt(() => {
    if (!item) return;
    workspace.edit(p => { const o = overlay(p); if (!o) return; let actor = o.actors.find(a => a.actorID === item.id); if (!actor) { actor = { actorID: item.id, ...actorPosition(item, o), end: null }; o.actors.push(actor); } actor.end = actor.end ? null : { x: clamp(actor.x + 100, 1000), y: actor.y }; }); changed();
  }));
}
function turnActor(plan: Plan, id: string, degrees: number): void {
  const item = plan.layout.items.find(i => i.id === id), o = overlay(plan);
  if (!item) return;
  const facing = ((degrees % 360) + 360) % 360;
  if (actorScope === 'shared') item.facing = facing;
  else if (o) {
    const actor = o.actors.find(a => a.actorID === id);
    if (actor) actor.facing = facing;
    else o.actors.push({ actorID: id, ...actorPosition(item, o), end: null, facing });
  }
}
element('inspector').addEventListener('change', event => attempt(() => {
  const input = event.target as HTMLInputElement, key = input.dataset.field;
  if (!key) return;
  workspace.edit(p => {
    const item = p.layout.items.find(i => `item:${i.id}` === selected || `facing:${i.id}` === selected);
    if (item && key === 'label') item.label = input.value;
    else if (item && key === 'confirmed') item.inferred = !input.checked;
    else if (item && (key === 'width' || key === 'height')) {
      const n = Number(input.value), max = key === 'width' ? 1000 - item.x : 600 - item.y;
      if (!Number.isFinite(n) || n < 10 || n > max) throw new Error(`Size must be between 10 and ${max}.`);
      item[key] = n;
    } else if (key === 'x' || key === 'y') {
      const current = position(p, selected);
      if (!current) return;
      const n = Number(input.value);
      if (!Number.isFinite(n) || n < 0 || n > (key === 'x' ? 1000 : 600)) throw new Error('Position is outside the plan.');
      move(p, selected, { ...current, [key]: n });
    }
  }); changed();
}));
function addItem(kind: 'actor' | 'set'): void { attempt(() => {
  const id = crypto.randomUUID();
  workspace.edit(p => { p.layout.items.push({ id, kind, label: kind === 'actor' ? 'Person' : 'Table', x: 450, y: 250, width: kind === 'actor' ? 30 : 160, height: kind === 'actor' ? 30 : 100, inferred: true }); });
  selected = `item:${id}`; changed();
}); }
function references(): void {
  button('reference').disabled = workspace.session.references.length >= 4;
  element('references').innerHTML = workspace.session.references.map(r => `<div class="reference"><img src="${r.dataURL}" alt="${escape(r.name)}"><strong>${escape(r.name)}</strong><label>Geometry notes for local generation<textarea data-notes="${escape(r.id)}" maxlength="4000" placeholder="Door on left, table in centre…">${escape(r.notes)}</textarea></label><button data-remove-reference="${escape(r.id)}">Remove</button></div>`).join('');
}
element('references').addEventListener('change', event => attempt(() => {
  const input = event.target as HTMLTextAreaElement, id = input.dataset.notes;
  if (!id) return;
  const refs = copy(workspace.session.references), ref = refs.find(r => r.id === id);
  if (ref) { ref.notes = input.value; workspace.setReferences(refs); changed(); }
}));
element('references').addEventListener('click', event => attempt(() => {
  const id = (event.target as HTMLElement).dataset.removeReference;
  if (id) { workspace.setReferences(workspace.session.references.filter(r => r.id !== id)); changed(); }
}));
function position(plan: Plan, key: string): Point | null {
  const o = overlay(plan);
  if (key.startsWith('facing:')) {
    const item = plan.layout.items.find(i => `facing:${i.id}` === key);
    return item ? facingHandle(actorPosition(item, o), actorFacing(item, plan, o)) : null;
  }
  if (key === 'cameraFacing' && o) return facingHandle(o.camera, Math.atan2(o.target.y - o.camera.y, o.target.x - o.camera.x) * 180 / Math.PI + 90, 76);
  if (key.startsWith('item:')) {
    const item = plan.layout.items.find(i => `item:${i.id}` === key);
    if (!item) return null;
    return item.kind === 'actor' && actorScope === 'shot' ? o?.actors.find(a => a.actorID === item.id) ?? { x: item.x + item.width / 2, y: item.y + item.height / 2 } : item;
  }
  if (key.startsWith('actorEnd:')) return o?.actors.find(a => `actorEnd:${a.actorID}` === key)?.end ?? null;
  return key === 'camera' ? o?.camera ?? null : key === 'target' ? o?.target ?? null : key === 'cameraEnd' ? o?.cameraEnd ?? null : null;
}
function move(plan: Plan, key: string, to: Point): void {
  const p = { x: clamp(to.x, 1000), y: clamp(to.y, 600) }, o = overlay(plan);
  if (key.startsWith('facing:')) {
    const item = plan.layout.items.find(i => `facing:${i.id}` === key);
    if (item) { const origin = actorPosition(item, o); turnActor(plan, item.id, Math.atan2(p.y - origin.y, p.x - origin.x) * 180 / Math.PI + 90); }
    return;
  }
  if (key === 'cameraFacing' && o) {
    const length = Math.max(80, Math.hypot(o.target.x - o.camera.x, o.target.y - o.camera.y));
    const angle = Math.atan2(p.y - o.camera.y, p.x - o.camera.x);
    o.target = { x: clamp(o.camera.x + Math.cos(angle) * length, 1000), y: clamp(o.camera.y + Math.sin(angle) * length, 600) }; return;
  }
  if (key.startsWith('item:')) {
    const item = plan.layout.items.find(i => `item:${i.id}` === key);
    if (!item) return;
    if (item.kind === 'actor' && actorScope === 'shot' && o) {
      const actor = o.actors.find(a => a.actorID === item.id);
      if (actor) { actor.x = p.x; actor.y = p.y; }
      else o.actors.push({ actorID: item.id, ...p, end: null });
    } else { item.x = clamp(p.x, 1000 - item.width); item.y = clamp(p.y, 600 - item.height); }
  } else if (key.startsWith('actorEnd:')) {
    const actor = o?.actors.find(a => `actorEnd:${a.actorID}` === key); if (actor) actor.end = p;
  } else if (o && key === 'camera') o.camera = p;
  else if (o && key === 'target') o.target = p;
  else if (o && key === 'cameraEnd') o.cameraEnd = p;
}
function coordinate(event: PointerEvent): Point {
  const svg = element('canvas').querySelector('svg')!;
  const point = new DOMPoint(event.clientX, event.clientY).matrixTransform(svg.getScreenCTM()!.inverse());
  return svg.dataset.stage === 'true' ? { x: point.x, y: point.y } : { x: point.x - 60, y: point.y - 120 };
}
element('canvas').addEventListener('pointerdown', event => {
  if (event.button !== 0) return;
  const key = (event.target as Element).closest('[data-key]')?.getAttribute('data-key');
  const plan = displayPlan();
  if (!key || !plan) { selected = ''; paint(); inspector(); return; }
  event.preventDefault(); selected = key;
  drag = { key, start: coordinate(event), before: copy(plan), preview: copy(plan) };
  element('canvas').setPointerCapture(event.pointerId); paint(); inspector();
});
element('canvas').addEventListener('pointermove', event => {
  if (!drag) return;
  const current = coordinate(event), original = position(drag.before, drag.key);
  if (!original) return;
  drag.preview = copy(drag.before);
  move(drag.preview, drag.key, { x: original.x + current.x - drag.start.x, y: original.y + current.y - drag.start.y });
  paint(drag.preview);
});
element('canvas').addEventListener('pointerup', event => attempt(() => {
  if (!drag) return;
  const finished = drag; drag = null;
  element('canvas').releasePointerCapture(event.pointerId);
  if (JSON.stringify(finished.preview) !== JSON.stringify(finished.before)) workspace.edit(p => { p.layout = finished.preview.layout; });
  changed();
}));
element('canvas').addEventListener('pointercancel', () => { drag = null; paint(); });
element('canvas').addEventListener('click', event => {
  const key = (event.target as Element).closest('[data-key]')?.getAttribute('data-key');
  if (key && key !== selected) { selected = key; paint(); inspector(); cast(); }
});
element('canvas').addEventListener('keydown', event => attempt(() => {
  const key = (event.target as Element).closest('[data-key]')?.getAttribute('data-key') ?? selected;
  if (!key) return;
  selected = key;
  if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); paint(); inspector(); return; }
  const offset = event.shiftKey ? 10 : 1;
  const delta = ({ ArrowLeft: [-offset, 0], ArrowRight: [offset, 0], ArrowUp: [0, -offset], ArrowDown: [0, offset] } as Record<string, number[]>)[event.key];
  if (!delta) return;
  event.preventDefault();
  workspace.edit(p => { const v = position(p, key); if (v) move(p, key, { x: v.x + delta[0]!, y: v.y + delta[1]! }); });
  changed();
  element('canvas').querySelector<SVGElement>(`[data-key="${CSS.escape(key)}"]`)?.focus();
}));
async function generation(): Promise<void> {
  const request = workspace.begin(), token = ++activeGeneration;
  if (!configuration.runtime || !configuration.model) throw new Error('Choose a local runtime and model through Shot list > Local AI before generating a plan.');
  busy = true; render();
  try {
    const result = await host<{ ok: boolean; layout?: unknown; error?: string }>('generate', { runtime: configuration.runtime, model: configuration.model, scene: request.scene, references: request.references.map(r => ({ name: r.name, notes: r.notes })) });
    if (token !== activeGeneration) return;
    if (!result.ok) throw new Error(result.error ?? 'Local generation failed. Existing plan preserved.');
    workspace.receive(result.layout, request); changed();
  } finally { if (token === activeGeneration) { busy = false; render(); } }
}
button('generate').addEventListener('click', () => attempt(generation));
button('start').addEventListener('click', () => attempt(generation));
button('cancel').addEventListener('click', () => attempt(async () => {
  ++activeGeneration; await host('cancel'); busy = false; render();
}));
button('open').addEventListener('click', () => attempt(async () => {
  const result = await host<{ content: string; token: string } | null>('open');
  if (!result) return;
  const plan = decodePlan(result.content, workspace.scene.sceneID);
  await host('adoptOpen', { token: result.token });
  workspace.load(plan); selected = ''; changed();
}));
button('save').addEventListener('click', () => attempt(async () => {
  if (workspace.session.draft || !workspace.session.plan) return;
  const revision = workspace.session.revision;
  const result = await host<boolean>('save', { content: encodePlan(workspace.session.plan) });
  if (result && revision === workspace.session.revision) workspace.session.dirty = false;
  changed();
}));
button('reference').addEventListener('click', () => attempt(async () => {
  const ref = await host<Reference | null>('reference');
  if (ref) { workspace.setReferences([...workspace.session.references, ref]); changed(); }
}));
button('done').addEventListener('click', () => attempt(async () => { await host('done'); }));
button('undo').addEventListener('click', () => { workspace.undo(); changed(); });
button('redo').addEventListener('click', () => { workspace.redo(); changed(); });
element('shot').addEventListener('change', event => { selectedShot = (event.target as HTMLSelectElement).value; selected = ''; render(); });
element('underlay').addEventListener('change', event => { showReference = (event.target as HTMLInputElement).checked; paint(); });
document.addEventListener('keydown', event => {
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'z' && !(event.target instanceof HTMLInputElement || event.target instanceof HTMLTextAreaElement)) {
    event.preventDefault(); if (event.shiftKey) workspace.redo(); else workspace.undo(); changed();
  }
});
async function exportImage(format: 'pdf' | 'png'): Promise<void> {
  const plan = displayPlan(); if (!plan) return;
  const label = workspace.session.draft ? 'DRAFT · Review before acceptance.' : stale(plan, workspace.scene) ? 'REVIEW REQUIRED · Scene or shot list changed.' : '';
  const svg = renderPlan(plan, selectedShot, '', showReference, label);
  const blob = new Blob([svg], { type: 'image/svg+xml' }), url = URL.createObjectURL(blob);
  try {
    const image = new Image();
    await new Promise<void>((resolve, reject) => { image.onload = () => resolve(); image.onerror = () => reject(new Error('Could not render plan export.')); image.src = url; });
    const canvas = document.createElement('canvas'); canvas.width = 2800; canvas.height = 2125;
    const context = canvas.getContext('2d'); if (!context) throw new Error('Image renderer unavailable.');
    context.drawImage(image, 0, 0, canvas.width, canvas.height);
    await host('export', { format, dataURL: canvas.toDataURL('image/png'), shotNumber: plan.scene.shots.findIndex(s => s.id === selectedShot) + 1 });
  } finally { URL.revokeObjectURL(url); }
}
button('exportPNG').addEventListener('click', () => attempt(() => exportImage('png')));
button('exportPDF').addEventListener('click', () => attempt(() => exportImage('pdf')));
window.blocking = {
  start(context) {
    attempt(() => {
      configuration = context; workspace = new BlockingWorkspace(validateScene(context.scene));
      if (context.recovery) { try { workspace.session = restoreSession(context.recovery, workspace.scene.sceneID); } catch (e) { error(new Error(`Could not restore blocking plan: ${e instanceof Error ? e.message : String(e)}`)); } }
      render();
      if (context.initialError) error(context.initialError);
    });
  },
  update(scene) {
    if (!workspace) return;
    try { workspace.scene = validateScene(scene); render(); }
    catch (e) { window.blocking.invalidate(e instanceof Error ? e.message : String(e)); }
  },
  invalidate(message) { if (workspace) { workspace.scene = { ...workspace.scene, shots: [] }; render(); error(message); } },
  reply(id, value, message) { const request = pending.get(id); if (!request) return; pending.delete(id); if (message) request.reject(new Error(message)); else request.resolve(value); },
};
void host('ready').catch(error);

button('placeActor').addEventListener('click', () => addItem('actor'));
button('placeTable').addEventListener('click', () => addItem('set'));
button('referencesToggle').addEventListener('click', () => { referencesOpen = !referencesOpen; panelState(); });
element('cast').addEventListener('click', event => {
  const id = (event.target as Element).closest('[data-select]')?.getAttribute('data-select');
  if (id) { selected = `item:${id}`; paint(); inspector(); cast(); }
});
