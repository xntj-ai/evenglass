// Subscribes to G2 input events from the Even Hub SDK and forwards them
// upstream as `/api/g2/events`. The server stores everything as
// direction="up" rows under the device's session, then PubSub-broadcasts
// to /admin/events for live monitoring.
//
// Event mapping (SDK -> server):
//   listEvent  -> type "list_event"  (user navigated/clicked a list item)
//   textEvent  -> type "text_event"  (user clicked a text container)
//   sysEvent   -> type "sys_event"   (foreground enter/exit, etc.)
// Audio events are intentionally NOT relayed here — they are high-rate
// PCM streams that need their own batching path (milestone D1).
// IMU sysEvents (eventType=8) are also dropped to avoid flooding the
// admin event log when imuControl is enabled for other purposes.

import { OsEventTypeList } from "@evenrealities/even_hub_sdk";

import { onEvenHubEvent } from "@bridge/events";
import { logInfo } from "@services/logger";
import { sendEvent } from "@transport/uplink";

export async function startInputRelay(): Promise<() => void> {
  logInfo("input-relay: subscribing to EvenHub events");

  return onEvenHubEvent((event) => {
    if (event.listEvent) {
      void sendEvent("list_event", {
        container_id: event.listEvent.containerID,
        container_name: event.listEvent.containerName,
        item_index: event.listEvent.currentSelectItemIndex,
        item_name: event.listEvent.currentSelectItemName,
        event_type: event.listEvent.eventType,
      });
      return;
    }
    if (event.textEvent) {
      void sendEvent("text_event", {
        container_id: event.textEvent.containerID,
        container_name: event.textEvent.containerName,
        event_type: event.textEvent.eventType,
      });
      return;
    }
    if (event.sysEvent) {
      if (event.sysEvent.eventType === OsEventTypeList.IMU_DATA_REPORT) return;
      void sendEvent("sys_event", {
        event_type: event.sysEvent.eventType,
        event_source: event.sysEvent.eventSource,
      });
      return;
    }
    // audioEvent intentionally ignored here — handled by the audio
    // pipeline (milestone D1).
  });
}
