import { clamp, copy, type Item, type Layout, type Point, type SceneInput } from './model';

type Box = Point & { width: number; height: number };
function inside(p: Point, box: Box, radius: number): boolean {
  return p.x > box.x - radius && p.x < box.x + box.width + radius && p.y > box.y - radius && p.y < box.y + box.height + radius;
}
function available(p: Point, boxes: Box[], others: Point[], radius: number): boolean {
  return !boxes.some(box => inside(p, box, radius)) && others.every(other => Math.hypot(p.x - other.x, p.y - other.y) >= radius * 2);
}
function clearPosition(desired: Point, boxes: Box[], others: Point[], radius: number): Point {
  const bound = (p: Point): Point => ({ x: Math.max(60, Math.min(940, p.x)), y: Math.max(65, Math.min(515, p.y)) });
  const p = bound(desired), candidates: Point[] = [p];
  for (const box of boxes) {
    const left = box.x - radius - 2, right = box.x + box.width + radius + 2;
    const top = box.y - radius - 2, bottom = box.y + box.height + radius + 2;
    candidates.push({ x: left, y: p.y }, { x: right, y: p.y }, { x: p.x, y: top }, { x: p.x, y: bottom });
    for (const x of [left, right]) for (const y of [top, bottom]) candidates.push({ x, y });
  }
  for (let y = 65; y <= 515; y += 50) for (let x = 60; x <= 940; x += 50) candidates.push({ x, y });
  const best = candidates.map(bound).filter(c => available(c, boxes, others, radius))
    .sort((a, b) => Math.hypot(a.x - p.x, a.y - p.y) - Math.hypot(b.x - p.x, b.y - p.y))[0];
  if (!best) throw new Error('The proposed set leaves no clear space for people and camera. Retry with a simpler scene.');
  return best;
}
function solid(item: Item): boolean { return item.kind === 'set' && !/door|entrance|window|^(room|floor|kitchen|hall|courtyard|street|location)( plan)?$/i.test(item.label); }

/** Normalises a new proposal only. Accepted plans and manual edits never pass here. */
function entrySide(name: string, action: string): 'left' | 'right' | null {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = action.match(new RegExp(`\\b${escaped}\\b[^.!?\\n]{0,45}\\b(?:enters|walks in|comes in)\\b([^.!?\\n]{0,70})`, 'i'));
  if (!match || !/door|entrance/i.test(match[1]!)) return null;
  return /left/i.test(match[1]!) ? 'left' : /right/i.test(match[1]!) ? 'right' : null;
}
function entrance(side: 'left' | 'right'): Point { return { x: side === 'left' ? 150 : 850, y: 300 }; }
export function prepareGeography(layout: Layout, scene?: SceneInput): Layout {
  const result = copy(layout);
  const actions = scene?.shots.map(s => s.action).join(' ') ?? '';
  const entryActors = result.items.filter(i => i.kind === 'actor').map(actor => ({ actor, side: entrySide(actor.label, actions) }));
  const sides = [...new Set(entryActors.map(a => a.side).filter((side): side is 'left' | 'right' => side !== null))];
  for (const side of sides) {
    const door = result.items.find(i => i.kind === 'set' && /door|entrance/i.test(i.label) && (i.label.toLowerCase().includes(side) || sides.length === 1));
    if (door) { door.x = side === 'left' ? 25 : 900; door.y = 260; }
    else result.items.push({ id: `entrance-${side}`, kind: 'set', label: `${side === 'left' ? 'Left' : 'Right'} door`, x: side === 'left' ? 25 : 900, y: 260, width: 75, height: 75, inferred: true });
  }
  for (const { actor, side } of entryActors) {
    if (side) { const p = entrance(side); actor.x = p.x - actor.width / 2; actor.y = p.y - actor.height / 2; }
  }
  for (const item of result.items.filter(i => i.kind === 'set')) {
    if (/table|desk|counter/i.test(item.label)) { item.width = Math.max(150, item.width); item.height = Math.max(90, item.height); }
    else if (/chair|seat/i.test(item.label)) { item.width = Math.max(55, item.width); item.height = Math.max(55, item.height); }
    else if (/sofa|couch|bench/i.test(item.label)) { item.width = Math.max(160, item.width); item.height = Math.max(65, item.height); }
    else if (/door|entrance/i.test(item.label)) { item.width = Math.max(75, item.width); item.height = Math.max(75, item.height); }
    item.x = Math.max(/door|entrance/i.test(item.label) ? 25 : 35, Math.min(975 - item.width, item.x));
    item.y = Math.max(35, Math.min(565 - item.height, item.y));
  }
  const boxes = result.items.filter(solid), placed: Point[] = [];
  for (const item of result.items.filter(i => i.kind === 'actor')) {
    const point = clearPosition({ x: item.x + item.width / 2, y: item.y + item.height / 2 }, boxes, placed, 38);
    item.width = 30; item.height = 30; item.x = point.x - 15; item.y = point.y - 15;
    placed.push(point);
  }
  return result;
}

