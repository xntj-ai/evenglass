// Even Hub bridge — single point of contact with the native container.
//
// Outside the Even App (e.g. Vite dev server in a normal browser),
// `window.EvenHub` is undefined; we install a no-op stub so the rest of
// the app keeps working in the dev preview.

import { logInfo, logWarn } from "@services/logger";

let cachedBridge: EvenBridge | null = null;
let readyPromise: Promise<EvenBridge> | null = null;

export function waitForEvenAppBridge(): Promise<EvenBridge> {
  if (readyPromise) return readyPromise;

  readyPromise = (async () => {
    const bridge = window.EvenHub ?? makeStubBridge();
    await bridge.waitReady();
    cachedBridge = bridge;
    logInfo("bridge ready, version=", bridge.version);
    return bridge;
  })();

  return readyPromise;
}

export function bridgeOrNull(): EvenBridge | null {
  return cachedBridge;
}

// Stub used when running outside the Even App container. Logs warnings
// and never emits events — useful for visual/UI development on a desktop.
function makeStubBridge(): EvenBridge {
  logWarn("window.EvenHub not present — falling back to stub bridge (dev mode)");

  return {
    version: "stub",
    waitReady: () => Promise.resolve(),
    on: () => () => undefined,
    audioControl: async (enabled) => {
      logInfo("[stub] audioControl", enabled);
    },
  };
}
