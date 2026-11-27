import { afterEach, describe, expect, test } from 'bun:test';
import { createServer, type Server, type Socket } from 'node:net';
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { Effect } from 'effect';
import { command, exchange, parseArguments, ServicesLive, type Request } from './main';
import { Automation, AutomationLive } from './client';
import { commandError } from './errors';
import { Platform, PlatformLive } from './platform';

const cleanups: (() => void)[] = [];
afterEach(() => { for (const cleanup of cleanups.splice(0)) cleanup(); });

describe('command contract', () => {
  test('literal prompts and explicit identity survive argument parsing', async () => {
    const prompt = 'Keep $HOME, `literal`, emoji 🎬 and\nline breaks.';
    const { request } = await Effect.runPromise(parseArguments(['images', 'prepare', '--document', 'doc', '--revision', 'rev', '--request-id', 'once', '--json', JSON.stringify({ targetKind: 'shot', targetID: 'shot', prompt })]).pipe(Effect.provide(ServicesLive)));
    expect(request.parameters.prompt).toBe(prompt);
    expect(request.operation).toBe('images.prepare');
    expect(request.requestID).toBe('once');
    expect(request.expectedRevision).toBe('rev');
  });
  test('unknown flags and malformed parameters fail before launch', async () => {
    await expect(Effect.runPromise(parseArguments(['documents', 'list', '--approve', 'yes']).pipe(Effect.provide(ServicesLive)))).rejects.toThrow('Unknown option');
    await expect(Effect.runPromise(parseArguments(['documents', 'list', '--json', '[]']).pipe(Effect.provide(ServicesLive)))).rejects.toThrow('must contain an object');
    await expect(Effect.runPromise(parseArguments(['status', '--timeout-ms', 'NaN']).pipe(Effect.provide(ServicesLive)))).rejects.toThrow('100–60000');
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
      const split = bytes.indexOf(Buffer.from('É')) + 1;
      client.write(bytes.subarray(0, split));
      setTimeout(() => client.end(bytes.subarray(split)), 10);
    });
  });
  expect((await Effect.runPromise(exchange(path, request, 1000))).result).toBe('Éva');
});

test('lost responses report uncertainty instead of automatically repeating writes', async () => {
  let count = 0;
  const path = await socketServer(client => { client.once('data', () => { count++; client.end(); }); });
  await expect(Effect.runPromise(exchange(path, { version: 1, requestID: 'stable', operation: 'edits.apply', parameters: {} }, 1000))).rejects.toThrow('before returning a result');
  expect(count).toBe(1);
});

const request: Request = { version: 1, requestID: 'stable', operation: 'edits.apply', parameters: {} };

async function invoke(args: string[], input?: string, environment: Record<string, string> = {}) {
  const child = Bun.spawn([process.execPath, join(import.meta.dir, 'main.ts'), ...args], {
    env: { ...process.env, ACT_APP_PATH: '/missing/Act.app', ...environment },
    stdin: input === undefined ? 'ignore' : new Response(input), stdout: 'pipe', stderr: 'pipe',
  });
  const [stdout, stderr, code] = await Promise.all([new Response(child.stdout).text(), new Response(child.stderr).text(), child.exited]);
  expect(stderr).toBe('');
  expect(stdout.trim().split('\n')).toHaveLength(1);
  return { code, response: JSON.parse(stdout) };
}

test('JSON files retain literal input and schema/help run without Act', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'act-arguments-'));
  cleanups.push(() => rmSync(directory, { recursive: true, force: true }));
  const path = join(directory, 'input.json');
  const parameters = { prompt: 'Éva\n$HOME `literal`' };
  writeFileSync(path, JSON.stringify(parameters));
  const parsed = await Effect.runPromise(parseArguments(['images.prepare', '--json', '@' + path]).pipe(Effect.provide(PlatformLive)));
  expect(parsed.request.parameters).toEqual(parameters);
  for (const args of [[], ['help'], ['--help'], ['schema']]) {
    const { code, response } = await invoke(args);
    expect(code).toBe(0);
    expect(response.ok).toBe(true);
  }
});

