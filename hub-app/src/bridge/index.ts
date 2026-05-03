// Even Hub bridge — single entry point. Re-exports the official SDK's
// `waitForEvenAppBridge` so callers always go through one module, and
// caches the resolved instance for synchronous lookups (e.g. inside an
// event callback that doesn't want to await again).
//
// Outside an Even App / simulator container the SDK's bridge still
// initializes (its `init()` flips ready on DOMContentLoaded) but
// `callEvenApp` calls will time out — that's the expected dev-mode
// behavior in plain Chrome.

import { waitForEvenAppBridge as sdkWaitForEvenAppBridge, type EvenAppBridge } from "@evenrealities/even_hub_sdk";

import { logInfo } from "@services/logger";

let cachedBridge: EvenAppBridge | null = null;
let readyPromise: Promise<EvenAppBridge> | null = null;

export function waitForEvenAppBridge(): Promise<EvenAppBridge> {
  if (readyPromise) return readyPromise;

  readyPromise = (async () => {
    const bridge = await sdkWaitForEvenAppBridge();
    cachedBridge = bridge;
    logInfo("bridge ready");
    return bridge;
  })();

  return readyPromise;
}

export function bridgeOrNull(): EvenAppBridge | null {
  return cachedBridge;
}
