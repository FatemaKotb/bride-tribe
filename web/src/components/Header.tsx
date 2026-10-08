import { Anchor, Button, Drawer, Group, Paper, Stack, Text, Title, UnstyledButton } from '@mantine/core';
import { useState } from 'react';
import { call } from '../api';
import { useHome, useSession } from '../session';
import { showToast } from '../toast';

// "Sara · Doing makeup" with a status picker and "Not Sara? Switch"
// (BR-03a, BR-27), on every screen but sign-in. Sits on the lavender bar.
export function Header() {
  const { reloadHome, switchMember } = useSession();
  const { me, my_status: status } = useHome();
  const [picking, setPicking] = useState(false);
  const [saving, setSaving] = useState<string | null>(null);
  const current = status.options.find((o) => o.value === status.value);

  async function choose(value: string) {
    setSaving(value);
    const { error } = await call('set_status', { status: value });
    if (error) showToast(error.message);
    await reloadHome();
    setSaving(null);
    setPicking(false);
  }

  async function switchAway() {
    const error = await switchMember();
    if (error) showToast(error.message);
  }

  return (
    <Stack gap={2} justify="center" h="100%" px="md" maw={572} mx="auto">
      <Group gap={8} wrap="nowrap">
        <Text c="white" fw={800} size="lg" truncate style={{ flexShrink: 0, maxWidth: '45%' }}>
          {me.name}
        </Text>
        <Text c="lavender.1">·</Text>
        <UnstyledButton onClick={() => setPicking(true)} miw={0}>
          <Paper bg="white" radius="xl" px="sm" py={2} shadow="xs">
            <Text c="lavender.7" fw={700} size="sm" truncate>
              {current?.emoji} {status.label} ▾
            </Text>
          </Paper>
        </UnstyledButton>
      </Group>
      <Anchor component="button" type="button" size="xs" c="lavender.0" ta="left" onClick={() => void switchAway()}>
        Not {me.name}? Switch
      </Anchor>

      <Drawer
        opened={picking}
        onClose={() => setPicking(false)}
        position="bottom"
        size={580}
        title={
          <Stack gap={0}>
            <Title order={4}>How are you doing?</Title>
            <Text size="sm" c="dimmed">
              {status.label} · {status.updated}
            </Text>
          </Stack>
        }
      >
        <Stack gap={6} pb="md">
          {status.options.map((option) => (
            <Button
              key={option.value}
              variant={option.value === status.value ? 'filled' : 'light'}
              justify="flex-start"
              fullWidth
              loading={saving === option.value}
              onClick={() => void choose(option.value)}
            >
              {option.emoji} {option.label}
            </Button>
          ))}
        </Stack>
      </Drawer>
    </Stack>
  );
}
