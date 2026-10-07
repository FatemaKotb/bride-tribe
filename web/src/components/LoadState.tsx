import { Alert, Button, Center, Loader, Stack } from '@mantine/core';
import type { ReactNode } from 'react';
import type { Loaded } from '../hooks';

// Shows a spinner until the first result arrives, and the backend's
// message when the call fails.
export function LoadState<T>({ loaded, children }: { loaded: Loaded<T>; children: (data: T) => ReactNode }) {
  if (loaded.data !== undefined) return children(loaded.data);
  if (loaded.error) {
    return (
      <Stack gap="sm">
        <Alert color="red">{loaded.error.message}</Alert>
        <Button variant="default" onClick={() => void loaded.reload()} loading={loaded.loading}>
          Try again
        </Button>
      </Stack>
    );
  }
  return (
    <Center py="xl">
      <Loader />
    </Center>
  );
}
