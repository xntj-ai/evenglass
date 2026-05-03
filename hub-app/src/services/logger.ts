// Thin structured logger. Real implementation lands in milestone 4
// (LoggerJSON server-side + trace_id propagation); for now we stick
// with console with a tiny prefix so log lines are visibly ours.

const PREFIX = "[evenglass]";

export function initLogger(): void {
  // Reserved for future: install a global error handler, hook into
  // window.onerror / unhandledrejection, attach trace_id from bridge.
}

export function logInfo(...args: unknown[]): void {
  console.info(PREFIX, ...args);
}

export function logWarn(...args: unknown[]): void {
  console.warn(PREFIX, ...args);
}

export function logError(...args: unknown[]): void {
  console.error(PREFIX, ...args);
}
