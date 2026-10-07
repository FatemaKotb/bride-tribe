import { Alert, Button, Container, Stack, Text, Title } from '@mantine/core';
import { useState } from 'react';
import { useNavigate } from 'react-router';
import type { LoginMember, MembersForLogin } from '../contract';
import { LoadState } from '../components/LoadState';
import { useLoad } from '../hooks';
import { useSession } from '../session';

// BR-03: pick your name, confirm it, and this phone remembers you.
export function SignIn() {
  const { signIn } = useSession();
  const navigate = useNavigate();
  const loaded = useLoad<MembersForLogin>('list_members_for_login', {});
  const [chosen, setChosen] = useState<LoginMember | null>(null);
  const [busy, setBusy] = useState(false);
  const [failure, setFailure] = useState<string | null>(null);

  async function confirm(member: LoginMember) {
    setBusy(true);
    setFailure(null);
    const error = await signIn(member.id);
    setBusy(false);
    if (error) setFailure(error.message);
    else void navigate('/', { replace: true });
  }

  return (
    <Container size="xs" py="xl">
      {chosen ? (
        <Stack gap="md">
          <Title order={2} fw={400}>
            You're <b>{chosen.name}</b> ({chosen.role_label})?
          </Title>
          {failure && <Alert color="red">{failure}</Alert>}
          <Button size="md" loading={busy} onClick={() => void confirm(chosen)}>
            Yes, that's me
          </Button>
          <Button
            size="md"
            variant="default"
            disabled={busy}
            onClick={() => {
              setChosen(null);
              setFailure(null);
            }}
          >
            No, go back
          </Button>
        </Stack>
      ) : (
        <Stack gap="md">
          <Title order={1}>Bride Tribe</Title>
          <Text c="dimmed">Please pick your name to continue.</Text>
          <LoadState loaded={loaded}>
            {({ members }) => (
              <Stack gap="xs">
                {members.map((member) => (
                  <Button
                    key={member.id}
                    variant="default"
                    size="lg"
                    justify="space-between"
                    fullWidth
                    rightSection={
                      <Text size="sm" c="dimmed">
                        {member.role_label}
                      </Text>
                    }
                    onClick={() => setChosen(member)}
                  >
                    {member.name}
                  </Button>
                ))}
              </Stack>
            )}
          </LoadState>
        </Stack>
      )}
    </Container>
  );
}
