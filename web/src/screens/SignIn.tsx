import { Alert, Avatar, Button, Container, Group, Image, Paper, Stack, Text, Title, UnstyledButton } from '@mantine/core';
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
      <Stack align="center" gap={0} mb="lg">
        <Image src="./icon-192.png" alt="" w={64} h={64} />
        <Title order={1} fz={40} c="lavender.6">
          Bride Tribe
        </Title>
      </Stack>

      {chosen ? (
        <Paper withBorder shadow="sm" p="lg">
          <Stack gap="md" align="center">
            <Avatar color="lavender" size="xl">{chosen.name.charAt(0)}</Avatar>
            <Title order={2} fw={400} ta="center">
              You're <b>{chosen.title}</b>?
            </Title>
            {failure && (
              <Alert color="red" w="100%">
                {failure}
              </Alert>
            )}
            <Button size="md" fullWidth loading={busy} onClick={() => void confirm(chosen)}>
              Yes, that's me
            </Button>
            <Button
              size="md"
              fullWidth
              variant="light"
              disabled={busy}
              onClick={() => {
                setChosen(null);
                setFailure(null);
              }}
            >
              No, go back
            </Button>
          </Stack>
        </Paper>
      ) : (
        <Stack gap="md">
          <Text c="dimmed" ta="center">
            Please pick your name to continue.
          </Text>
          <LoadState loaded={loaded}>
            {({ members }) => (
              <Stack gap="xs">
                {members.map((member) => (
                  <UnstyledButton key={member.id} onClick={() => setChosen(member)}>
                    <Paper withBorder shadow="xs" px="md" py="sm" radius="xl">
                      <Group gap="sm" wrap="nowrap">
                        <Avatar color="lavender">{member.name.charAt(0)}</Avatar>
                        <Text fw={700} truncate style={{ flex: 1 }}>
                          {member.title}
                        </Text>
                        <Text c="lavender.4" fz={22} lh={1}>
                          ›
                        </Text>
                      </Group>
                    </Paper>
                  </UnstyledButton>
                ))}
              </Stack>
            )}
          </LoadState>
        </Stack>
      )}
    </Container>
  );
}
