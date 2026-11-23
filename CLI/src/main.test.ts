import { afterEach, describe, expect, test } from 'bun:test';
import { createServer, type Server, type Socket } from 'node:net';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { exchange, parseArguments, type Request } from './main';

const cleanups: (() => void)[] = [];
afterEach(() => { for (const cleanup of cleanups.splice(0)) cleanup(); });

describe('command contract', () => {
  test('literal prompts and explicit identity survive argument parsing', () => {
    const prompt = 'Keep $HOME, `literal`, emoji 🎬 and\nline breaks.';
    const { request } = parseArguments(['images', 'prepare', '--document', 'doc', '--revision', 'rev', '--request-id', 'once', '--json', JSON.stringify({ targetKind: 'shot', targetID: 'shot', prompt })]);
    expect(request.parameters.prompt).toBe(prompt);
    expect(request.operation).toBe('images.prepare');
    expect(request.requestID).toBe('once');
    expect(request.expectedRevision).toBe('rev');
  });
  test('unknown flags and malformed parameters fail before launch', () => {
    expect(() => parseArguments(['documents', 'list', '--approve', 'yes'])).toThrow('Unknown option');
    expect(() => parseArguments(['documents', 'list', '--json', '[]'])).toThrow('must contain an object');
    expect(() => parseArguments(['status', '--timeout-ms', 'NaN'])).toThrow('100–60000');
  });
});

async function socketServer(listener: (socket: Socket) => void): Promise<string> {
  const directory = mkdtempSync(join(tmpdir(), 'act-cli-'));
  const path = join(directory, 'socket');
  const server = createServer(listener) as Server;
  await new Promise<void>((fulfil, reject) => { server.once('error', reject); server.listen(path, fulfil); });
  cleanups.push(() => { server.close(); rmSync(directory, { recursive: true, force: true }); });
  return path;
}

test('socket client assembles fragmented UTF-8 responses and validates identity', async () => {
  const request: Request = { version: 1, requestID: 'r1', operation: 'status', parameters: {} };
  const path = await socketServer(client => {
    client.once('data', data => {
      expect(JSON.parse(data.toString()).requestID).toBe('r1');
      const bytes = Buffer.from(JSON.stringify({ version: 1, requestID: 'r1', operation: 'status', ok: true, result: 'Éva' }) + '\n');
      client.write(bytes.subarray(0, bytes.length - 4));
      setTimeout(() => client.end(bytes.subarray(bytes.length - 4)), 10);
    });
  });
  expect((await exchange(path, request, 1000)).result).toBe('Éva');
});

test('lost responses report uncertainty instead of automatically repeating writes', async () => {
  let count = 0;
  const path = await socketServer(client => { client.once('data', () => { count++; client.end(); }); });
  await expect(exchange(path, { version: 1, requestID: 'stable', operation: 'edits.apply', parameters: {} }, 1000)).rejects.toThrow('before returning a result');
  expect(count).toBe(1);
});
