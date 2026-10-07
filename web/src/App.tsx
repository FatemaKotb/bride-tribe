import { Alert, AppShell, Button, Center, Container, Loader, Stack } from '@mantine/core';
import { Navigate, Route, Routes } from 'react-router';
import { DetailScreen } from './components/DetailScreen';
import { FormScreen } from './components/FormScreen';
import { Header } from './components/Header';
import { ListScreen } from './components/ListScreen';
import { TabBar } from './components/TabBar';
import { Home } from './screens/Home';
import { SignIn } from './screens/SignIn';
import { useSession } from './session';

export function App() {
  const { state, start } = useSession();

  if (state.status === 'loading') {
    return (
      <Center h="100dvh">
        <Loader />
      </Center>
    );
  }

  if (state.status === 'failed') {
    return (
      <Container size="xs" py="xl">
        <Stack>
          <Alert color="red">{state.error.message}</Alert>
          <Button onClick={() => void start()}>Try again</Button>
        </Stack>
      </Container>
    );
  }

  if (state.status === 'signed_out') return <SignIn />;

  return (
    <AppShell header={{ height: 60 }} footer={{ height: 60 }} padding="md">
      <AppShell.Header>
        <Header />
      </AppShell.Header>
      <AppShell.Main>
        <Container size="xs" px={0} pb="md">
          <Routes>
            <Route path="/" element={<Home />} />
            <Route path="/items" element={<ListScreen key="list_items" fn="list_items" />} />
            <Route path="/cars" element={<ListScreen key="list_cars" fn="list_cars" />} />
            <Route path="/requests" element={<ListScreen key="list_requests" fn="list_requests" />} />
            <Route path="/form/:name" element={<FormScreen />} />
            <Route path="/:detail/:id" element={<DetailScreen />} />
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </Container>
      </AppShell.Main>
      <AppShell.Footer>
        <TabBar />
      </AppShell.Footer>
    </AppShell>
  );
}
