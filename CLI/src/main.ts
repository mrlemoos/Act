#!/usr/bin/env bun
import { Cause, Effect, Layer } from 'effect';
import { contract, operations } from '../contract';
import { parseArguments } from './arguments';
import { Automation, AutomationLive } from './client';
import { asCommandError, attempt, commandError } from './errors';
import { Platform, PlatformLive } from './platform';
import { decodeRequest, requestLimit, type Request, type Result } from './protocol';

export { parseArguments } from './arguments';
export { exchange } from './transport';
export type { Request, Result } from './protocol';

export const ServicesLive = AutomationLive.pipe(Layer.provideMerge(PlatformLive));

export function command(args: readonly string[], signal?: AbortSignal) {
  return Effect.suspend(() => {
    let request: Request | undefined;
    let dispatched = false;
    const work = Effect.gen(function* () {
      if (!args.length || args.includes('--help') || args[0] === 'help') {
        return { version: 1, requestID: null, operation: 'help', ok: true, result: { usage: 'act <family> <operation> [--json OBJECT|@FILE] [--document ID] [--revision REVISION] [--request-id ID]', raw: 'act call --stdin < request.json', examples: ['act schema', 'act documents list', 'act source read --document ID'], installation: 'act install [--directory PATH]', operations: Object.keys(operations) } } satisfies Result;
      }
      const platform = yield* Platform;
      if (args[0] === 'install') return yield* platform.install(args.slice(1));
      let timeout = 15000;
      if (args[0] === 'call') {
        if (args.length !== 2 || args[1] !== '--stdin') return yield* Effect.fail(commandError('invalid_arguments', 'Usage: act call --stdin < request.json'));
        const data = yield* platform.readStdin;
        request = yield* attempt(() => decodeRequest(JSON.parse(data)));
      } else ({ request, timeout } = yield* parseArguments(args));
      if (request.version !== 1) return yield* Effect.fail(commandError('unsupported_version', 'Supported protocol version: 1.'));
      if (Buffer.byteLength(JSON.stringify(request)) > requestLimit) return yield* Effect.fail(commandError('request_too_large', 'Request exceeds 4 MiB.'));
      if (request.operation === 'schema') return { version: 1, requestID: request.requestID, operation: 'schema', ok: true, result: contract } satisfies Result;
      const automation = yield* Automation;
      dispatched = true;
      return yield* automation.send(request, timeout);
    });
    const cancellation = Effect.callback<never, never>(resume => {
      if (!signal) return;
      const cancel = () => resume(Effect.interrupt);
      if (signal.aborted) cancel();
      else signal.addEventListener('abort', cancel, { once: true });
      return Effect.sync(() => signal.removeEventListener('abort', cancel));
    });
    // Render cancellation only after scoped resources have closed. Never claim a sent mutation failed.
    return Effect.uninterruptibleMask(restore => Effect.gen(function* () {
      const exit = yield* Effect.exit(restore(signal?.aborted ? Effect.interrupt : Effect.raceFirst(work, cancellation)));
      if (exit._tag === 'Success') return exit.value;
      const error = Cause.hasInterrupts(exit.cause)
        ? commandError(dispatched ? 'uncertain_outcome' : 'cancelled', dispatched
          ? `Interrupted. Inspect state and retry with requestID ${request?.requestID}; never blindly repeat a mutation.`
          : 'Command cancelled before submission.')
        : asCommandError(Cause.squash(exit.cause), 'internal_error');
      return { version: 1, requestID: request?.requestID ?? null, operation: request?.operation ?? null, ok: false, error: { code: error.code, message: error.message, retryable: false } } satisfies Result;
    }));
  });
}

export async function main(args: readonly string[], signal?: AbortSignal): Promise<number> {
  const program = Effect.uninterruptibleMask(restore => Effect.gen(function* () {
    const result = yield* restore(command(args, signal));
    yield* (yield* Platform).writeResult(result);
    return result.ok ? 0 : 1;
  })).pipe(Effect.provide(ServicesLive));
  const exit = await Effect.runPromiseExit(program);
  if (exit._tag === 'Success') return exit.value;
  process.stderr.write(asCommandError(Cause.squash(exit.cause), 'output_failed').message + '\n');
  return 1;
}

if (import.meta.main) {
  const controller = new AbortController();
  const cancel = () => controller.abort();
  process.once('SIGINT', cancel);
  process.once('SIGTERM', cancel);
  try { process.exitCode = await main(process.argv.slice(2), controller.signal); }
  finally {
    process.removeListener('SIGINT', cancel);
    process.removeListener('SIGTERM', cancel);
  }
}
