import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react';
import { call, supabase, UNEXPECTED, whenSignedOut } from './api';
import type { Home } from './contract';
import { SessionContext, type SessionState } from './session';

export function SessionProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<SessionState>({ status: 'loading' });

  const loadHome = useCallback(async () => {
    const { data, error } = await call<Home>('get_home');
    if (data) {
      setState({ status: 'signed_in', home: data });
      return null;
    }
    if (error.code === 'NOT_SIGNED_IN') setState({ status: 'signed_out' });
    // A failed refresh keeps what is already on screen.
    else setState((previous) => (previous.status === 'signed_in' ? previous : { status: 'failed', error }));
    return error;
  }, []);

  const check = useCallback(async () => {
    const { data } = await supabase.auth.getSession();
    if (data.session) await loadHome();
    else setState({ status: 'signed_out' });
  }, [loadHome]);

  const start = useCallback(async () => {
    setState({ status: 'loading' });
    await check();
  }, [check]);

  const reloadHome = useCallback(async () => {
    await loadHome();
  }, [loadHome]);

  // BR-03: reuse this phone's anonymous session while the server still
  // knows it; otherwise start a new one. Then link it to the member.
  const signIn = useCallback(
    async (memberId: string) => {
      const { data } = await supabase.auth.getUser();
      if (!data.user) {
        await supabase.auth.signOut({ scope: 'local' });
        const { error } = await supabase.auth.signInAnonymously();
        if (error) {
          console.error('signInAnonymously failed', error);
          return UNEXPECTED;
        }
      }
      const { error } = await call('sign_in', { member_id: memberId });
      if (error) return error;
      return loadHome();
    },
    [loadHome],
  );

  // "Not Sara? Switch": unlink the session and go back to the name list.
  // The anonymous session itself is kept for the next sign-in.
  const switchMember = useCallback(async () => {
    const { error } = await call('sign_out');
    if (error) return error;
    setState({ status: 'signed_out' });
    return null;
  }, []);

  useEffect(() => {
    whenSignedOut(() => setState({ status: 'signed_out' }));
    // check() sets state only after awaiting the stored session.
    // oxlint-disable-next-line react/set-state-in-effect
    void check();
  }, [check]);

  // The header shows my status on every screen, so refresh it whenever the
  // app comes back to the foreground.
  useEffect(() => {
    const onVisible = () => {
      if (!document.hidden && state.status === 'signed_in') void loadHome();
    };
    document.addEventListener('visibilitychange', onVisible);
    return () => document.removeEventListener('visibilitychange', onVisible);
  }, [loadHome, state.status]);

  const session = useMemo(
    () => ({ state, start, reloadHome, signIn, switchMember }),
    [state, start, reloadHome, signIn, switchMember],
  );

  return <SessionContext.Provider value={session}>{children}</SessionContext.Provider>;
}
