// Tiny IndexedDB-backed FIFO. Survives WebView restarts so events
// captured while offline reach the server eventually. We dedupe via the
// idempotency_key the server already enforces — replays cannot create
// duplicate event rows.

import { get, set } from "idb-keyval";

const QUEUE_KEY = "evenglass.uplink.queue.v1";

export type QueuedEvent = {
  type: string;
  payload: unknown;
  idempotency_key: string;
  enqueued_at: number;
};

async function read(): Promise<QueuedEvent[]> {
  return ((await get<QueuedEvent[]>(QUEUE_KEY)) ?? []).slice();
}

async function write(queue: QueuedEvent[]): Promise<void> {
  await set(QUEUE_KEY, queue);
}

export async function enqueue(event: QueuedEvent): Promise<void> {
  const q = await read();
  q.push(event);
  await write(q);
}

export async function drain(send: (event: QueuedEvent) => Promise<boolean>): Promise<void> {
  const q = await read();
  const remaining: QueuedEvent[] = [];

  for (const event of q) {
    const ok = await send(event);
    if (!ok) remaining.push(event);
  }

  if (remaining.length !== q.length) {
    await write(remaining);
  }
}

export async function size(): Promise<number> {
  const q = await read();
  return q.length;
}
