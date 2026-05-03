// Wrapper that swallows bridge errors into the logger + Sentry instead of
// crashing the host. Use for any user-action-triggered bridge call that
// should fail soft (audio toggle, display flush, etc.).

import { captureException } from "@services/sentry";
import { logError } from "@services/logger";

export async function safeCall<T>(label: string, fn: () => Promise<T>): Promise<T | null> {
  try {
    return await fn();
  } catch (err) {
    logError(`bridge call "${label}" failed`, err);
    captureException(err, { bridgeCall: label });
    return null;
  }
}
