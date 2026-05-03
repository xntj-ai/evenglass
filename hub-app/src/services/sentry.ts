// Sentry wiring. Disabled when DSN is empty (default in scaffold).
// makeBrowserOfflineTransport is added in milestone 4 once we have a
// committed DSN.

import * as Sentry from "@sentry/browser";

export function initSentry(): void {
  const dsn = import.meta.env.VITE_SENTRY_DSN;
  if (!dsn) {
    return;
  }

  Sentry.init({
    dsn,
    tracesSampleRate: 0,
    integrations: [],
    environment: import.meta.env.MODE,
  });
}

export function captureException(err: unknown, ctx?: Record<string, unknown>): void {
  if (!import.meta.env.VITE_SENTRY_DSN) {
    return;
  }

  Sentry.captureException(err, ctx ? { extra: ctx } : undefined);
}
