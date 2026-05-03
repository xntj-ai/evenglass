// Subscribes to G2 input events from the Even Hub bridge and forwards
// them upstream as `/api/g2/events`. The server stores everything as
// direction="up" rows under the device's session, then PubSub-broadcasts
// to /admin/events for live monitoring.

import { onBridgeEvent } from "@bridge/events";
import { logInfo } from "@services/logger";
import { sendEvent } from "@transport/uplink";

const FORWARDED_EVENTS = ["tap", "long_press", "swipe", "gesture"] as const;

export async function startInputRelay(): Promise<() => void> {
  logInfo("input-relay: subscribing to bridge events");

  const unsubs = await Promise.all(
    FORWARDED_EVENTS.map((event) =>
      onBridgeEvent(event, (payload) => {
        void sendEvent(event, payload);
      }),
    ),
  );

  return () => unsubs.forEach((u) => u());
}
