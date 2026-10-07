import '@mantine/core/styles.css';
import { MantineProvider } from '@mantine/core';
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { HashRouter } from 'react-router';
import { App } from './App';
import { Toaster } from './components/Toaster';
import { SessionProvider } from './SessionProvider';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <MantineProvider>
      <HashRouter>
        <SessionProvider>
          <App />
          <Toaster />
        </SessionProvider>
      </HashRouter>
    </MantineProvider>
  </StrictMode>,
);