export function prepareCameras(layout: Layout, scene: SceneInput): Layout {
  const result = copy(layout), actors = result.items.filter(i => i.kind === 'actor'), boxes = result.items.filter(solid);
  for (const shot of scene.shots) {
    const o = result.overlays.find(o => o.shotID === shot.id);
    if (!o) continue;
    const placed: Point[] = [];
    for (const actor of actors) {
      let position = o.actors.find(a => a.actorID === actor.id);
      const side = entrySide(actor.label, shot.action);
      const p = clearPosition(side ? entrance(side) : position ?? { x: actor.x + 15, y: actor.y + 15 }, boxes, placed, 38);
      if (position) { position.x = p.x; position.y = p.y; }
      else { position = { actorID: actor.id, ...p, end: null }; o.actors.push(position); }
      placed.push(p);
    }
    const action = shot.action.toLocaleLowerCase('en-GB');
    const named = actors.map(a => ({ actor: a, index: action.search(new RegExp(`(?<![\\p{L}\\p{N}])${a.label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}(?![\\p{L}\\p{N}])`, 'iu')) }))
      .filter(a => a.index >= 0).sort((a, b) => a.index - b.index);
    const wide = /wide|establish|long shot/i.test(shot.framing), close = /close|insert|detail/i.test(shot.framing);
    const subjects = (wide ? named : named.slice(0, 1)).map(({ actor }) => o.actors.find(a => a.actorID === actor.id)!);
    if (subjects.length) o.target = { x: subjects.reduce((sum, p) => sum + p.x, 0) / subjects.length, y: subjects.reduce((sum, p) => sum + p.y, 0) / subjects.length };
    const dx = o.camera.x - o.target.x, dy = o.camera.y - o.target.y, distance = Math.hypot(dx, dy);
    const minimum = wide ? 260 : close ? 90 : 150, maximum = wide ? 480 : close ? 170 : 280;
    const wanted = Math.max(minimum, Math.min(maximum, distance));
    const angle = distance > 1 ? Math.atan2(dy, dx) : Math.PI / 2;
    const desired = { x: clamp(o.target.x + Math.cos(angle) * wanted, 1000), y: clamp(o.target.y + Math.sin(angle) * wanted, 600) };
    o.camera = clearPosition(desired, boxes, placed, 40);
    if (wide && subjects.length > 1) {
      const seesEveryone = (camera: Point): boolean => subjects.every(person => (person.x - camera.x) * (o.target.x - camera.x) + (person.y - camera.y) * (o.target.y - camera.y) > 1500);
      if (!seesEveryone(o.camera)) {
        const alternatives = Array.from({ length: 16 }, (_, n) => ({ x: o.target.x + Math.cos(n * Math.PI / 8) * wanted, y: o.target.y + Math.sin(n * Math.PI / 8) * wanted }))
          .map(p => clearPosition(p, boxes, placed, 40)).filter(seesEveryone)
          .sort((a, b) => Math.hypot(a.x - desired.x, a.y - desired.y) - Math.hypot(b.x - desired.x, b.y - desired.y));
        if (alternatives[0]) o.camera = alternatives[0];
      }
    }
  }
  return result;
}
