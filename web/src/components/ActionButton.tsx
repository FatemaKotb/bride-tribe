import { Button, Group, Modal, Text, type ButtonProps } from '@mantine/core';
import { useState } from 'react';
import { useNavigate } from 'react-router';
import { call } from '../api';
import type { Action } from '../contract';
import { formPath } from '../hooks';
import { showToast } from '../toast';

const STYLES: Record<Action['style'], ButtonProps> = {
  primary: { variant: 'filled' },
  secondary: { variant: 'light' },
  danger: { variant: 'light', color: 'red' },
};

// Renders an Action (contract Section 1). Asks first when it has a
// `confirm`, then either calls its function or opens its form. The screen
// reloads afterwards, through `onDone`.
export function ActionButton({
  action,
  onDone,
  size = 'sm',
}: {
  action: Action;
  onDone: () => void;
  size?: ButtonProps['size'];
}) {
  const navigate = useNavigate();
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);

  async function run() {
    setConfirming(false);
    if (action.form) {
      void navigate(formPath(action.form));
      return;
    }
    if (!action.call) return;
    setBusy(true);
    const { error } = await call(action.call.function, action.call.args);
    setBusy(false);
    if (error) showToast(error.message);
    // Reload either way: an error often means the screen is out of date.
    onDone();
  }

  return (
    <>
      <Button
        {...STYLES[action.style]}
        size={size}
        loading={busy}
        onClick={(event) => {
          event.stopPropagation();
          if (action.confirm) setConfirming(true);
          else void run();
        }}
      >
        {action.label}
      </Button>
      {action.confirm && (
        <Modal opened={confirming} onClose={() => setConfirming(false)} withCloseButton={false} centered>
          <Text>{action.confirm}</Text>
          <Group justify="flex-end" mt="lg">
            <Button variant="default" onClick={() => setConfirming(false)}>
              Go back
            </Button>
            <Button color={action.style === 'danger' ? 'red' : undefined} onClick={() => void run()}>
              {action.label}
            </Button>
          </Group>
        </Modal>
      )}
    </>
  );
}

export function ActionBar({ actions, onDone }: { actions: Action[]; onDone: () => void }) {
  if (actions.length === 0) return null;
  return (
    <Group gap="xs">
      {actions.map((action) => (
        <ActionButton key={action.id} action={action} onDone={onDone} />
      ))}
    </Group>
  );
}
