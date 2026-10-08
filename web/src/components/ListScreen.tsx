import { Button, Chip, Group, Stack, Text, Title } from '@mantine/core';
import { useEffect, useState } from 'react';
import { useSearchParams } from 'react-router';
import type { Filter, FilterChoices, ListResponse } from '../contract';
import { useLoad } from '../hooks';
import { ActionBar } from './ActionButton';
import { LoadState } from './LoadState';
import { RowList } from './RowCard';

// The last filters used on each list, so switching tabs keeps them.
const lastFilters = new Map<string, string>();

function parseChoices(raw: string): FilterChoices {
  try {
    const parsed: unknown = JSON.parse(raw);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? (parsed as FilterChoices) : {};
  } catch {
    return {};
  }
}

// Renders a List response (contract Section 1): filters as chips, screen
// actions, rows, and the empty message. `fn` is the list endpoint, such as
// list_items.
export function ListScreen({ fn }: { fn: string }) {
  const [params, setParams] = useSearchParams();
  const raw = params.get('filters') ?? lastFilters.get(fn) ?? '{}';
  const loaded = useLoad<ListResponse>(fn, { filters: parseChoices(raw) });

  useEffect(() => {
    lastFilters.set(fn, raw);
  }, [fn, raw]);

  // Send back every filter's current choice, with this one changed. The
  // backend decides what an empty choice means.
  function choose(list: ListResponse, filter: Filter, value: string) {
    const choices: FilterChoices = Object.fromEntries(list.filters.map((f) => [f.key, f.selected]));
    const selected = filter.selected;
    choices[filter.key] = selected.includes(value)
      ? selected.filter((v) => v !== value)
      : filter.multi
        ? [...selected, value]
        : [value];
    setParams({ filters: JSON.stringify(choices) }, { replace: true });
  }

  return (
    <LoadState loaded={loaded}>
      {(list) => (
        <Stack gap="md">
          <Title order={2}>{list.title}</Title>
          <FilterBar filters={list.filters} onChoose={(filter, value) => choose(list, filter, value)} />
          <ActionBar actions={list.actions} onDone={() => void loaded.reload()} />
          <RowList rows={list.rows} empty={list.empty_message} onDone={() => void loaded.reload()} />
        </Stack>
      )}
    </LoadState>
  );
}

// Long filter lists fold away behind "More filters" so the rows stay in
// view on a phone. The first filter always shows.
const FOLD_AFTER = 3;

function FilterBar({ filters: all, onChoose }: { filters: Filter[]; onChoose: (filter: Filter, value: string) => void }) {
  const [expanded, setExpanded] = useState(false);
  // A filter with nothing to choose, such as Tag before any tags exist.
  const filters = all.filter((f) => f.options.length > 0);
  const folds = filters.length > FOLD_AFTER;
  const shown = folds && !expanded ? filters.slice(0, 1) : filters;
  const activeHidden = filters.slice(1).filter((f) => f.selected.length > 0).length;

  if (filters.length === 0) return null;
  return (
    <Stack gap={6}>
      {shown.map((filter) => (
        <FilterChips key={filter.key} filter={filter} onChoose={(value) => onChoose(filter, value)} />
      ))}
      {folds && (
        <Group>
          <Button variant="subtle" size="compact-sm" onClick={() => setExpanded((e) => !e)}>
            {expanded ? 'Fewer filters' : activeHidden > 0 ? `More filters (${activeHidden} on)` : 'More filters'}
          </Button>
        </Group>
      )}
    </Stack>
  );
}

// Chips wrap rather than scroll, so the chosen one is always in view.
function FilterChips({ filter, onChoose }: { filter: Filter; onChoose: (value: string) => void }) {
  return (
    <Group gap="xs" wrap="nowrap" align="flex-start">
      <Text size="sm" c="dimmed" w={64} pt={4} style={{ flexShrink: 0 }}>
        {filter.label}
      </Text>
      <Group gap={6} style={{ flex: 1 }}>
        {filter.options.map((option) => {
          // Solid when chosen, outlined otherwise, so the choice stands out.
          const checked = filter.selected.includes(option.value);
          return (
            <Chip
              key={option.value}
              size="sm"
              variant={checked ? 'filled' : 'outline'}
              checked={checked}
              onChange={() => onChoose(option.value)}
            >
              {option.emoji ? `${option.emoji} ${option.label}` : option.label}
            </Chip>
          );
        })}
      </Group>
    </Group>
  );
}
