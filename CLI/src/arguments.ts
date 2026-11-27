import { Effect } from 'effect';
import { operations } from '../contract';
import { attempt, commandError } from './errors';
import { Platform } from './platform';
import type { Request } from './protocol';

export function parseArguments(args: readonly string[]) {
  return Effect.gen(function* () {
    const { operation, options } = yield* attempt(() => {
      const words: string[] = [], options = new Map<string, string>();
      for (let index = 0; index < args.length; index++) {
        const arg = args[index]!;
        if (arg.startsWith('--')) {
          if (!['--json', '--document', '--revision', '--request-id', '--timeout-ms'].includes(arg)) throw commandError('invalid_arguments', `Unknown option: ${arg}`);
          if (options.has(arg) || index + 1 === args.length) throw commandError('invalid_arguments', `Missing or repeated option: ${arg}`);
          options.set(arg, args[++index]!);
        } else words.push(arg);
      }
      const operation = words.join('.');
      if (!operations[operation]) throw commandError('unknown_operation', 'Use act schema to discover commands. Example: act documents list');
      return { operation, options };
    });
    let parameters: unknown = {};
    const input = options.get('--json');
    if (input !== undefined) {
      const text = input.startsWith('@') ? yield* (yield* Platform).readText(input.slice(1)) : input;
      parameters = yield* attempt(() => JSON.parse(text) as unknown);
    }
    if (!parameters || typeof parameters !== 'object' || Array.isArray(parameters)) {
      return yield* Effect.fail(commandError('invalid_arguments', '--json must contain an object.'));
    }
    const timeout = Number(options.get('--timeout-ms') ?? '15000');
    if (!Number.isInteger(timeout) || timeout < 100 || timeout > 60000) {
      return yield* Effect.fail(commandError('invalid_arguments', '--timeout-ms must be 100–60000.'));
    }
    const request: Request = {
      version: 1, requestID: options.get('--request-id') ?? crypto.randomUUID(), operation,
      parameters: parameters as Record<string, unknown>,
    };
    if (options.has('--document')) request.documentID = options.get('--document');
    if (options.has('--revision')) request.expectedRevision = options.get('--revision');
    return { request, timeout };
  });
}
