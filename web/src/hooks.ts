import { useCallback, useEffect, useRef, useState } from 'react';
import { useLocation, useNavigate } from 'react-router';
import { call } from './api';
import type { ApiError, Args } from './contract';

export interface Loaded<T> {
  data?: T;
  error?: ApiError;
  loading: boolean;
  reload: () => Promise<void>;
}

// Calls a read function and keeps its latest result. The previous result
// stays on screen while a reload runs, such as after a filter tap. Screens
// reload when the app comes back to the foreground, unless
// `refreshOnFocus` is false (forms, which would lose what was typed).
export function useLoad<T>(fn: string, args: Args, refreshOnFocus = true): Loaded<T> {
  const argsKey = JSON.stringify(args);
  const [result, setResult] = useState<{ key: string; data?: T; error?: ApiError } | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const latest = useRef(0);

  const fetchLatest = useCallback(async () => {
    const request = ++latest.current;
    const { data, error } = await call<T>(fn, JSON.parse(argsKey) as Args);
    // A newer request (say, after another filter tap) wins.
    if (request !== latest.current) return;
    setResult(error ? { key: argsKey, error } : { key: argsKey, data });
    setRefreshing(false);
  }, [fn, argsKey]);

  useEffect(() => {
    void fetchLatest();
  }, [fetchLatest]);

  const reload = useCallback(async () => {
    setRefreshing(true);
    await fetchLatest();
  }, [fetchLatest]);

  useEffect(() => {
    if (!refreshOnFocus) return;
    const onVisible = () => {
      if (!document.hidden) void reload();
    };
    document.addEventListener('visibilitychange', onVisible);
    return () => document.removeEventListener('visibilitychange', onVisible);
  }, [reload, refreshOnFocus]);

  return {
    data: result?.data,
    error: result?.error,
    loading: refreshing || result?.key !== argsKey,
    reload,
  };
}

// Goes back to the previous screen, or home when there is none (for
// example, when a form was opened from a bookmark).
export function useBack() {
  const navigate = useNavigate();
  const location = useLocation();
  return useCallback(() => {
    if (location.key === 'default') void navigate('/', { replace: true });
    else void navigate(-1);
  }, [navigate, location.key]);
}

export function formPath(form: { name: string; context: Args }) {
  const params = new URLSearchParams({ context: JSON.stringify(form.context) });
  return `/form/${encodeURIComponent(form.name)}?${params}`;
}

export function detailPath(open: { detail: string; id: string }) {
  return `/${encodeURIComponent(open.detail)}/${encodeURIComponent(open.id)}`;
}
