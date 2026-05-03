// Ky-based HTTP client. Always attaches the device_token Bearer header.

import ky, { type KyInstance } from "ky";

import { $deviceToken } from "@shared/store";

import { TRANSPORT_API_BASE } from "./index";

export function makeHttp(): KyInstance {
  return ky.create({
    prefixUrl: TRANSPORT_API_BASE,
    timeout: 10_000,
    retry: { limit: 0 },
    hooks: {
      beforeRequest: [
        (request) => {
          const token = $deviceToken.get();
          if (token) {
            request.headers.set("Authorization", `Bearer ${token}`);
          }
        },
      ],
    },
  });
}
