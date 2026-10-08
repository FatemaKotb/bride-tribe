import { Button, Group, Paper, Stack, Text, ThemeIcon, Title } from '@mantine/core';
import { useParams } from 'react-router';
import type { DetailResponse, Section } from '../contract';
import { useBack, useLoad } from '../hooks';
import { ActionBar } from './ActionButton';
import { LoadState } from './LoadState';
import { RowList } from './RowCard';

// Renders a Detail response (contract Section 1). A row's
// `open: { detail: "car", id }` maps to get_car({ car_id: id }), the
// naming every detail endpoint follows.
export function DetailScreen() {
  const { detail = '', id = '' } = useParams();
  // A new detail starts fresh instead of showing the last one while loading.
  return <DetailView key={`${detail}/${id}`} detail={detail} id={id} />;
}

function DetailView({ detail, id }: { detail: string; id: string }) {
  const loaded = useLoad<DetailResponse>(`get_${detail}`, { [`${detail}_id`]: id });
  const back = useBack();
  const reload = () => void loaded.reload();

  return (
    <Stack gap="md">
      <Group>
        <Button variant="subtle" size="compact-sm" onClick={back}>
          ‹ Back
        </Button>
      </Group>
      <LoadState loaded={loaded}>
        {(view) => (
          <Stack gap="lg">
            <Group gap="md" wrap="nowrap" align="center">
              {view.emoji && (
                <ThemeIcon variant="light" radius="xl" size={60} style={{ flexShrink: 0 }}>
                  <Text fz={32} lh={1}>
                    {view.emoji}
                  </Text>
                </ThemeIcon>
              )}
              <Stack gap={2} miw={0}>
                <Title order={2}>{view.title}</Title>
                {view.subtitle && <Text c="dimmed">{view.subtitle}</Text>}
              </Stack>
            </Group>
            <ActionBar actions={view.actions} onDone={reload} />
            {view.sections.map((section) => (
              <DetailSection key={section.title} section={section} onDone={reload} />
            ))}
          </Stack>
        )}
      </LoadState>
    </Stack>
  );
}

function DetailSection({ section, onDone }: { section: Section; onDone: () => void }) {
  return (
    <Stack gap="xs">
      <Title order={4}>{section.title}</Title>
      {section.fields ? (
        <Paper withBorder p="md" shadow="xs">
          <Stack gap={8}>
            {section.fields.map((pair) => (
              <Group key={pair.label} gap="sm" wrap="nowrap" align="flex-start">
                <Text size="sm" c="dimmed" w={110} style={{ flexShrink: 0 }}>
                  {pair.label}
                </Text>
                <Text size="sm" fw={600} style={{ whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>
                  {pair.value}
                </Text>
              </Group>
            ))}
          </Stack>
        </Paper>
      ) : (
        <RowList rows={section.rows} empty={section.empty_message} onDone={onDone} />
      )}
    </Stack>
  );
}
