// Phoenix Channel client. Mints a short-lived channel_token via the
// authenticated REST endpoint right before connecting, then joins the
// per-device topic.
//
// Cache invariant: the module-level `channel` and `socket` references
// point at the **currently usable** instances. On socket close/error we
// reset both so the next connectChannel() call mints a fresh
// channel_token and reopens cleanly. The phoenix.js auto-reconnect logic
// would keep the socket itself alive, but its 2h-old channel_token
// would expire mid-session — re-minting on every reconnect is the
// simpler and more correct path.

import { Socket, type Channel } from "phoenix";

import { logInfo, logWarn } from "@services/logger";
import { $deviceId } from "@shared/store";

import { makeHttp } from "./http";
import { TRANSPORT_WSS_BASE } from "./index";

let socket: Socket | null = null;
let channel: Channel | null = null;

const JOIN_TIMEOUT_MS = 15_000;

/**
 * Returns the currently joined channel, or null when there isn't one
 * (never connected, mid-reconnect, or socket closed). Callers that need
 * to push best-effort frames — e.g. the audio-relay — should null-check
 * and drop on the floor when the link is down, rather than queueing PCM.
 */
export function getActiveChannel(): Channel | null {
  if (channel && channel.state === "joined") return channel;
  return null;
}

async function fetchChannelToken(): Promise<string> {
  const http = makeHttp();
  const res = await http
    .post("api/g2/socket-token")
    .json<{ channel_token: string; expires_in: number }>();
  return res.channel_token;
}

function resetCache(reason: string): void {
  if (channel || socket) {
    logWarn(`socket cache reset: ${reason}`);
    channel = null;
    socket = null;
  }
}

export async function connectChannel(): Promise<Channel> {
  // Reuse only when the cached channel is actually live. phoenix.js
  // exposes state predicates we can rely on across versions.
  if (channel && (channel.state === "joined" || channel.state === "joining")) {
    return channel;
  }

  const deviceId = $deviceId.get();
  if (!deviceId) {
    throw new Error("connectChannel: device not enrolled");
  }

  // Tear any stale state down before rebuilding — keeps invariants tight.
  if (socket) {
    try {
      socket.disconnect();
    } catch (err) {
      logWarn("socket.disconnect during reconnect failed", err);
    }
    socket = null;
    channel = null;
  }

  const token = await fetchChannelToken();

  const sock = new Socket(`${TRANSPORT_WSS_BASE}/socket`, { params: { token } });
  sock.onError((err) => {
    logWarn("socket error", err);
    resetCache("onError");
  });
  sock.onClose(() => {
    logWarn("socket closed");
    resetCache("onClose");
  });
  sock.connect();
  socket = sock;

  const ch = sock.channel(`g2:device:${deviceId}`, {});

  await new Promise<void>((resolve, reject) => {
    const watchdog = setTimeout(() => {
      reject(new Error("channel join watchdog: no reply within 30s"));
    }, JOIN_TIMEOUT_MS * 2);

    ch.join(JOIN_TIMEOUT_MS)
      .receive("ok", () => {
        clearTimeout(watchdog);
        logInfo("channel joined");
        resolve();
      })
      .receive("error", (resp) => {
        clearTimeout(watchdog);
        reject(new Error(`join failed: ${JSON.stringify(resp)}`));
      })
      .receive("timeout", () => {
        clearTimeout(watchdog);
        reject(new Error("channel join timeout"));
      });
  });

  channel = ch;
  return ch;
}

export function disconnectChannel(): void {
  channel?.leave();
  socket?.disconnect();
  channel = null;
  socket = null;
}
