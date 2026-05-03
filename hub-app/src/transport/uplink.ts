// Server uplink for upstream events. Tries HTTP POST; on failure (offline,
// 5xx, network) it queues to IndexedDB and retries on the next online
// signal. Idempotency-Key is generated client-side so retries collapse
// server-side instead of producing duplicates.

import type { KyInstance } from "ky";

import { logError, logInfo, logWarn } from "@services/logger";
import { newUlid } from "@shared/ulid";

import { makeHttp } from "./http";
import { drain, enqueue, type QueuedEvent } from "./offline-queue";

let http: KyInstance | null = null;

function client(): KyInstance {
  if (!http) http = makeHttp();
  return http;
}

async function postEvent(event: QueuedEvent): Promise<boolean> {
  try {
    await client().post("api/g2/events", {
      headers: { "Idempotency-Key": event.idempotency_key },
      json: { type: event.type, payload: event.payload },
    });
    return true;
  } catch (err) {
    logWarn("event POST failed; will retry from queue", err);
    return false;
  }
}

export async function sendEvent(type: string, payload: unknown): Promise<void> {
  const event: QueuedEvent = {
    type,
    payload,
    idempotency_key: newUlid(),
    enqueued_at: Date.now(),
  };

  const sent = await postEvent(event);
  if (!sent) {
    await enqueue(event);
  }
}

export async function flushQueue(): Promise<void> {
  try {
    await drain(postEvent);
  } catch (err) {
    logError("queue drain failed", err);
  }
}

export function watchOnlineForFlush(): void {
  window.addEventListener("online", () => {
    logInfo("network online → flushing uplink queue");
    void flushQueue();
  });
}
