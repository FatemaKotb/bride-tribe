import '@mantine/core/styles.css';
import { MantineProvider } from '@mantine/core';
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { HashRouter } from 'react-router';
import { App } from './App';
import { Toaster } from './components/Toaster';
import { SessionProvider } from './SessionProvider';
import { cssVariablesResolver, theme } from './theme';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <MantineProvider theme={theme} cssVariablesResolver={cssVariablesResolver}>
      <HashRouter>
        <SessionProvider>
          <App />
          <Toaster />
        </SessionProvider>
      </HashRouter>
    </MantineProvider>
  </StrictMode>,
);
