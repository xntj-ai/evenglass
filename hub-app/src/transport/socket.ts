// Phoenix Channel client. We mint a short-lived channel_token via the
// authenticated REST endpoint right before connecting, then join the
// per-device topic. Reconnect logic comes from phoenix.js itself.

import { Socket, type Channel } from "phoenix";

import { logInfo, logWarn } from "@services/logger";
import { $deviceId } from "@shared/store";

import { makeHttp } from "./http";
import { TRANSPORT_WSS_BASE } from "./index";

let socket: Socket | null = null;
let channel: Channel | null = null;

async function fetchChannelToken(): Promise<string> {
  const http = makeHttp();
  const res = await http
    .post("api/g2/socket-token")
    .json<{ channel_token: string; expires_in: number }>();
  return res.channel_token;
}

export async function connectChannel(): Promise<Channel> {
  if (channel) return channel;

  const deviceId = $deviceId.get();
  if (!deviceId) {
    throw new Error("connectChannel: device not enrolled");
  }

  const token = await fetchChannelToken();

  socket = new Socket(`${TRANSPORT_WSS_BASE}/socket`, { params: { token } });
  socket.connect();
  socket.onError((err) => logWarn("socket error", err));
  socket.onClose(() => logWarn("socket closed"));

  const ch = socket.channel(`g2:device:${deviceId}`, {});

  await new Promise<void>((resolve, reject) => {
    ch.join()
      .receive("ok", () => {
        logInfo("channel joined");
        resolve();
      })
      .receive("error", (resp) => reject(new Error(`join failed: ${JSON.stringify(resp)}`)))
      .receive("timeout", () => reject(new Error("join timeout")));
  });

  channel = ch;
  return ch;
}

export function disconnectChannel(): void {
  channel?.leave();
  channel = null;
  socket?.disconnect();
  socket = null;
}
