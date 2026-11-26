import type { Plan, Point, Item, Overlay } from './model';
export const escape = (s: string): string => s.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' })[c]!);
const colours = ['#528698', '#be8552', '#8d779f', '#6f9174', '#a56874', '#747fa8'];
export function actorPosition(item: Item, overlay?: Overlay): Point {
  return overlay?.actors.find(a => a.actorID === item.id) ?? { x: item.x + item.width / 2, y: item.y + item.height / 2 };
}
export function actorFacing(item: Item, plan: Plan, overlay?: Overlay): number {
  const override = overlay?.actors.find(a => a.actorID === item.id)?.facing ?? item.facing;
  if (override !== undefined) return override;
  const other = plan.layout.items.find(i => i.kind === 'actor' && i.id !== item.id);
  if (!other) return 0;
  const p = actorPosition(item, overlay), t = actorPosition(other, overlay);
  return (Math.atan2(t.y - p.y, t.x - p.x) * 180 / Math.PI + 450) % 360;
}
export function facingHandle(p: Point, facing: number, distance = 74): Point {
  const angle = (facing - 90) * Math.PI / 180;
  return { x: p.x + Math.cos(angle) * distance, y: p.y + Math.sin(angle) * distance };
}
function path(a: Point, b: Point, colour: string, dash = false): string {
  return `<path d="M${a.x},${a.y} L${b.x},${b.y}" fill="none" stroke="${colour}" stroke-width="2.5" ${dash ? 'stroke-dasharray="7 7"' : ''} marker-end="url(#arrow)" pointer-events="none"/>`;
}
function grab(p: Point, key: string, label: string, colour: string, selected: string): string {
  return `<g data-key="${escape(key)}" tabindex="0" role="button" aria-label="${escape(label)}" transform="translate(${p.x} ${p.y})" class="piece handle" style="cursor:grab"><circle r="17" fill="transparent"/><circle r="7" fill="white" stroke="${colour}" stroke-width="${key === selected ? 3 : 2}"/><circle r="2" fill="${colour}"/></g>`;
}
function furniture(item: Item, selected: string): string {
  const { x, y, width: w, height: h } = item;
  const label = item.label.toLowerCase(), active = selected === `item:${item.id}`;
  let drawing = '';
  if (/door|entrance/.test(label)) {
    drawing = `<path d="M${x},${y + h} V${y} H${x + w}" fill="none" stroke="#777b77" stroke-width="5"/><path d="M${x},${y + h} A${h},${h} 0 0 1 ${x + h},${y}" fill="none" stroke="#a3a8a2" stroke-width="1.5" stroke-dasharray="4 4"/><circle cx="${x}" cy="${y}" r="4" fill="#777b77"/>`;
  } else if (/table|desk|counter/.test(label)) {
    drawing = `<rect x="${x + 2}" y="${y + 6}" width="${w}" height="${h}" rx="8" fill="#363d3a" opacity=".12"/><rect x="${x}" y="${y}" width="${w}" height="${h}" rx="8" fill="#cec3ac" stroke="#a99f89" stroke-width="2"/><rect x="${x + 6}" y="${y + 6}" width="${Math.max(1, w - 12)}" height="${Math.max(1, h - 12)}" rx="4" fill="none" stroke="#e3dbc9" stroke-width="1.5"/><path d="M${x + w * .22},${y + 10} V${y + h - 10} M${x + w * .68},${y + 10} V${y + h - 10}" stroke="#b8ad96" stroke-opacity=".35"/>`;
  } else if (/chair|seat|sofa|couch|bench/.test(label)) {
    drawing = `<rect x="${x + 2}" y="${y + 5}" width="${w}" height="${h}" rx="10" fill="#363d3a" opacity=".12"/><rect x="${x}" y="${y}" width="${w}" height="${h}" rx="10" fill="#a8b1a6" stroke="#879184" stroke-width="2"/><rect x="${x + 8}" y="${y + 10}" width="${Math.max(1, w - 16)}" height="${Math.max(1, h - 18)}" rx="6" fill="#bdc4b8"/><path d="M${x + 8},${y + 10} H${x + w - 8}" stroke="#879184" stroke-width="5"/>`;
  } else {
    drawing = `<rect x="${x + 2}" y="${y + 5}" width="${w}" height="${h}" rx="5" fill="#363d3a" opacity=".10"/><rect x="${x}" y="${y}" width="${w}" height="${h}" rx="5" fill="#d9ddd5" stroke="#a3aaa0" stroke-width="2"/>`;
  }
  return `<g data-key="item:${escape(item.id)}" tabindex="0" role="button" aria-label="${escape(item.label)} set object" class="piece" style="cursor:grab"><rect x="${x - 8}" y="${y - 8}" width="${w + 16}" height="${h + 16}" fill="transparent"/>${active ? `<rect x="${x - 7}" y="${y - 7}" width="${w + 14}" height="${h + 14}" rx="10" fill="none" stroke="#43889b" stroke-width="2" stroke-dasharray="4 4"/>` : ''}${drawing}<text x="${x + w / 2}" y="${y + h / 2 + 4}" text-anchor="middle" fill="#585e54" font-size="11" paint-order="stroke" stroke="#e5dfd2" stroke-width="3">${escape(item.label)}</text></g>`;
}
function person(item: Item, plan: Plan, overlay: Overlay | undefined, selected: string, index: number, interactive: boolean): string {
  const p = actorPosition(item, overlay), facing = actorFacing(item, plan, overlay);
  const colour = colours[index % colours.length]!, active = selected === `item:${item.id}` || selected === `facing:${item.id}`;
  const position = overlay?.actors.find(a => a.actorID === item.id);
  const handle = facingHandle(p, facing);
  const movement = position?.end ? path(p, position.end, colour, true) + grab(position.end, `actorEnd:${item.id}`, `${item.label} movement end`, colour, selected) : '';
  const rotation = active && interactive ? `<path d="M${p.x},${p.y} L${handle.x},${handle.y}" stroke="${colour}" stroke-width="1.5" stroke-dasharray="3 5" pointer-events="none"/>${grab(handle, `facing:${item.id}`, `Turn ${item.label}`, colour, selected)}` : '';
  // The body has shoulders, arms, hands, shoes and a head, seen from above.
  return `${movement}${rotation}<g data-key="item:${escape(item.id)}" tabindex="0" role="button" aria-label="${escape(item.label)} actor" class="piece person" style="cursor:grab"><g transform="translate(${p.x} ${p.y})"><circle r="45" fill="transparent"/>${active ? `<circle r="46" fill="${colour}" fill-opacity=".09" stroke="${colour}" stroke-width="1.5"/>` : ''}<ellipse cx="2" cy="9" rx="30" ry="34" fill="#263a32" opacity=".13"/><g transform="rotate(${facing})"><path d="M-16,12 L-15,31 Q-10,37 -5,31 L-3,12 M3,12 L5,31 Q10,37 15,31 L16,12" fill="#525c63" stroke="#41494f" stroke-width="1.5"/><path d="M-16,27 Q-9,22 -4,28 L-4,36 Q-11,41 -17,35 Z M4,28 Q10,22 16,27 L17,35 Q11,41 4,36 Z" fill="#333b40"/><path d="M-17,-10 Q-27,-9 -29,4 L-27,18 Q-23,23 -19,17 L-19,4 M17,-10 Q27,-9 29,4 L27,18 Q23,23 19,17 L19,4" fill="${colour}" stroke="#344b50" stroke-opacity=".3" stroke-width="1.5"/><ellipse cx="-23" cy="21" rx="5" ry="7" fill="#c1ad98"/><ellipse cx="23" cy="21" rx="5" ry="7" fill="#c1ad98"/><path d="M-20,-11 Q0,-20 20,-11 L17,19 Q0,25 -17,19 Z" fill="${colour}" stroke="#344b50" stroke-opacity=".35" stroke-width="1.5"/><path d="M-14,15 Q0,20 14,15" fill="none" stroke="white" stroke-opacity=".18" stroke-width="2"/><ellipse cy="-9" rx="12" ry="14" fill="#bba68f" stroke="#8e7c68" stroke-width="1"/><path d="M-12,-7 Q-16,-26 0,-27 Q16,-26 12,-7 Q4,-14 -5,-10 Z" fill="#4d4842"/><path d="M-3,-23 Q3,-26 8,-18" fill="none" stroke="#73675a" stroke-width="2"/><path d="M-3,-23 L0,-29 L3,-23" fill="#c5b5a1"/></g><rect x="-55" y="47" width="110" height="25" rx="12.5" fill="#f8faf5" stroke="${active ? colour : '#d4dad0'}"/><circle cx="-43" cy="59.5" r="3.5" fill="${colour}"/><text y="64" x="4" text-anchor="middle" font-size="12" font-weight="600" fill="#37473e">${escape(item.label.slice(0, 16))}</text></g></g>`;
}
export function renderPlan(plan: Plan, shotID: string, selected = '', showReference = true, status = '', stage = false): string {
  const overlay = plan.layout.overlays.find(o => o.shotID === shotID), shot = plan.scene.shots.find(s => s.id === shotID);
  const number = plan.scene.shots.findIndex(s => s.id === shotID) + 1;
  const refs = showReference ? plan.references.slice(0, 1).map(r => `<image href="${r.dataURL}" width="1000" height="600" opacity="0.22" preserveAspectRatio="xMidYMid meet"/>`).join('') : '';
  const sets = plan.layout.items.filter(i => i.kind === 'set').map(i => furniture(i, selected)).join('');
  const actors = plan.layout.items.filter(i => i.kind === 'actor').map((i, index) => person(i, plan, overlay, selected, index, stage)).join('');
  let cone = '', camera = '';
  if (overlay) {
    const c = overlay.camera, t = overlay.target;
    const angle = Math.atan2(t.y - c.y, t.x - c.x), degrees = angle * 180 / Math.PI + 90;
    const length = Math.hypot(t.x - c.x, t.y - c.y), spread = /close|insert|detail/i.test(shot?.framing ?? '') ? .17 : /medium|mid/i.test(shot?.framing ?? '') ? .32 : .52;
    const wide = /wide|establish|long shot/i.test(shot?.framing ?? '');
    const visiblePeople = plan.layout.items.filter(i => i.kind === 'actor' && (shot?.action.toLowerCase().includes(i.label.toLowerCase()) ?? false)).map(i => actorPosition(i, overlay));
    const depth = (p: Point) => (p.x - c.x) * Math.cos(angle) + (p.y - c.y) * Math.sin(angle);
    const reach = wide ? Math.max(length + 65, ...visiblePeople.map(p => depth(p) + 65)) : length + 45;
    let width = reach * spread;
    if (wide) for (const p of visiblePeople) {
      const side = Math.abs(-(p.x - c.x) * Math.sin(angle) + (p.y - c.y) * Math.cos(angle));
      if (depth(p) > 0) width = Math.max(width, (side + 38) / depth(p) * reach);
    }
    const end = { x: c.x + Math.cos(angle) * reach, y: c.y + Math.sin(angle) * reach };
    const x = Math.sin(angle) * width, y = -Math.cos(angle) * width;
    const aimHandle = facingHandle(c, degrees, 76);
    const active = selected === 'camera' || selected === 'cameraFacing' || selected === 'target';
    cone = `<path d="M${c.x},${c.y} L${end.x + x},${end.y + y} L${end.x - x},${end.y - y} Z" fill="#5e96a7" fill-opacity=".13" stroke="#7ba9b6" stroke-width="1" stroke-dasharray="5 6" pointer-events="none"/>${path(c, t, '#6a98a5', true)}<g transform="translate(${t.x} ${t.y})" pointer-events="none"><path d="M-7,0 H7 M0,-7 V7" stroke="#6195a5" stroke-width="1.5"/></g>`;
    camera = `${overlay.cameraEnd ? path(c, overlay.cameraEnd, '#4d7f90', true) + grab(overlay.cameraEnd, 'cameraEnd', 'Camera movement end', '#4d7f90', selected) : ''}<g data-key="camera" tabindex="0" role="button" aria-label="Camera position" class="piece camera" style="cursor:grab" transform="translate(${c.x} ${c.y})"><circle r="45" fill="transparent"/>${active ? '<circle r="45" fill="#4d7f90" fill-opacity=".10" stroke="#4d7f90" stroke-width="1.5"/>' : ''}<g transform="rotate(${degrees})"><path d="M0,10 L-25,35 M0,10 L25,35 M0,10 V40" stroke="#7f8987" stroke-width="5" stroke-linecap="round"/><path d="M0,10 L-25,35 M0,10 L25,35 M0,10 V40" stroke="#3f4e50" stroke-width="2" stroke-linecap="round"/><rect x="-20" y="-12" width="40" height="31" rx="5" fill="#3d555f" stroke="#233e4a" stroke-width="2"/><path d="M-12,-12 V-24 L-16,-29 H16 L12,-24 V-12" fill="#263c46" stroke="#152f3a" stroke-width="1.5"/><rect x="-15" y="-29" width="30" height="5" rx="2" fill="#81adb7"/><rect x="-27" y="-5" width="7" height="14" rx="2" fill="#526b72"/><rect x="-13" y="-5" width="26" height="15" rx="2" fill="#536e78"/><circle cx="12" cy="14" r="2" fill="#e19c67"/></g><rect x="-49" y="47" width="98" height="24" rx="12" fill="#edf3f3" stroke="#bfd0d3"/><text y="63" text-anchor="middle" fill="#3e626f" font-size="11" font-weight="600">Camera · ${escape((shot?.framing ?? '').slice(0, 9))}</text></g>${stage ? `<path d="M${c.x},${c.y} L${aimHandle.x},${aimHandle.y}" stroke="#4d7f90" stroke-width="1.5" pointer-events="none"/>${grab(aimHandle, 'cameraFacing', 'Turn camera', '#4d7f90', selected)}` : ''}`;
  }
  const note = status || (plan.layout.items.some(i => i.inferred) ? 'Proposed positions. Review before shooting.' : 'Object positions confirmed. Review camera and shot positions.');
  const interior = /^(INT\.|INT |I\/E)/i.test(plan.scene.heading);
  const contents = `<rect width="1000" height="600" fill="#e9ede5"/><rect x="25" y="25" width="950" height="550" rx="3" fill="#f0f2eb" stroke="#b7c0b2" stroke-width="${interior ? 9 : 1}" ${interior ? '' : 'stroke-dasharray="5 9"'}/><rect x="31" y="31" width="938" height="538" fill="url(#grid)"/>${refs}${cone}${sets}${camera}${actors}`;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${stage ? 1000 : 1120}" height="${stage ? 600 : 850}" viewBox="${stage ? '0 0 1000 600' : '0 0 1120 850'}" data-stage="${stage}" role="group" aria-label="Overhead blocking plan for ${escape(plan.scene.heading)}" font-family="-apple-system,BlinkMacSystemFont,Helvetica,Arial,sans-serif"><defs><pattern id="grid" width="50" height="50" patternUnits="userSpaceOnUse"><path d="M50 0 H0 V50" fill="none" stroke="#d6ddcf" stroke-width=".7"/></pattern><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" orient="auto"><path d="M0 0 L10 5 L0 10" fill="none" stroke="#6a98a5" stroke-width="1.5"/></marker><clipPath id="plot"><rect width="1000" height="600"/></clipPath></defs>${stage ? `<g clip-path="url(#plot)">${contents}</g>` : `<rect width="1120" height="850" fill="#fff"/><text x="60" y="39" fill="#798779" font-size="11" letter-spacing="2">BLOCKING PLAN</text><text x="60" y="70" fill="#293a31" font-size="23" font-weight="600">${escape(plan.scene.heading.slice(0, 85))}</text><text x="60" y="96" fill="#627568" font-size="13">Shot ${String(number).padStart(2, '0')} · ${escape((shot?.framing ?? '').slice(0, 100))}</text><g transform="translate(60 120)" clip-path="url(#plot)">${contents}</g><text x="60" y="750" fill="#627568" font-size="12">${escape(note.slice(0, 140))}</text><text x="60" y="776" fill="#627568" font-size="12">View cone schematic · Dashed paths show movement · Not to scale · Scene boundary proposed</text><text x="60" y="803" fill="#627568" font-size="12">${escape((overlay?.warning || plan.layout.notes).replace(/\s+/g, ' ').slice(0, 140))}</text>`}</svg>`;
}
