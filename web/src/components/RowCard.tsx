import { Badge, Card, Group, Stack, Text, UnstyledButton } from '@mantine/core';
import { useNavigate } from 'react-router';
import type { Row, Tone } from '../contract';
import { detailPath } from '../hooks';
import { ActionButton } from './ActionButton';

const TONE_COLORS: Record<Tone, string> = {
  neutral: 'gray',
  success: 'green',
  warning: 'orange',
  danger: 'red',
};

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
      {row.emoji && (
        <Text fz={24} lh={1.2}>
          {row.emoji}
        </Text>
      )}
      <Stack gap={4} miw={0} style={{ flex: 1 }}>
        <Text fw={500}>{row.title}</Text>
        {row.subtitle && (
          <Text size="sm" c="dimmed">
            {row.subtitle}
          </Text>
        )}
        {row.badges.length > 0 && (
          <Group gap={6}>
            {row.badges.map((badge) => (
              <Badge key={badge.label} color={TONE_COLORS[badge.tone]} variant="light" tt="none">
                {badge.label}
              </Badge>
            ))}
          </Group>
        )}
      </Stack>
    </Group>
  );

  return (
    <Card withBorder padding="sm" radius="md">
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
      <Text c="dimmed" size="sm">
        {empty}
      </Text>
    ) : null;
  }
  return (
    <Stack gap="xs">
      {rows.map((row) => (
        <RowCard key={row.id} row={row} onDone={onDone} />
      ))}
    </Stack>
  );
}
