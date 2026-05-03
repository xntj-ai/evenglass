// IndexedDB-backed FIFO. Survives WebView restarts so events captured
// offline reach the server eventually. We dedupe via the idempotency_key
// the server already enforces — replays cannot create duplicate event
// rows, so retrying a queued event is always safe.
//
// All mutations go through `update()`, which idb-keyval implements as a
// single read-modify-write transaction on the IndexedDB object store.
// That gives us atomic enqueue / takeAll / dropHead even with multiple
// concurrent callers (sendEvent fires while flushQueue is running, etc.)
// and keeps FIFO order intact under load.

import { get, update } from "idb-keyval";

const QUEUE_KEY = "evenglass.uplink.queue.v1";

export type QueuedEvent = {
  type: string;
  payload: unknown;
  idempotency_key: string;
  enqueued_at: number;
};

export async function enqueue(event: QueuedEvent): Promise<void> {
  await update<QueuedEvent[]>(QUEUE_KEY, (current) => [...(current ?? []), event]);
}

export async function peekHead(): Promise<QueuedEvent | null> {
  const q = await get<QueuedEvent[]>(QUEUE_KEY);
  return q && q.length > 0 ? (q[0] ?? null) : null;
}

/**
 * Removes the queue head iff it still matches `expectedKey`. Returns
 * true on successful removal. Concurrent enqueues that landed in the
 * meantime are preserved untouched.
 */
export async function dropHeadIf(expectedKey: string): Promise<boolean> {
  let removed = false;
  await update<QueuedEvent[]>(QUEUE_KEY, (current) => {
    const q = current ?? [];
    if (q.length > 0 && q[0]?.idempotency_key === expectedKey) {
      removed = true;
      return q.slice(1);
    }
    return q;
  });
  return removed;
}

export async function size(): Promise<number> {
  const q = await get<QueuedEvent[]>(QUEUE_KEY);
  return q?.length ?? 0;
}
