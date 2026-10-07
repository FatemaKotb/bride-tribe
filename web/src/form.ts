// Form values and submission (contract Section 5). Everything here follows
// the schema: which fields show, what is required, and what gets sent.
import type { Field, Json, Option, VisibleIf } from './contract';

export type Values = { [key: string]: Json };
export type Errors = Record<string, string>;

export function initialValues(fields: Field[]): Values {
  const values: Values = {};
  for (const field of fields) values[field.key] = initialValue(field);
  return values;
}

function initialValue(field: Field): Json {
  const nested = field.fields ?? [];
  if (field.type === 'group') return initialValues(nested);
  if (field.type === 'list') {
    const entries = field.value ?? field.default ?? [];
    return Array.isArray(entries)
      ? entries.map((entry) => ({ ...initialValues(nested), ...(entry as Values) }))
      : [];
  }
  return field.value ?? field.default ?? emptyValue(field);
}

function emptyValue(field: Field): Json {
  switch (field.type) {
    case 'tags':
    case 'multiselect':
      return [];
    case 'toggle':
      return false;
    default:
      return null;
  }
}

// A new entry for a list field, such as a stop.
export function newEntry(field: Field): Values {
  return initialValues(field.fields ?? []);
}

// Shown when the other field equals the value, or any value in a list.
// Against a multiselect, "equals" means "includes".
export function isVisible(rule: VisibleIf | null | undefined, scope: Values): boolean {
  if (!rule) return true;
  const actual = scope[rule.field] ?? null;
  const wanted = Array.isArray(rule.equals) ? rule.equals : [rule.equals];
  return Array.isArray(actual) ? actual.some((v) => wanted.includes(v)) : wanted.includes(actual);
}

export function visibleOptions(field: Field, scope: Values): Option[] {
  return (field.options ?? []).filter((option) => isVisible(option.visible_if, scope));
}

// Times are typed as HH:MM, 24-hour. Returns '' for blank, the time when
// valid, or null when it can't be read.
export function readTime(raw: Json): string | null {
  const text = String(raw ?? '').replace(/_/g, '').trim();
  if (text === '' || text === ':') return '';
  return /^([01]\d|2[0-3]):[0-5]\d$/.test(text) ? text : null;
}

// The value sent for a field: a hidden choice counts as no choice, and a
// blank as null.
function outgoing(field: Field, value: Json, scope: Values): Json {
  const nested = field.fields ?? [];
  switch (field.type) {
    case 'group':
      return collect(nested, (value ?? {}) as Values);
    case 'list':
      return ((value ?? []) as Values[]).map((entry) => collect(nested, entry));
    case 'select':
      return visibleOptions(field, scope).some((o) => o.value === value) ? value : null;
    case 'multiselect': {
      const allowed = visibleOptions(field, scope).map((o) => o.value);
      return ((value ?? []) as string[]).filter((v) => allowed.includes(v));
    }
    case 'tags':
      return value ?? [];
    case 'toggle':
      return Boolean(value);
    case 'time':
      return readTime(value) || null;
    default:
      return typeof value === 'string' && value.trim() === '' ? null : value;
  }
}

// The visible fields' values, keyed by field. Hidden fields aren't sent.
export function collect(fields: Field[], values: Values): Values {
  const body: Values = {};
  for (const field of fields) {
    if (isVisible(field.visible_if, values)) body[field.key] = outgoing(field, values[field.key] ?? null, values);
  }
  return body;
}

function isBlank(value: Json) {
  return value === null || value === '' || (Array.isArray(value) && value.length === 0);
}

// Required fields the member left empty, and times that can't be read,
// keyed by path ("stops.0.description").
export function validate(fields: Field[], values: Values, path = ''): Errors {
  const errors: Errors = {};
  for (const field of fields) {
    if (!isVisible(field.visible_if, values)) continue;
    const key = path + field.key;
    const value = values[field.key] ?? null;
    const nested = field.fields ?? [];
    if (field.type === 'group') {
      Object.assign(errors, validate(nested, (value ?? {}) as Values, `${key}.`));
    } else if (field.type === 'list') {
      ((value ?? []) as Values[]).forEach((entry, i) => Object.assign(errors, validate(nested, entry, `${key}.${i}.`)));
    } else if (field.type === 'time' && readTime(value) === null) {
      errors[key] = 'Use 24-hour time, like 23:30.';
    } else if (field.required && isBlank(outgoing(field, value, values))) {
      errors[key] = 'Please fill this in.';
    }
  }
  return errors;
}
