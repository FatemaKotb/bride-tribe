import { createClient } from '@supabase/supabase-js';
import type { ApiError, Args, Envelope } from './contract';

const url = import.meta.env.VITE_SUPABASE_URL;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  throw new Error('Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY (see web/.env.example).');
}

// The client keeps the anonymous session on the phone and sends it with
// every call, so a member signs in only once (BR-03).
export const supabase = createClient(url, anonKey);

export const UNEXPECTED: ApiError = {
  code: 'UNEXPECTED',
  message: 'Something went wrong. Please try again.',
};

// Called when the backend says the session isn't linked to a member.
let onSignedOut: () => void = () => {};
export function whenSignedOut(handler: () => void) {
  onSignedOut = handler;
}

// Calls a contract function and returns the contract's envelope. The
// backend puts the error code in `hint` and the user-facing text in
// `message`; anything without a code is unexpected.
export async function call<T>(fn: string, args: Args = {}): Promise<Envelope<T>> {
  try {
    const { data, error } = await supabase.rpc(fn, args);
    if (error) {
      if (!error.hint) {
        console.error(`${fn} failed`, error);
        return { error: UNEXPECTED };
      }
      if (error.hint === 'NOT_SIGNED_IN') onSignedOut();
      return { error: { code: error.hint, message: error.message } };
    }
    return { data: data as T };
  } catch (thrown) {
    console.error(`${fn} failed`, thrown);
    return { error: UNEXPECTED };
  }
}