test('raw envelopes fail locally with structured JSON and retain valid request identity', async () => {
  for (const parameters of [[], null, 'text']) {
    const { code, response } = await invoke(['call', '--stdin'], JSON.stringify({ ...request, parameters }));
    expect(code).toBe(1);
    expect(response.error.code).toBe('invalid_arguments');
  }
  const unsupported = await invoke(['call', '--stdin'], JSON.stringify({ ...request, version: 2 }));
  expect(unsupported.response).toMatchObject({ requestID: 'stable', operation: 'edits.apply', ok: false, error: { code: 'unsupported_version', retryable: false } });
  const oversized = await invoke(['call', '--stdin'], ' '.repeat(4 * 1024 * 1024 + 1));
  expect(oversized.response.error.code).toBe('request_too_large');
  const malformed = await invoke(['status', '--json', '{']);
  expect(malformed.response.error.code).toBe('invalid_arguments');
});

test.each([
  '{broken',
  'null',
  JSON.stringify({ ...request, requestID: 'different', ok: true }),
  JSON.stringify({ ...request, operation: 'status', ok: true }),
  JSON.stringify({ ...request, version: 2, ok: true }),
  JSON.stringify({ ...request, ok: 'true' }),
  JSON.stringify({ ...request, ok: false }),
])('invalid response fails without replay: %s', async text => {
  let count = 0;
  const path = await socketServer(client => client.once('data', () => { count++; client.end(text + '\n'); }));
  const result = await Effect.runPromise(exchange(path, request, 1000).pipe(Effect.result));
  expect(result._tag).toBe('Failure');
  if (result._tag === 'Failure') expect(result.failure.code).toBe('invalid_response');
  expect(count).toBe(1);
});

test('server errors retain their structured code and persistence details survive success', async () => {
  for (const fields of [
    { ok: false, error: { code: 'revision_conflict', message: 'Writing changed.', retryable: false } },
    { ok: true, result: { revision: 'next', persistence: 'pending' } },
  ]) {
    const response = { version: 1, requestID: request.requestID, operation: request.operation, ...fields };
    const path = await socketServer(client => client.once('data', () => client.end(JSON.stringify(response) + '\n')));
    expect(await Effect.runPromise(exchange(path, request, 1000))).toEqual(response);
  }
});

test('timeout bounds the whole exchange even when bytes keep arriving and closes the socket', async () => {
  let count = 0;
  let closed!: () => void;
  const connectionClosed = new Promise<void>(resolve => { closed = resolve; });
  const path = await socketServer(client => {
    client.once('data', () => { count++; });
    const timer = setInterval(() => client.write(' '), 10);
    client.once('close', () => { clearInterval(timer); closed(); });
  });
  const result = await Effect.runPromise(exchange(path, request, 80).pipe(Effect.result));
  expect(result._tag).toBe('Failure');
  if (result._tag === 'Failure') expect(result.failure.code).toBe('uncertain_outcome');
  await connectionClosed;
  expect(count).toBe(1);
});

test('interrupting an Effect exchange releases its socket', async () => {
  const controller = new AbortController();
  let closed!: () => void;
  const connectionClosed = new Promise<void>(resolve => { closed = resolve; });
  const path = await socketServer(client => {
    client.once('data', () => controller.abort());
    client.once('close', closed);
  });
  const exit = await Effect.runPromiseExit(exchange(path, request, 1000), { signal: controller.signal });
  expect(exit._tag).toBe('Failure');
  await connectionClosed;
});

test('CLI cancellation returns one uncertain result with original identity and never replays', async () => {
  let child: Bun.Subprocess<'ignore', 'pipe', 'pipe'>;
  let count = 0;
  const path = await socketServer(client => client.once('data', () => { count++; child.kill('SIGTERM'); }));
  const directory = dirname(path);
  chmodSync(directory, 0o700); chmodSync(path, 0o600);
  writeFileSync(join(directory, 'endpoint.json'), JSON.stringify({ version: 1, socketPath: path }));
  child = Bun.spawn([process.execPath, join(import.meta.dir, 'main.ts'), 'edits', 'apply', '--request-id', request.requestID], {
    env: { ...process.env, ACT_AUTOMATION_DIRECTORY: directory, ACT_APP_PATH: '/missing/Act.app' }, stdin: 'ignore', stdout: 'pipe', stderr: 'pipe',
  });
  const [stdout, stderr, code] = await Promise.all([new Response(child.stdout).text(), new Response(child.stderr).text(), child.exited]);
  expect(code).toBe(1);
  expect(stderr).toBe('');
  expect(JSON.parse(stdout)).toMatchObject({ requestID: 'stable', operation: 'edits.apply', ok: false, error: { code: 'uncertain_outcome', retryable: false } });
  expect(count).toBe(1);
});

