// Typed wrapper around bridge.on(). Exists mainly so callers can import
// from a single semantic module instead of touching the bridge struct.

import { waitForEvenAppBridge } from "./index";

export async function onBridgeEvent<E extends keyof EvenBridgeEvents>(
  event: E,
  handler: (payload: EvenBridgeEvents[E]) => void,
): Promise<() => void> {
  const bridge = await waitForEvenAppBridge();
  return bridge.on(event, handler);
}
