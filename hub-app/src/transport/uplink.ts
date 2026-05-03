// Server uplink — single ordering authority. Every sendEvent enqueues
// first, then triggers a (re-entrant-safe) flush. The flush worker drains
// the queue head-first; on failure (offline, 5xx) it leaves the head in
// place and exits, so the event isn't lost and ordering is preserved.
//
// Rationale: a "post directly, queue on failure" path can reorder
// (event A queued while B succeeds inline). Making the queue the single
// path keeps strict FIFO and reduces moving parts.

import type { KyInstance } from "ky";

import { logError, logInfo, logWarn } from "@services/logger";
import { newUlid } from "@shared/ulid";

import { makeHttp } from "./http";
import { dropHeadIf, enqueue, peekHead, type QueuedEvent } from "./offline-queue";

let http: KyInstance | null = null;
let flushing = false;

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

  await enqueue(event);
  void flushQueue();
}

/**
 * Drains the queue head-first. Re-entrant calls return immediately —
 * the in-flight flush will pick up any newly-enqueued events because it
 * loops until peekHead() returns null.
 */
export async function flushQueue(): Promise<void> {
  if (flushing) return;
  flushing = true;

  try {
    while (true) {
      const head = await peekHead();
      if (!head) return;

      const ok = await postEvent(head);
      if (!ok) {
        // Network down or server 5xx — leave the head in place; the next
        // online event or sendEvent call will retry. No event is lost.
        return;
      }

      await dropHeadIf(head.idempotency_key);
    }
  } catch (err) {
    logError("queue flush failed unexpectedly", err);
  } finally {
    flushing = false;
  }
}

export function watchOnlineForFlush(): void {
  window.addEventListener("online", () => {
    logInfo("network online → flushing uplink queue");
    void flushQueue();
  });
}
