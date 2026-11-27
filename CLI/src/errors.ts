import { Data, Effect } from 'effect';

export class CommandError extends Data.TaggedError('CommandError')<{
  readonly code: string;
  readonly message: string;
}> {}

export const commandError = (code: string, message: string) => new CommandError({ code, message });

export function asCommandError(error: unknown, code = 'invalid_arguments'): CommandError {
  return error instanceof CommandError ? error : commandError(code, error instanceof Error ? error.message : String(error));
}

export const attempt = <A>(evaluate: () => A, code = 'invalid_arguments') =>
  Effect.try({ try: evaluate, catch: error => asCommandError(error, code) });
