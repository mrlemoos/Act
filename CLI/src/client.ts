import { Clock, Context, Effect, Layer } from 'effect';
import { commandError, type CommandError } from './errors';
import { Platform } from './platform';
import type { Request, Result } from './protocol';
import { exchange } from './transport';

export class Automation extends Context.Service<Automation, {
  readonly send: (request: Request, timeout: number) => Effect.Effect<Result, CommandError>;
}>()('act/Automation') {}

const canLaunch = (error: CommandError) => error.code === 'connection_failed' || error.code === 'endpoint_unavailable';

export const AutomationLive = Layer.effect(Automation, Effect.gen(function* () {
  const platform = yield* Platform;
  return Automation.of({
    send: (request, timeout) => Effect.gen(function* () {
      const connect = (remaining: number) => Effect.flatMap(platform.endpoint, path => exchange(path, request, remaining));
      const first = yield* connect(timeout).pipe(Effect.result);
      if (first._tag === 'Success') return first.success;
      if (!canLaunch(first.failure)) return yield* Effect.fail(first.failure);
      yield* platform.launch;
      const deadline = (yield* Clock.currentTimeMillis) + timeout;
      while (true) {
        const remaining = deadline - (yield* Clock.currentTimeMillis);
        if (remaining <= 0) return yield* Effect.fail(commandError('launch_timeout', 'Act did not publish an automation endpoint. Check the running app and its Automation window.'));
        const response = yield* connect(remaining).pipe(Effect.result);
        if (response._tag === 'Success') return response.success;
        // Only discovery/connect failures are safe to repeat. A sent request is never replayed here.
        if (!canLaunch(response.failure)) return yield* Effect.fail(response.failure);
        yield* Effect.sleep(Math.min(100, remaining));
      }
    }),
  });
}));
