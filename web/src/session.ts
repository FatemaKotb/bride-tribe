import { createContext, useContext } from 'react';
import type { ApiError, Home } from './contract';

export type SessionState =
  | { status: 'loading' }
  | { status: 'signed_out' }
  | { status: 'signed_in'; home: Home }
  | { status: 'failed'; error: ApiError };

export interface Session {
  state: SessionState;
  // Checks this phone's session and loads the home data.
  start: () => Promise<void>;
  // Reloads get_home, which also feeds the header on every screen.
  reloadHome: () => Promise<void>;
  signIn: (memberId: string) => Promise<ApiError | null>;
  switchMember: () => Promise<ApiError | null>;
}

export const SessionContext = createContext<Session | null>(null);

export function useSession(): Session {
  const session = useContext(SessionContext);
  if (!session) throw new Error('useSession must be used inside <SessionProvider>');
  return session;
}

// For screens that only render when signed in.
export function useHome(): Home {
  const { state } = useSession();
  if (state.status !== 'signed_in') throw new Error('useHome needs a signed-in member');
  return state.home;
}
