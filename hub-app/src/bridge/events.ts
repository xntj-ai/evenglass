// Wrapper around `bridge.onEvenHubEvent`. Exists mainly so callers can
// import a single semantic module instead of touching the bridge struct
// directly. Returns the SDK's unsubscribe handle.

import type { EvenHubEvent } from "@evenrealities/even_hub_sdk";

import { waitForEvenAppBridge } from "./index";

export async function onEvenHubEvent(
  handler: (event: EvenHubEvent) => void,
): Promise<() => void> {
  const bridge = await waitForEvenAppBridge();
  return bridge.onEvenHubEvent(handler);
}
