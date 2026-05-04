// Streams G2 microphone PCM up the channel as ~10Hz batched `audio_chunk`
// pushes. Server does not persist the PCM — see G2Channel.handle_in/3,
// which accumulates only frame/byte counts and writes one `audio_meta`
// event per ~1s window for admin observability, then re-broadcasts the
// chunk to PC subscribers (D1b ingestion target).
//
// Lifecycle:
//   startAudioRelay()  → bridge.audioControl(true)  + flush timer + listener
//   handle.stop()      → bridge.audioControl(false) + clear timer + unsub
//
// Best-effort delivery: if the channel is not joined when a flush fires,
// the buffered frames are dropped on the floor. Queueing PCM offline is
// pointless (audio is "live or never") and would balloon memory.

import type { Channel } from "phoenix";

import { onEvenHubEvent } from "@bridge/events";
import { waitForEvenAppBridge } from "@bridge/index";
import { safeCall } from "@bridge/safe-call";
import { logError, logInfo, logWarn } from "@services/logger";
import { getActiveChannel } from "@transport/channel";

const FLUSH_INTERVAL_MS = 100;
const SAMPLE_RATE_HZ = 16_000;
const FORMAT = "pcm_s16le";

export type AudioRelayHandle = {
  stop: () => Promise<void>;
};

let active: AudioRelayHandle | null = null;

export function isAudioRelayActive(): boolean {
  return active !== null;
}

export async function startAudioRelay(): Promise<AudioRelayHandle> {
  if (active) return active;

  const bridge = await waitForEvenAppBridge();

  const frames: Uint8Array[] = [];
  let totalBytes = 0;
  let firstFrameLogged = false;
  let seq = 0;

  const unsubscribe = await onEvenHubEvent((event) => {
    if (!event.audioEvent) return;

    const pcm = event.audioEvent.audioPcm;

    // First-frame diagnostic: nail down the actual byte layout the SDK
    // delivers. memory `g2-protocol-knowledge.md` (40B/10ms LC3) and the
    // session note (100ms PCM frames) disagreed; this log resolves it
    // before D1b STT integration.
    if (!firstFrameLogged) {
      firstFrameLogged = true;
      const ctorName = (pcm as unknown as { constructor?: { name?: string } })?.constructor?.name;
      logInfo("audio-relay: first audioPcm frame", {
        ctor: ctorName,
        length: pcm?.length ?? 0,
      });
    }

    if (!pcm || pcm.length === 0) return;
    frames.push(pcm);
    totalBytes += pcm.length;
  });

  const flushTimer = window.setInterval(() => {
    if (frames.length === 0) return;

    const ch = getActiveChannel();
    if (!ch) {
      // Channel down: drop the buffer rather than queueing PCM offline.
      frames.length = 0;
      totalBytes = 0;
      logWarn("audio-relay: channel down, dropping buffered PCM");
      return;
    }

    const framesCount = frames.length;
    const bytes = totalBytes;
    const merged = mergeFrames(frames, bytes);
    frames.length = 0;
    totalBytes = 0;
    seq += 1;

    ch.push("audio_chunk", {
      seq,
      pcm_b64: toBase64(merged),
      frames: framesCount,
      bytes,
      sample_rate: SAMPLE_RATE_HZ,
      format: FORMAT,
    });
  }, FLUSH_INTERVAL_MS);

  const result = await safeCall("audioControl(true)", () => bridge.audioControl(true));
  if (result === null) {
    window.clearInterval(flushTimer);
    unsubscribe();
    throw new Error("audio-relay: audioControl(true) failed");
  }

  logInfo("audio-relay: started");

  const handle: AudioRelayHandle = {
    stop: async () => {
      window.clearInterval(flushTimer);
      unsubscribe();
      await safeCall("audioControl(false)", () => bridge.audioControl(false));
      active = null;
      logInfo("audio-relay: stopped");
    },
  };
  active = handle;
  return handle;
}

/**
 * Wires the channel's `start_audio` / `stop_audio` events to start/stop the
 * audio relay. PC clients (voice-input) push these on PTT key down/up; the
 * server `broadcast_from!`s them so this Hub App receives them but the PC
 * does not echo to itself.
 *
 * Returns a teardown function that detaches both listeners and stops any
 * active relay. Reentrant signals (start while running, stop while idle)
 * are treated as no-ops so spurious key repeats don't churn the bridge.
 */
export function attachAudioControlListener(channel: Channel): () => void {
  let handle: AudioRelayHandle | null = null;
  let busy = false;

  const startRef = channel.on("start_audio", () => {
    if (busy || handle) return;
    busy = true;

    void (async () => {
      try {
        handle = await startAudioRelay();
        logInfo("audio-relay: started by channel start_audio");
      } catch (err) {
        logError("audio-relay: start_audio handler failed", err);
        handle = null;
      } finally {
        busy = false;
      }
    })();
  });

  const stopRef = channel.on("stop_audio", () => {
    if (busy || !handle) return;
    busy = true;

    void (async () => {
      const h = handle;
      handle = null;
      try {
        await h?.stop();
        logInfo("audio-relay: stopped by channel stop_audio");
      } catch (err) {
        logError("audio-relay: stop_audio handler failed", err);
      } finally {
        busy = false;
      }
    })();
  });

  return () => {
    channel.off("start_audio", startRef);
    channel.off("stop_audio", stopRef);
    if (handle) {
      void handle.stop().catch((err) =>
        logError("audio-relay: detach stop failed", err),
      );
      handle = null;
    }
  };
}

function mergeFrames(frames: Uint8Array[], totalBytes: number): Uint8Array {
  const out = new Uint8Array(totalBytes);
  let offset = 0;
  for (const f of frames) {
    out.set(f, offset);
    offset += f.length;
  }
  return out;
}

// Chunked btoa: splitting the input avoids `String.fromCharCode(...big)`
// stack overflows on large concatenated buffers (a flush can carry up to
// ~3.2KB at 100ms × 16kHz S16LE; harmless here, but keeps the helper
// reusable if the flush window ever grows).
function toBase64(bytes: Uint8Array): string {
  let binary = "";
  const CHUNK = 0x8000;
  for (let i = 0; i < bytes.length; i += CHUNK) {
    const slice = bytes.subarray(i, i + CHUNK);
    binary += String.fromCharCode.apply(
      null,
      slice as unknown as number[],
    );
  }
  return btoa(binary);
}

