import { Affix, Notification, Stack } from '@mantine/core';
import { useSyncExternalStore } from 'react';
import { dismissToast, getToasts, subscribeToasts } from '../toast';

// Error messages from actions (contract Section 1: shown as is).
export function Toaster() {
  const toasts = useSyncExternalStore(subscribeToasts, getToasts);
  return (
    <Affix position={{ top: 72, left: 16, right: 16 }} zIndex={400}>
      <Stack gap="xs" maw={500} mx="auto">
        {toasts.map((toast) => (
          <Notification key={toast.id} color="red" withBorder onClose={() => dismissToast(toast.id)}>
            {toast.message}
          </Notification>
        ))}
      </Stack>
    </Affix>
  );
}
