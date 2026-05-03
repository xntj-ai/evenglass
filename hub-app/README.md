# hub-app

Even Hub web app for evenglass — runs inside the Even App container on the operator's phone, bridges G2 BLE I/O to the evenglass server, and lets PC business logic drive the glasses through the server.

## Stack

- pnpm 10 + Node 22
- Vite 7, TypeScript 5.9 strict mode
- Transport: Phoenix Channel WSS (`phoenix`) + Ky HTTP fallback
- State: Nanostores (no React)
- Offline queue: idb-keyval (IndexedDB)
- Errors: Sentry browser SDK
- Debug overlay: Eruda (toggle via `VITE_DEBUG_OVERLAY=true`)

## Layout

```
src/
├── main.ts              app bootstrap — wires bridge, transport, features
├── bridge/              talks to the Even Hub native bridge (waitForEvenAppBridge, safe-call, events)
├── transport/           server I/O — Phoenix socket/channel, Ky HTTP, IndexedDB offline queue
├── features/
│   └── input-relay/     subscribes to G2 events from bridge → forwards to server
├── services/            cross-cutting (logger, sentry init, error bus, nanostores root)
├── shared/              api-types (auto-generated from ../priv/static/openapi.json), constants
└── debug/               eruda overlay loader (lazy, dev/staging only)
```

## Getting started

```sh
pnpm install
pnpm dev          # vite dev server on :5173
pnpm typecheck    # tsc --noEmit, fails on any type error
pnpm build        # produces dist/
```

## Auth model

1. **First launch**: operator types a 6-digit `enrollment_code` from `/admin/devices/new`. App calls `POST /api/g2/enroll` and stores the returned 90-day `device_token`.
2. **Steady state**: every event upload uses `Authorization: Bearer <device_token>`.
3. **WSS connect**: app calls `POST /api/g2/socket-token`, receives a 2-hour `channel_token`, opens `wss://g2.xntj.tv/socket?token=<channel_token>`.
4. **Revocation**: admin clicks "Revoke device" on `/admin/devices/:id`. The server clears the device's `jti` (next request 401s) and broadcasts `disconnect` (active socket drops).

## Building & sideloading

The hub-app builds to `dist/` and is wrapped into an `.ehpk` archive (Even Hub package format) per Even Hub SDK docs. Sideload via Even App's developer mode (or Hub Store after publishing).

## Type generation

`src/shared/api-types.ts` is regenerated from the server-side OpenAPI spec:

```sh
# from repo root
curl -s https://g2.xntj.tv/api/openapi.json > /tmp/openapi.json
npx openapi-typescript /tmp/openapi.json -o hub-app/src/shared/api-types.ts
```

(Wired into CI in milestone 5.)
