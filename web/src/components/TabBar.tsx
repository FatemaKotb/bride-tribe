import { Group, Paper, Stack, Text, UnstyledButton } from '@mantine/core';
import { useEffect } from 'react';
import { useLocation, useNavigate } from 'react-router';

const TABS = [
  { path: '/', label: 'Home', emoji: '🏡', also: [] },
  { path: '/items', label: 'Items', emoji: '🧴', also: ['/item/'] },
  { path: '/bags', label: 'Bags', emoji: '👜', also: [] },
  { path: '/cars', label: 'Cars', emoji: '🚗', also: ['/car/'] },
  { path: '/requests', label: 'Requests', emoji: '💌', also: [] },
];

// The tab last shown, so a detail or form screen lights up the tab it was
// opened from (items and bags share one detail screen).
const last: { tab: string | null } = { tab: null };

// Bottom navigation.
export function TabBar() {
  const navigate = useNavigate();
  const { pathname } = useLocation();
  const current = TABS.find((tab) => tab.path === pathname)?.path;
  // Opened directly, a detail screen lights up the tab it belongs to.
  const active =
    current ?? last.tab ?? TABS.find((tab) => tab.also.some((prefix) => pathname.startsWith(prefix)))?.path;

  useEffect(() => {
    if (current) last.tab = current;
  }, [current]);

  return (
    <Group grow gap={0} h="100%" maw={572} mx="auto" px="xs">
      {TABS.map((tab) => {
        const isActive = tab.path === active;
        return (
          <UnstyledButton key={tab.path} h="100%" onClick={() => void navigate(tab.path)}>
            <Stack gap={2} align="center">
              <Paper bg={isActive ? 'lavender.1' : 'transparent'} radius="xl" px="md" py={2}>
                <Text fz={20} lh={1.3}>
                  {tab.emoji}
                </Text>
              </Paper>
              <Text size="xs" fw={isActive ? 800 : 600} c={isActive ? 'lavender.7' : 'dimmed'}>
                {tab.label}
              </Text>
            </Stack>
          </UnstyledButton>
        );
      })}
    </Group>
  );
}
