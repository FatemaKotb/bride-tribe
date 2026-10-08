import { Group, Paper, Stack, Text, UnstyledButton } from '@mantine/core';
import { useLocation, useNavigate } from 'react-router';

const TABS = [
  { path: '/', label: 'Home', emoji: '🏡', also: [] },
  { path: '/items', label: 'Items', emoji: '👜', also: ['/item/'] },
  { path: '/cars', label: 'Cars', emoji: '🚗', also: ['/car/'] },
  { path: '/requests', label: 'Requests', emoji: '💌', also: [] },
];

// Bottom navigation. Detail screens light up the tab they belong to.
export function TabBar() {
  const navigate = useNavigate();
  const { pathname } = useLocation();

  return (
    <Group grow gap={0} h="100%" maw={572} mx="auto" px="xs">
      {TABS.map((tab) => {
        const active = pathname === tab.path || tab.also.some((prefix) => pathname.startsWith(prefix));
        return (
          <UnstyledButton key={tab.path} h="100%" onClick={() => void navigate(tab.path)}>
            <Stack gap={2} align="center">
              <Paper bg={active ? 'lavender.1' : 'transparent'} radius="xl" px="md" py={2}>
                <Text fz={20} lh={1.3}>
                  {tab.emoji}
                </Text>
              </Paper>
              <Text size="xs" fw={active ? 800 : 600} c={active ? 'lavender.7' : 'dimmed'}>
                {tab.label}
              </Text>
            </Stack>
          </UnstyledButton>
        );
      })}
    </Group>
  );
}