test('oversized response closes transport with explicit error', async () => {
  const path = await socketServer(client => {
    client.on('error', () => {});
    client.once('data', () => client.end(' '.repeat(32 * 1024 * 1024 + 1)));
  });
  const result = await Effect.runPromise(exchange(path, request, 15000).pipe(Effect.result));
  expect(result._tag).toBe('Failure');
  if (result._tag === 'Failure') expect(result.failure.code).toBe('response_too_large');
}, 20000);

test('invalid endpoint permissions stop before launch or submission', async () => {
  let count = 0;
  const path = await socketServer(client => client.once('data', () => { count++; }));
  const directory = dirname(path);
  chmodSync(directory, 0o755);
  writeFileSync(join(directory, 'endpoint.json'), JSON.stringify({ version: 1, socketPath: path }));
  const { response } = await invoke(['status'], undefined, { ACT_AUTOMATION_DIRECTORY: directory });
  expect(response.error.code).toBe('invalid_endpoint');
  expect(count).toBe(0);
});

test('discovery recovery launches once and only retries before submission', async () => {
  let launches = 0, sends = 0;
  const path = await socketServer(client => client.once('data', () => {
    sends++;
    client.end(JSON.stringify({ version: 1, requestID: request.requestID, operation: request.operation, ok: true }) + '\n');
  }));
  const response = await Effect.runPromise(Effect.gen(function* () {
    const platform = yield* Platform;
    const send = Effect.flatMap(Automation, client => client.send(request, 1000));
    return yield* send.pipe(Effect.provide(AutomationLive), Effect.provideService(Platform, {
      ...platform,
      endpoint: Effect.suspend(() => launches ? Effect.succeed(path) : Effect.fail(commandError('endpoint_unavailable', 'Not running.'))),
      launch: Effect.sync(() => { launches++; }),
    }));
  }).pipe(Effect.provide(PlatformLive)));
  expect(response.ok).toBe(true);
  expect(launches).toBe(1);
  expect(sends).toBe(1);
});

test('lost mutation replies never trigger app launch or a second submission', async () => {
  let launches = 0, sends = 0;
  const path = await socketServer(client => client.once('data', () => { sends++; client.end(); }));
  const result = await Effect.runPromise(Effect.gen(function* () {
    const platform = yield* Platform;
    return yield* Effect.flatMap(Automation, client => client.send(request, 1000)).pipe(
      Effect.provide(AutomationLive),
      Effect.provideService(Platform, { ...platform, endpoint: Effect.succeed(path), launch: Effect.sync(() => { launches++; }) }),
      Effect.result,
    );
  }).pipe(Effect.provide(PlatformLive)));
  expect(result._tag).toBe('Failure');
  if (result._tag === 'Failure') expect(result.failure.code).toBe('uncertain_outcome');
  expect(sends).toBe(1);
  expect(launches).toBe(0);
});

test('startup deadline expires when no endpoint appears', async () => {
  let launches = 0;
  const result = await Effect.runPromise(Effect.gen(function* () {
    const platform = yield* Platform;
    return yield* Effect.flatMap(Automation, client => client.send(request, 100)).pipe(
      Effect.provide(AutomationLive),
      Effect.provideService(Platform, {
        ...platform,
        endpoint: Effect.fail(commandError('endpoint_unavailable', 'Not running.')),
        launch: Effect.sync(() => { launches++; }),
      }),
      Effect.result,
    );
  }).pipe(Effect.provide(PlatformLive)));
  expect(result._tag).toBe('Failure');
  if (result._tag === 'Failure') expect(result.failure.code).toBe('launch_timeout');
  expect(launches).toBe(1);
});

test('a command cancelled before execution never submits', async () => {
  const controller = new AbortController(); controller.abort();
  const response = await Effect.runPromise(command(['edits', 'apply'], controller.signal).pipe(Effect.provide(ServicesLive)));
  expect(response).toMatchObject({ ok: false, error: { code: 'cancelled', retryable: false } });
});
