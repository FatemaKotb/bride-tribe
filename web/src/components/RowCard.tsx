import { Badge, Card, Divider, Group, Paper, Stack, Text, ThemeIcon, UnstyledButton } from '@mantine/core';
import { useNavigate } from 'react-router';
import type { Row, Tone } from '../contract';
import { detailPath } from '../hooks';
import { ActionButton } from './ActionButton';

const TONE_COLORS: Record<Tone, string> = {
  neutral: 'lavender',
  success: 'teal',
  warning: 'orange',
  danger: 'red',
};

// The row's emoji in a soft circle, or the title's first letter when it
// has none, so rows line up.
function RowIcon({ row }: { row: Row }) {
  return (
    <ThemeIcon variant="light" radius="xl" size={42} style={{ flexShrink: 0 }}>
      <Text fz={row.emoji ? 22 : 18} fw={700} c="lavender.7" lh={1}>
        {row.emoji ?? row.title?.charAt(0).toUpperCase()}
      </Text>
    </ThemeIcon>
  );
}

// Renders a Row (contract Section 1). Tapping it opens its detail view, if
// it names one.
export function RowCard({ row, onDone }: { row: Row; onDone: () => void }) {
  const navigate = useNavigate();
  const { open } = row;
  const actions = row.actions.length > 0 && (
    <Group gap="xs">
      {row.actions.map((action) => (
        <ActionButton key={action.id} action={action} onDone={onDone} size="xs" />
      ))}
    </Group>
  );

  // A row with nothing to show but its actions, such as "Got it".
  if (!row.title && !row.emoji && !row.subtitle) {
    return <Group justify="flex-end">{actions}</Group>;
  }

  const body = (
    <Group gap="sm" wrap="nowrap" align="flex-start">
      <RowIcon row={row} />
      <Stack gap={4} miw={0} style={{ flex: 1 }}>
        <Text fw={700}>{row.title}</Text>
        {row.subtitle && (
          <Text size="sm" c="dimmed">
            {row.subtitle}
          </Text>
        )}
        {row.badges.length > 0 && (
          <Group gap={6}>
            {row.badges.map((badge, i) => (
              <Badge key={i} color={TONE_COLORS[badge.tone]} variant="light" tt="none">
                {badge.label}
              </Badge>
            ))}
          </Group>
        )}
      </Stack>
    </Group>
  );

  return (
    <Card withBorder padding="sm">
      <Stack gap="sm">
        {open ? (
          <UnstyledButton onClick={() => void navigate(detailPath(open))}>{body}</UnstyledButton>
        ) : (
          body
        )}
        {actions}
      </Stack>
    </Card>
  );
}

export function RowList({ rows, empty, onDone }: { rows: Row[]; empty?: string; onDone: () => void }) {
  if (rows.length === 0) {
    return empty ? (
      <Paper withBorder p="md">
        <Text c="dimmed" size="sm" ta="center">
          {empty}
        </Text>
      </Paper>
    ) : null;
  }
  // Rows with nothing to tap, such as the status board, share one card.
  if (rows.every((row) => !row.open && row.actions.length === 0)) {
    return (
      <Paper withBorder shadow="xs" px="sm" py={4}>
        {rows.map((row, i) => (
          <Stack key={row.id} gap={0}>
            {i > 0 && <Divider color="lavender.1" />}
            <Group gap="sm" wrap="nowrap" py={8}>
              <RowIcon row={row} />
              <Stack gap={0} miw={0} style={{ flex: 1 }}>
                <Text fw={700}>{row.title}</Text>
                {row.subtitle && (
                  <Text size="sm" c="dimmed">
                    {row.subtitle}
                  </Text>
                )}
              </Stack>
              {row.badges.map((badge, j) => (
                <Badge key={j} color={TONE_COLORS[badge.tone]} variant="light" tt="none">
                  {badge.label}
                </Badge>
              ))}
            </Group>
          </Stack>
        ))}
      </Paper>
    );
  }

  return (
    <Stack gap="xs">
      {rows.map((row) => (
        <RowCard key={row.id} row={row} onDone={onDone} />
      ))}
    </Stack>
  );
}
