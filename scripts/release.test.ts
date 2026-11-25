import { afterEach, beforeEach, expect, test } from 'bun:test';
import { createHash } from 'node:crypto';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { identity, publish, type Run } from './release';

const originalDirectory = process.cwd();
const id = identity('a'.repeat(40), '12345');
let directory: string;
let calls: string[][];
beforeEach(async () => {
  directory = await mkdtemp(join(tmpdir(), 'act-release-test-'));
  process.chdir(directory);
  await mkdir('.build/download', { recursive: true });
  const archive = Buffer.from('verified archive fixture');
  await writeFile(`.build/download/${id.asset}`, archive);
  await writeFile('.build/download/release.json', JSON.stringify({
    ...id, sha256: createHash('sha256').update(archive).digest('hex'),
  }));
  calls = [];
});
afterEach(async () => {
  process.chdir(originalDirectory);
  await rm(directory, { recursive: true, force: true });
});
function github(state: 'missing' | 'draft' | 'published' | 'unavailable', failUpload = false): Run {
  return async args => {
    calls.push(args);
    if (args[1] === 'api') {
      if (state === 'missing') throw new Error('HTTP 404');
      if (state === 'unavailable') throw new Error('HTTP 503');
      return JSON.stringify({ draft: state === 'draft', target_commitish: id.sha });
    }
    if (failUpload && args[2] === 'upload') throw new Error('Upload interrupted');
    return '';
  };
}
test('identifiers distinguish pushes and reject malformed input', () => {
  expect(identity(id.sha, '12346').tag).not.toBe(id.tag);
  expect(() => identity('main', '12345')).toThrow();
  expect(() => identity(id.sha, '../12345')).toThrow();
});
test('new release stays a draft until upload succeeds and targets exact commit', async () => {
  await publish(id, 'example/Act', github('missing'));
  expect(calls.map(args => args[2])).toEqual([
    `repos/example/Act/releases/tags/${id.tag}`, 'create', 'upload', 'edit',
  ]);
  expect(calls[1]).toContain(id.sha);
  expect(calls[1]).toContain('--draft');
  expect(calls[3]).toContain('--draft=false');
});
test('interrupted draft resumes without creating another release', async () => {
  await publish(id, 'example/Act', github('draft'));
  expect(calls.some(args => args[2] === 'create')).toBe(false);
  expect(calls.some(args => args[2] === 'upload')).toBe(true);
});
test('published release is never modified on rerun', async () => {
  await publish(id, 'example/Act', github('published'));
  expect(calls).toHaveLength(1);
});
test('failed upload never publishes the draft', async () => {
  await expect(publish(id, 'example/Act', github('draft', true))).rejects.toThrow('Upload interrupted');
  expect(calls.some(args => args[2] === 'edit')).toBe(false);
});
test('network failures do not masquerade as missing releases', async () => {
  await expect(publish(id, 'example/Act', github('unavailable'))).rejects.toThrow('HTTP 503');
  expect(calls).toHaveLength(1);
});
test('corrupted download is rejected before contacting GitHub', async () => {
  await writeFile(`.build/download/${id.asset}`, 'corrupted');
  await expect(publish(id, 'example/Act', github('missing'))).rejects.toThrow('checksum mismatch');
  expect(calls).toHaveLength(0);
});
test('a conflicting existing release is not modified', async () => {
  const exec: Run = async args => {
    calls.push(args);
    return JSON.stringify({ draft: true, target_commitish: 'b'.repeat(40) });
  };
  await expect(publish(id, 'example/Act', exec)).rejects.toThrow('another commit');
  expect(calls).toHaveLength(1);
});
