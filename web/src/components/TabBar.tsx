import { Group, Stack, Text, UnstyledButton } from '@mantine/core';
import { useLocation, useNavigate } from 'react-router';

const TABS = [
  { path: '/', label: 'Home', emoji: '🏠', also: [] },
  { path: '/items', label: 'Items', emoji: '🎒', also: ['/item/'] },
  { path: '/cars', label: 'Cars', emoji: '🚗', also: ['/car/'] },
  { path: '/requests', label: 'Requests', emoji: '📨', also: [] },
];

// Bottom navigation. Detail screens light up the tab they belong to.
export function TabBar() {
  const navigate = useNavigate();
  const { pathname } = useLocation();

  return (
    <Group grow gap={0} h="100%" maw={572} mx="auto">
      {TABS.map((tab) => {
        const active = pathname === tab.path || tab.also.some((prefix) => pathname.startsWith(prefix));
        return (
          <UnstyledButton key={tab.path} h="100%" onClick={() => void navigate(tab.path)}>
            <Stack gap={0} align="center">
              <Text fz={20} lh={1.2}>
                {tab.emoji}
              </Text>
              <Text size="xs" fw={active ? 700 : 400} c={active ? 'blue' : 'dimmed'}>
                {tab.label}
              </Text>
            </Stack>
          </UnstyledButton>
        );
      })}
    </Group>
  );
}
