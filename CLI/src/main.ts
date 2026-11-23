#!/usr/bin/env bun
import { connect } from 'node:net';
import { spawn } from 'node:child_process';
import { existsSync, lstatSync, mkdirSync, readFileSync, realpathSync, symlinkSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { homedir } from 'node:os';
import { contract, operations } from '../contract';

export type Request = {
  version: number; requestID: string; operation: string;
  documentID?: string; expectedRevision?: string; parameters: Record<string, unknown>;
};
type Result = { version: number; requestID: string | null; operation: string | null; ok: boolean; result?: unknown; error?: { code: string; message: string; retryable: boolean } };

class CommandError extends Error {
  constructor(readonly code: string, message: string) { super(message); }
}

export function parseArguments(args: string[]): { request: Request; timeout: number } {
  const words: string[] = [], options = new Map<string, string>();
  for (let index = 0; index < args.length; index++) {
    const arg = args[index]!;
    if (arg.startsWith('--')) {
      if (!['--json', '--document', '--revision', '--request-id', '--timeout-ms'].includes(arg)) throw new CommandError('invalid_arguments', `Unknown option: ${arg}`);
      if (options.has(arg) || index + 1 === args.length) throw new CommandError('invalid_arguments', `Missing or repeated option: ${arg}`);
      options.set(arg, args[++index]!);
    } else words.push(arg);
  }
  const operation = words.join('.');
  if (!operations[operation]) throw new CommandError('unknown_operation', 'Use act schema to discover commands. Example: act documents list');
  let parameters: unknown = {};
  if (options.has('--json')) {
    const input = options.get('--json')!;
    parameters = JSON.parse(input.startsWith('@') ? readFileSync(input.slice(1), 'utf8') : input);
  }
  if (!parameters || typeof parameters !== 'object' || Array.isArray(parameters)) throw new CommandError('invalid_arguments', '--json must contain an object.');
  const timeout = Number(options.get('--timeout-ms') ?? '15000');
  if (!Number.isInteger(timeout) || timeout < 100 || timeout > 60000) throw new CommandError('invalid_arguments', '--timeout-ms must be 100–60000.');
  const request: Request = {
    version: 1, requestID: options.get('--request-id') ?? crypto.randomUUID(), operation,
    parameters: parameters as Record<string, unknown>,
  };
  if (options.has('--document')) request.documentID = options.get('--document');
  if (options.has('--revision')) request.expectedRevision = options.get('--revision');
  return { request, timeout };
}

export async function exchange(socketPath: string, request: Request, timeout: number): Promise<Result> {
  return new Promise((fulfil, reject) => {
    let data = '', sent = false, done = false;
    const client = connect(socketPath);
    const finish = (error?: Error, result?: Result) => {
      if (done) return; done = true; client.destroy();
      if (error) reject(error); else fulfil(result!);
    };
    client.setTimeout(timeout);
    client.setEncoding('utf8');
    client.on('connect', () => { sent = true; client.write(JSON.stringify(request) + '\n'); });
    client.on('data', (chunk: string) => {
      data += chunk;
      if (Buffer.byteLength(data) > 32 * 1024 * 1024) return finish(new CommandError('response_too_large', 'Response exceeded 32 MiB; read a single scene instead.'));
      const end = data.indexOf('\n');
      if (end < 0) return;
      try {
        const result = JSON.parse(data.slice(0, end)) as Result;
        if (result.version !== 1 || result.requestID !== request.requestID || result.operation !== request.operation || typeof result.ok !== 'boolean') throw new Error('Response does not match this request.');
        finish(undefined, result);
      } catch (error) { finish(new CommandError('invalid_response', String(error))); }
    });
    client.on('timeout', () => finish(new CommandError(sent ? 'uncertain_outcome' : 'connection_timeout', `Timed out. Inspect state and retry with requestID ${request.requestID}; never blindly repeat a mutation.`)));
    client.on('error', error => finish(new CommandError(sent ? 'uncertain_outcome' : 'connection_failed', error.message)));
    client.on('end', () => { if (!done) finish(new CommandError(sent ? 'uncertain_outcome' : 'connection_failed', 'Act closed the connection before returning a result.')); });
  });
}

function endpoint(directory: string): string {
  const dir = lstatSync(directory);
  if (!dir.isDirectory() || dir.uid !== process.getuid!() || (dir.mode & 0o077) !== 0) throw new CommandError('invalid_endpoint', 'Automation directory must be private and owned by your account.');
  const manifest = join(directory, 'endpoint.json');
  if (!lstatSync(manifest).isFile()) throw new CommandError('invalid_endpoint', 'Endpoint manifest must be a regular file.');
  const value = JSON.parse(readFileSync(manifest, 'utf8')) as { version: number; socketPath: string };
  if (value.version !== 1 || typeof value.socketPath !== 'string') throw new CommandError('invalid_endpoint', 'Unsupported endpoint discovery format.');
  const socket = lstatSync(value.socketPath);
  if (!socket.isSocket() || socket.uid !== process.getuid!() || (socket.mode & 0o077) !== 0) throw new CommandError('invalid_endpoint', 'Socket must be private and owned by your account.');
  return value.socketPath;
}

function bundledApp(): string {
  if (process.env.ACT_APP_PATH) return resolve(process.env.ACT_APP_PATH);
  const candidate = resolve(dirname(realpathSync(process.execPath)), '../..');
  if (candidate.endsWith('.app')) return candidate;
  return resolve(import.meta.dir, '../../.build/Act.app');
}

async function send(request: Request, timeout: number): Promise<Result> {
  const directory = process.env.ACT_AUTOMATION_DIRECTORY ?? join(homedir(), 'Library/Application Support/Act/Automation');
  try { return await exchange(endpoint(directory), request, timeout); }
  catch (error) {
    if (error instanceof CommandError && error.code !== 'connection_failed') throw error;
    if (!(error instanceof CommandError) && (error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
  }
  const app = bundledApp();
  if (!existsSync(app)) throw new CommandError('app_not_found', 'Build/install Act first, or provide ACT_APP_PATH pointing to Act.app.');
  const launchArguments = ['--automation-background'];
  // Isolated validation endpoints must not restore the writer's ordinary app session.
  if (process.env.ACT_AUTOMATION_DIRECTORY) launchArguments.push('-ApplePersistenceIgnoreState', 'YES');
  const child = spawn(join(app, 'Contents/MacOS/Act'), launchArguments, { detached: true, stdio: 'ignore', env: process.env });
  await new Promise<void>((fulfil, reject) => {
    child.once('spawn', fulfil);
    child.once('error', error => reject(new CommandError('launch_failed', error.message)));
  });
  child.unref();
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    try { return await exchange(endpoint(directory), request, Math.max(100, deadline - Date.now())); }
    catch (error) {
      if (error instanceof CommandError && error.code !== 'connection_failed') throw error;
      if (!(error instanceof CommandError) && (error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
    }
    await Bun.sleep(100);
  }
  throw new CommandError('launch_timeout', 'Act did not publish an automation endpoint. Check the running app and its Automation window.');
}

function install(args: string[]): Result {
  if (args.length !== 0 && (args.length !== 2 || args[0] !== '--directory')) throw new CommandError('invalid_arguments', 'Usage: act install [--directory /path/to/bin]');
  const directory = resolve(args[1] ?? join(homedir(), '.local/bin'));
  mkdirSync(directory, { recursive: true });
  const destination = join(directory, 'act'), source = realpathSync(process.execPath);
  if (existsSync(destination)) {
    if (realpathSync(destination) !== source) throw new CommandError('name_collision', 'Destination already exists; no command was replaced.');
  } else symlinkSync(source, destination);
  return { version: 1, requestID: null, operation: 'install', ok: true, result: { path: destination, target: source, pathModified: false } };
}

export async function main(args: string[]): Promise<number> {
  let request: Request | undefined;
  try {
    let result: Result;
    if (!args.length || args.includes('--help') || args[0] === 'help') {
      result = { version: 1, requestID: null, operation: 'help', ok: true, result: { usage: 'act <family> <operation> [--json OBJECT|@FILE] [--document ID] [--revision REVISION] [--request-id ID]', raw: 'act call --stdin < request.json', examples: ['act schema', 'act documents list', 'act source read --document ID'], installation: 'act install [--directory PATH]', operations: Object.keys(operations) } };
    } else if (args[0] === 'install') result = install(args.slice(1));
    else {
      let timeout = 15000;
      if (args[0] === 'call') {
        if (args.length !== 2 || args[1] !== '--stdin') throw new CommandError('invalid_arguments', 'Usage: act call --stdin < request.json');
        const data = await Bun.stdin.text();
        if (Buffer.byteLength(data) > 4 * 1024 * 1024) throw new CommandError('request_too_large', 'Request exceeds 4 MiB.');
        request = JSON.parse(data) as Request;
        if (!request || typeof request.requestID !== 'string' || typeof request.operation !== 'string') throw new CommandError('invalid_arguments', 'Invalid request envelope. See act schema.');
      } else ({ request, timeout } = parseArguments(args));
      if (request.version !== 1) throw new CommandError('unsupported_version', 'Supported protocol version: 1.');
      if (Buffer.byteLength(JSON.stringify(request)) > 4 * 1024 * 1024) throw new CommandError('request_too_large', 'Request exceeds 4 MiB.');
      result = request.operation === 'schema'
        ? { version: 1, requestID: request.requestID, operation: 'schema', ok: true, result: contract }
        : await send(request, timeout);
    }
    process.stdout.write(JSON.stringify(result) + '\n');
    return result.ok ? 0 : 1;
  } catch (error) {
    process.stdout.write(JSON.stringify({ version: 1, requestID: request?.requestID ?? null, operation: request?.operation ?? null, ok: false, error: { code: error instanceof CommandError ? error.code : 'invalid_arguments', message: error instanceof Error ? error.message : String(error), retryable: false } }) + '\n');
    return 1;
  }
}

if (import.meta.main) process.exitCode = await main(process.argv.slice(2));
