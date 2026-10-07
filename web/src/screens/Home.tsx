import { Stack, Title } from '@mantine/core';
import { useEffect } from 'react';
import { RowList } from '../components/RowCard';
import { useHome, useSession } from '../session';

const POLL_MS = 30_000;

// BR-28 and BR-34. get_home also feeds the header, so it lives in the
// session; this screen polls it every 30 seconds while the app is open.
export function Home() {
  const { reloadHome } = useSession();
  const home = useHome();
  const reload = () => void reloadHome();

  useEffect(() => {
    void reloadHome();
    const timer = setInterval(() => {
      if (!document.hidden) void reloadHome();
    }, POLL_MS);
    return () => clearInterval(timer);
  }, [reloadHome]);

  return (
    <Stack gap="lg">
      {home.attention.length > 0 && (
        <Stack gap="xs">
          <Title order={3}>Needs your attention</Title>
          <RowList rows={home.attention} onDone={reload} />
        </Stack>
      )}
      <Stack gap="xs">
        <Title order={3}>Status board</Title>
        <RowList rows={home.status_board} onDone={reload} />
      </Stack>
    </Stack>
  );
}
