import { connect } from 'node:net';
import { Effect } from 'effect';
import { attempt, commandError, type CommandError } from './errors';
import { decodeResponse, responseLimit, type Request, type Result } from './protocol';

export function exchange(socketPath: string, request: Request, timeout: number): Effect.Effect<Result, CommandError> {
  return Effect.suspend(() => {
    let sent = false;
    return Effect.scoped(Effect.gen(function* () {
      const client = yield* Effect.acquireRelease(
        attempt(() => connect(socketPath), 'connection_failed'),
        socket => Effect.sync(() => { socket.destroy(); }),
      );
      return yield* Effect.callback<Result, CommandError>(resume => {
        const chunks: string[] = [];
        let size = 0, done = false;
        const finish = (result: Effect.Effect<Result, CommandError>) => {
          if (done) return;
          done = true;
          resume(result);
        };
        client.setEncoding('utf8');
        client.once('connect', () => {
          // Once handed to the socket, a lost reply cannot prove whether Act applied it.
          sent = true;
          client.write(JSON.stringify(request) + '\n');
        });
        client.on('data', (chunk: string) => {
          if (done) return;
          size += Buffer.byteLength(chunk);
          if (size > responseLimit) {
            finish(Effect.fail(commandError('response_too_large', 'Response exceeded 32 MiB; read a single scene instead.')));
            return;
          }
          const end = chunk.indexOf('\n');
          chunks.push(end < 0 ? chunk : chunk.slice(0, end));
          if (end >= 0) finish(attempt(() => decodeResponse(chunks.join(''), request), 'invalid_response'));
        });
        client.once('error', error => finish(Effect.fail(commandError(sent ? 'uncertain_outcome' : 'connection_failed', error.message))));
        client.once('end', () => finish(Effect.fail(commandError(sent ? 'uncertain_outcome' : 'connection_failed', 'Act closed the connection before returning a result.'))));
      });
    })).pipe(Effect.timeoutOrElse({
      duration: timeout,
      orElse: () => Effect.fail(commandError(sent ? 'uncertain_outcome' : 'connection_timeout', `Timed out. Inspect state and retry with requestID ${request.requestID}; never blindly repeat a mutation.`)),
    }));
  });
}
