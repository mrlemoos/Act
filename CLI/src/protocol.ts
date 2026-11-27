import { Schema } from 'effect';
import { commandError } from './errors';

export type Request = {
  version: number; requestID: string; operation: string;
  documentID?: string; expectedRevision?: string; parameters: Record<string, unknown>;
};
export type Result = {
  version: number; requestID: string | null; operation: string | null; ok: boolean;
  result?: unknown; error?: { code: string; message: string; retryable: boolean };
};

const requestSchema = Schema.Struct({
  version: Schema.Number,
  requestID: Schema.String,
  operation: Schema.String,
  documentID: Schema.optionalKey(Schema.String),
  expectedRevision: Schema.optionalKey(Schema.String),
  parameters: Schema.Record(Schema.String, Schema.Unknown),
});
const resultSchema = Schema.Struct({
  version: Schema.Literal(1),
  requestID: Schema.String,
  operation: Schema.String,
  ok: Schema.Boolean,
  result: Schema.optionalKey(Schema.Unknown),
  error: Schema.optionalKey(Schema.Struct({ code: Schema.String, message: Schema.String, retryable: Schema.Boolean })),
});

export const requestLimit = 4 * 1024 * 1024;
export const responseLimit = 32 * 1024 * 1024;

export function decodeRequest(value: unknown): Request {
  try { return Schema.decodeUnknownSync(requestSchema)(value); }
  catch { throw commandError('invalid_arguments', 'Invalid request envelope. See act schema.'); }
}

export function decodeResponse(text: string, request: Request): Result {
  try {
    const original: unknown = JSON.parse(text);
    const value = Schema.decodeUnknownSync(resultSchema)(original);
    if (value.requestID !== request.requestID || value.operation !== request.operation || (!value.ok && !value.error)) {
      throw new Error('Response does not match this request.');
    }
    return original as Result;
  } catch (error) {
    throw commandError('invalid_response', String(error));
  }
}
