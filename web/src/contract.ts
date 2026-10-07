// The shapes the backend returns (docs/wedding-app-backend-contract.md,
// Sections 1 to 6). The UI renders these as given and makes no decisions
// of its own.

export type Json = string | number | boolean | null | Json[] | { [key: string]: Json };
export type Args = Record<string, Json>;

// Every call returns { data } or { error } (Section 1, Response envelope).
export interface ApiError {
  code: string;
  message: string;
}
export type Envelope<T> = { data: T; error?: undefined } | { data?: undefined; error: ApiError };

export type Tone = 'neutral' | 'success' | 'warning' | 'danger';

export interface Badge {
  label: string;
  tone: Tone;
}

// An action has either `call` or `form`, never both. `confirm` is always
// present, and null when no confirmation is needed.
export interface Action {
  id: string;
  label: string;
  style: 'primary' | 'secondary' | 'danger';
  confirm: string | null;
  call: { function: string; args: Args } | null;
  form: { name: string; context: Args } | null;
}

// `open` names a detail view, such as { detail: "car", id }. The "Got it"
// row on the home screen has no emoji, title, or subtitle, only its action.
export interface Row {
  id: string;
  emoji: string | null;
  title: string | null;
  subtitle: string | null;
  badges: Badge[];
  open: { detail: string; id: string } | null;
  actions: Action[];
}

// A dropdown, chip, or filter choice. An option can carry its own
// `visible_if` (for example, the vendor's address as a pickup location).
export interface Option {
  value: string;
  label: string;
  emoji?: string | null;
  visible_if?: VisibleIf | null;
}

export interface Filter {
  key: string;
  label: string;
  multi: boolean;
  options: Option[];
  selected: string[];
}

// Filters are sent back as { key: [values] }.
export type FilterChoices = Record<string, string[]>;

export interface ListResponse {
  title: string;
  filters: Filter[];
  rows: Row[];
  empty_message: string;
  actions: Action[];
}

export interface Pair {
  label: string;
  value: string;
}

// A section has either `fields` (label and value pairs) or `rows`.
export type Section =
  | { title: string; fields: Pair[]; rows?: undefined }
  | { title: string; rows: Row[]; empty_message: string; fields?: undefined };

export interface DetailResponse {
  emoji: string | null;
  title: string;
  subtitle: string | null;
  sections: Section[];
  actions: Action[];
}

export type FieldType =
  | 'text'
  | 'textarea'
  | 'number'
  | 'emoji'
  | 'tags'
  | 'select'
  | 'multiselect'
  | 'time'
  | 'toggle'
  | 'group'
  | 'list';

// The field is shown when another field at the same level equals this
// value. `equals` may be a list, meaning "any of these". When the other
// field is a multiselect, "equals" means "includes".
export interface VisibleIf {
  field: string;
  equals: Json;
}

// `group` and `list` fields hold their nested fields in `fields`. A list's
// `value` is an array of objects keyed by the nested fields.
export interface Field {
  key: string;
  label: string;
  type: FieldType;
  required: boolean;
  options: Option[] | null;
  hint: string | null;
  default: Json;
  value: Json;
  visible_if: VisibleIf | null;
  fields: Field[] | null;
}

export interface FormSchema {
  name: string;
  title: string;
  context: Args;
  fields: Field[];
  submit: { function: string; label: string };
}

// Section 2: sign-in.
export interface LoginMember {
  id: string;
  name: string;
  role_label: string;
}

export interface MembersForLogin {
  members: LoginMember[];
}

// Section 3: get_home.
export interface Home {
  me: { name: string; role_label: string };
  my_status: {
    value: string;
    label: string;
    updated: string;
    options: Option[];
  };
  attention: Row[];
  status_board: Row[];
}
