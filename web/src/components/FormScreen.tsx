import { Alert, Button, Group, Stack, Title } from '@mantine/core';
import { useState, type FormEvent } from 'react';
import { useParams, useSearchParams } from 'react-router';
import { call } from '../api';
import type { Args, FormSchema } from '../contract';
import { collect, initialValues, validate, type Errors } from '../form';
import { useBack, useLoad } from '../hooks';
import { Fields } from './FieldInput';
import { LoadState } from './LoadState';

function parseContext(raw: string | null): Args {
  try {
    const parsed: unknown = JSON.parse(raw ?? '{}');
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? (parsed as Args) : {};
  } catch {
    return {};
  }
}

// Fetches a form schema with get_form and renders it (contract Section 5).
export function FormScreen() {
  const { name = '' } = useParams();
  const [params] = useSearchParams();
  const context = params.get('context') ?? '{}';
  // A different form starts with its own values.
  return <FormView key={`${name}?${context}`} name={name} context={parseContext(context)} />;
}

function FormView({ name, context }: { name: string; context: Args }) {
  const loaded = useLoad<FormSchema>('get_form', { name, context }, false);
  const back = useBack();

  return (
    <LoadState loaded={loaded}>
      {(form) => <FormBody form={form} onDone={back} />}
    </LoadState>
  );
}

// On submit, sends the form's context plus the visible fields' values to
// submit.function, then goes back to the screen that opened it, which
// reloads.
function FormBody({ form, onDone }: { form: FormSchema; onDone: () => void }) {
  const [values, setValues] = useState(() => initialValues(form.fields));
  const [errors, setErrors] = useState<Errors>({});
  const [failure, setFailure] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault();
    const found = validate(form.fields, values);
    setErrors(found);
    if (Object.keys(found).length > 0) {
      setFailure('Please check the highlighted fields.');
      return;
    }
    setBusy(true);
    setFailure(null);
    const { error } = await call(form.submit.function, { ...form.context, ...collect(form.fields, values) });
    setBusy(false);
    if (error) setFailure(error.message);
    else onDone();
  }

  return (
    <form onSubmit={(event) => void submit(event)} noValidate>
      <Stack gap="md">
        <Title order={2}>{form.title}</Title>
        <Fields fields={form.fields} values={values} errors={errors} onChange={setValues} />
        {failure && <Alert color="red">{failure}</Alert>}
        <Group justify="flex-end">
          <Button variant="default" onClick={onDone}>
            Cancel
          </Button>
          <Button type="submit" loading={busy}>
            {form.submit.label}
          </Button>
        </Group>
      </Stack>
    </form>
  );
}
