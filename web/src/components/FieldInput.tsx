import {
  Button,
  Chip,
  Fieldset,
  Group,
  Input,
  MaskInput,
  NativeSelect,
  NumberInput,
  Paper,
  Stack,
  Switch,
  Textarea,
  TextInput,
} from '@mantine/core';
import type { Field, Json, Option } from '../contract';
import { isVisible, newEntry, visibleOptions, type Errors, type Values } from '../form';

function optionLabel(option: Option) {
  return option.emoji ? `${option.emoji} ${option.label}` : option.label;
}

const asText = (value: Json) => (value === null || value === undefined ? '' : String(value));
const asList = (value: Json) => (Array.isArray(value) ? (value as string[]) : []);

// The visible fields at one level of a form. `path` prefixes nested
// fields' keys in `errors` ("vendor.", "stops.0.").
export function Fields({
  fields,
  values,
  errors,
  path = '',
  onChange,
}: {
  fields: Field[];
  values: Values;
  errors: Errors;
  path?: string;
  onChange: (values: Values) => void;
}) {
  return (
    <>
      {fields
        .filter((field) => isVisible(field.visible_if, values))
        .map((field) => (
          <FieldInput
            key={field.key}
            field={field}
            value={values[field.key] ?? null}
            scope={values}
            errors={errors}
            path={path + field.key}
            onChange={(value) => onChange({ ...values, [field.key]: value })}
          />
        ))}
    </>
  );
}

// One field, by type (contract Section 5, Field types).
function FieldInput({
  field,
  value,
  scope,
  errors,
  path,
  onChange,
}: {
  field: Field;
  value: Json;
  scope: Values;
  errors: Errors;
  path: string;
  onChange: (value: Json) => void;
}) {
  const common = {
    label: field.label,
    description: field.hint ?? undefined,
    error: errors[path],
    withAsterisk: field.required,
  };

  switch (field.type) {
    case 'text':
      return <TextInput {...common} value={asText(value)} onChange={(e) => onChange(e.currentTarget.value)} />;

    case 'emoji':
      return (
        <TextInput {...common} w={120} value={asText(value)} onChange={(e) => onChange(e.currentTarget.value)} />
      );

    case 'textarea':
      return (
        <Textarea
          {...common}
          autosize
          minRows={2}
          value={asText(value)}
          onChange={(e) => onChange(e.currentTarget.value)}
        />
      );

    case 'number':
      return (
        <NumberInput
          {...common}
          value={typeof value === 'number' ? value : ''}
          onChange={(v) => onChange(typeof v === 'number' ? v : null)}
        />
      );

    // 24-hour time; the mask types the colon, so a phone's number pad works.
    // The mask edits the input itself, so it is left uncontrolled.
    case 'time':
      return (
        <MaskInput
          {...common}
          mask="99:99"
          placeholder="HH:MM"
          inputMode="numeric"
          defaultValue={asText(value)}
          onChangeRaw={(_raw, masked) => onChange(masked)}
        />
      );

    // The phone's own picker: a floating dropdown can be lost when the
    // browser scrolls a focused field into view.
    case 'select': {
      const options = visibleOptions(field, scope);
      const chosen = options.some((o) => o.value === value) ? (value as string) : '';
      // A blank choice: to clear an optional field, or to show that a
      // required one hasn't been chosen yet.
      const blank = !field.required || chosen === '' ? [{ value: '', label: '', disabled: field.required }] : [];
      return (
        <NativeSelect
          {...common}
          data={[...blank, ...options.map((o) => ({ value: o.value, label: optionLabel(o) }))]}
          value={chosen}
          onChange={(e) => onChange(e.currentTarget.value || null)}
        />
      );
    }

    case 'multiselect':
      return (
        <Input.Wrapper {...common}>
          <Chip.Group multiple value={asList(value)} onChange={onChange}>
            <Group gap={6} mt={6}>
              {visibleOptions(field, scope).map((o) => (
                <Chip key={o.value} value={o.value} size="sm">
                  {optionLabel(o)}
                </Chip>
              ))}
            </Group>
          </Chip.Group>
        </Input.Wrapper>
      );

    case 'toggle':
      return (
        <Switch
          label={field.label}
          description={field.hint ?? undefined}
          error={errors[path]}
          checked={Boolean(value)}
          onChange={(e) => onChange(e.currentTarget.checked)}
        />
      );

    case 'group':
      return (
        <Fieldset legend={field.label}>
          <Stack gap="sm">
            {field.hint && <Input.Description>{field.hint}</Input.Description>}
            <Fields
              fields={field.fields ?? []}
              values={(value ?? {}) as Values}
              errors={errors}
              path={`${path}.`}
              onChange={onChange}
            />
          </Stack>
        </Fieldset>
      );

    case 'list':
      return <ListField field={field} entries={(value ?? []) as Values[]} errors={errors} path={path} onChange={onChange} />;
  }
}

// A repeatable group, such as a car's stops.
function ListField({
  field,
  entries,
  errors,
  path,
  onChange,
}: {
  field: Field;
  entries: Values[];
  errors: Errors;
  path: string;
  onChange: (entries: Values[]) => void;
}) {
  return (
    <Input.Wrapper label={field.label} description={field.hint ?? undefined} withAsterisk={field.required}>
      <Stack gap="xs" mt={6}>
        {entries.map((entry, i) => (
          <Paper key={i} withBorder p="sm">
            <Stack gap="sm">
              <Fields
                fields={field.fields ?? []}
                values={entry}
                errors={errors}
                path={`${path}.${i}.`}
                onChange={(next) => onChange(entries.map((e, j) => (j === i ? next : e)))}
              />
              <Group justify="flex-end">
                <Button
                  variant="subtle"
                  color="red"
                  size="compact-sm"
                  onClick={() => onChange(entries.filter((_, j) => j !== i))}
                >
                  Remove
                </Button>
              </Group>
            </Stack>
          </Paper>
        ))}
        <Group>
          <Button variant="light" size="compact-sm" onClick={() => onChange([...entries, newEntry(field)])}>
            Add
          </Button>
        </Group>
      </Stack>
    </Input.Wrapper>
  );
}
