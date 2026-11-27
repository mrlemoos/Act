import { spawn } from 'node:child_process';
import { existsSync, lstatSync, mkdirSync, readFileSync, realpathSync, symlinkSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { homedir } from 'node:os';
import { Context, Effect, Layer } from 'effect';
import { attempt, asCommandError, commandError, type CommandError } from './errors';
import { requestLimit, type Result } from './protocol';

export class Platform extends Context.Service<Platform, {
  readonly endpoint: Effect.Effect<string, CommandError>;
  readonly launch: Effect.Effect<void, CommandError>;
  readonly readText: (path: string) => Effect.Effect<string, CommandError>;
  readonly readStdin: Effect.Effect<string, CommandError>;
  readonly install: (args: readonly string[]) => Effect.Effect<Result, CommandError>;
  readonly writeResult: (result: Result) => Effect.Effect<void, CommandError>;
}>()('act/Platform') {}

function endpoint(directory: string): string {
  const dir = lstatSync(directory);
  if (!dir.isDirectory() || dir.uid !== process.getuid!() || (dir.mode & 0o077) !== 0) throw commandError('invalid_endpoint', 'Automation directory must be private and owned by your account.');
  const manifest = join(directory, 'endpoint.json');
  if (!lstatSync(manifest).isFile()) throw commandError('invalid_endpoint', 'Endpoint manifest must be a regular file.');
  const value: unknown = JSON.parse(readFileSync(manifest, 'utf8'));
  if (!value || typeof value !== 'object' || !('version' in value) || value.version !== 1 || !('socketPath' in value) || typeof value.socketPath !== 'string') {
    throw commandError('invalid_endpoint', 'Unsupported endpoint discovery format.');
  }
  const socket = lstatSync(value.socketPath);
  if (!socket.isSocket() || socket.uid !== process.getuid!() || (socket.mode & 0o077) !== 0) throw commandError('invalid_endpoint', 'Socket must be private and owned by your account.');
  return value.socketPath;
}

function bundledApp(): string {
  if (process.env.ACT_APP_PATH) return resolve(process.env.ACT_APP_PATH);
  const candidate = resolve(dirname(realpathSync(process.execPath)), '../..');
  if (candidate.endsWith('.app')) return candidate;
  return resolve(import.meta.dir, '../../.build/Act.app');
}

function install(args: readonly string[]): Result {
  if (args.length !== 0 && (args.length !== 2 || args[0] !== '--directory')) throw commandError('invalid_arguments', 'Usage: act install [--directory /path/to/bin]');
  const directory = resolve(args[1] ?? join(homedir(), '.local/bin'));
  mkdirSync(directory, { recursive: true });
  const destination = join(directory, 'act'), source = realpathSync(process.execPath);
  if (existsSync(destination)) {
    if (realpathSync(destination) !== source) throw commandError('name_collision', 'Destination already exists; no command was replaced.');
  } else symlinkSync(source, destination);
  return { version: 1, requestID: null, operation: 'install', ok: true, result: { path: destination, target: source, pathModified: false } };
}

export const PlatformLive = Layer.sync(Platform, () => {
  const directory = process.env.ACT_AUTOMATION_DIRECTORY ?? join(homedir(), 'Library/Application Support/Act/Automation');
  return Platform.of({
    endpoint: Effect.try({
      try: () => endpoint(directory),
      catch: error => (error as NodeJS.ErrnoException)?.code === 'ENOENT'
        ? commandError('endpoint_unavailable', 'Act has not published an automation endpoint.')
        : asCommandError(error, 'invalid_endpoint'),
    }),
    launch: Effect.gen(function* () {
      const app = yield* attempt(bundledApp, 'app_not_found');
      if (!existsSync(app)) return yield* Effect.fail(commandError('app_not_found', 'Build/install Act first, or provide ACT_APP_PATH pointing to Act.app.'));
      const args = ['--automation-background'];
      // Isolated validation endpoints must not restore the writer's ordinary app session.
      if (process.env.ACT_AUTOMATION_DIRECTORY) args.push('-ApplePersistenceIgnoreState', 'YES');
      yield* Effect.callback<void, CommandError>(resume => {
        const child = spawn(join(app, 'Contents/MacOS/Act'), args, { detached: true, stdio: 'ignore', env: process.env });
        child.unref();
        child.once('spawn', () => resume(Effect.void));
        child.once('error', error => resume(Effect.fail(commandError('launch_failed', error.message))));
      });
    }),
    readText: path => Effect.tryPromise({ try: signal => readFile(path, { encoding: 'utf8', signal }), catch: asCommandError }),
    readStdin: Effect.scoped(Effect.gen(function* () {
      const reader = yield* Effect.acquireRelease(
        attempt(() => Bun.stdin.stream().getReader()),
        reader => Effect.promise(async () => { try { await reader.cancel(); } finally { reader.releaseLock(); } }),
      );
      const chunks: Uint8Array[] = [];
      let size = 0;
      while (true) {
        const chunk = yield* Effect.tryPromise({ try: () => reader.read(), catch: asCommandError });
        if (chunk.done) return Buffer.concat(chunks).toString('utf8');
        size += chunk.value.byteLength;
        if (size > requestLimit) return yield* Effect.fail(commandError('request_too_large', 'Request exceeds 4 MiB.'));
        chunks.push(chunk.value);
      }
    })),
    install: args => attempt(() => install(args)),
    writeResult: result => Effect.callback<void, CommandError>(resume => {
      process.stdout.write(JSON.stringify(result) + '\n', error => resume(error ? Effect.fail(asCommandError(error, 'output_failed')) : Effect.void));
    }),
  });
});
