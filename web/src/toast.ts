// A small store for error toasts, shown by <Toaster />.
export interface Toast {
  id: number;
  message: string;
}

let toasts: Toast[] = [];
let nextId = 1;
const listeners = new Set<() => void>();

function emit() {
  for (const listener of listeners) listener();
}

export function showToast(message: string) {
  const id = nextId++;
  toasts = [...toasts, { id, message }];
  emit();
  setTimeout(() => dismissToast(id), 6000);
}

export function dismissToast(id: number) {
  toasts = toasts.filter((t) => t.id !== id);
  emit();
}

export function subscribeToasts(listener: () => void) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function getToasts() {
  return toasts;
}
