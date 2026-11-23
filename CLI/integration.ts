import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import assert from 'node:assert/strict';

// Uses only isolated fixture projects and a distinct app process. No provider is invoked.
const fixture = mkdtempSync(join(tmpdir(), 'act-process-'));
const root = join(fixture, 'Projects'), endpoint = join(fixture, 'Endpoint');
const app = resolve('.build/Act.app'), cli = join(app, 'Contents/Helpers/act');
const environment = { ...process.env, PATH: '/usr/bin:/bin', ACT_APP_PATH: app, ACT_PROJECT_ROOT: root, ACT_AUTOMATION_DIRECTORY: endpoint };
let pid: number | undefined;
function call(operation: string, parameters: Record<string, unknown> = {}, doc?: Record<string, string>, id: string = crypto.randomUUID()) {
  const request = { version: 1, requestID: id, operation, parameters, ...(doc ? { documentID: doc.documentID, expectedRevision: doc.revision } : {}) };
  const process = spawnSync(cli, ['call', '--stdin'], { input: JSON.stringify(request), env: environment, encoding: 'utf8', timeout: 30000, maxBuffer: 8 * 1024 * 1024 });
  assert.equal(process.status, 0, process.stdout + process.stderr);
  const response = JSON.parse(process.stdout);
  assert.equal(response.ok, true, JSON.stringify(response));
  return response.result;
}
function stop() {
  if (pid) { try { process.kill(pid, 'SIGTERM'); } catch {} pid = undefined; }
}
try {
  assert(existsSync(cli), 'Build the app first.');
  const health = call('status'); pid = health.pid;
  assert.equal(health.projectRoot, root);
  assert.equal(health.isActive, false, 'Background automation must not activate Act.');
  assert.deepEqual(call('documents.list'), []);
  call('projects.create', { name: 'Film' });
  const path = join(root, 'Film/Draft.fountain');
  const original = 'INT. CAFÉ - NIGHT #1#\r\n\r\nÉva opens a red book.\r\n\r\nEXT. STREET - DAY #2#\r\n\r\nRain falls.\r\n';
  let doc = call('documents.create', { path, source: original });
  const scene = call('source.read', {}, doc).scenes[0].id;
  const preview = call('edits.preview', { edits: [{ kind: 'replace', sceneID: scene, match: 'red book', text: 'blue notebook' }] }, doc);
  const mutationID = 'process-edit-once';
  const input = { ...doc };
  doc = call('edits.apply', { previewID: preview.id }, input, mutationID);
  assert.equal(call('source.read', {}, doc).source, original.replace('red book', 'blue notebook'));
  assert(['pending', 'saved'].includes(doc.persistence));
  assert.deepEqual(call('edits.apply', { previewID: preview.id }, input, mutationID), doc);
  const shotList = call('shots.list', {}, doc);
  const added = call('shots.add', { sceneID: scene, action: 'Éva reads', framing: 'Wide' }, { ...doc, revision: shotList.revision });
  const shotID = added.list.shots[0].id;
  const image = call('images.prepare', { targetKind: 'shot', targetID: shotID, prompt: 'Storyboard in ink.' }, doc);
  assert(image.prompt.includes('Éva reads'));
  assert(!image.prompt.includes('Rain falls'));
  assert.equal(call('images.export', { jobID: image.id }).state, 'prepared');
  doc = call('documents.save', {}, doc);
  assert.equal(doc.persistence, 'saved');
  stop();
  await Bun.sleep(300);
  const relaunched = call('status'); pid = relaunched.pid;
  assert.notEqual(pid, health.pid);
  doc = call('documents.open', { path });
  const history = call('reviews.list', {}, doc);
  assert.equal(history.changes.length, 1);
  assert.equal(history.changes[0].conflicted, false);
  assert.equal(call('jobs.status', { jobID: image.id }).state, 'prepared');
  assert.equal(call('source.read', {}, doc).source, original.replace('red book', 'blue notebook'));
  doc = call('reviews.revert', { changeID: history.changes[0].id }, doc);
  assert.equal(call('source.read', {}, doc).source, original);
  doc = call('documents.save', {}, doc);
  assert.equal(readFileSync(path, 'utf8'), original);
  const bin = join(fixture, 'bin'); mkdirSync(bin);
  const installed = spawnSync(cli, ['install', '--directory', bin], { env: environment, encoding: 'utf8' });
  assert.equal(installed.status, 0, installed.stdout + installed.stderr);
  assert.equal(spawnSync(join(bin, 'act'), ['schema'], { env: environment }).status, 0);
  const output = resolve('.scratch/ai-cli-process-validation.json');
  mkdirSync(resolve('.scratch'), { recursive: true });
  writeFileSync(output, JSON.stringify({ passed: true, processLaunch: true, backgroundActivation: false, relaunch: true, nativeEdits: true, persistedHistory: true, sourceReversion: true, jobs: true, installation: true, separatelyInstalledNodeRequired: false, paidRequests: 0 }, null, 2) + '\n');
  console.log('Actual app/CLI launch, edits, save, relaunch, history, reversion, jobs and installation passed.');
} finally {
  stop(); await Bun.sleep(150);
  rmSync(fixture, { recursive: true, force: true });
}
