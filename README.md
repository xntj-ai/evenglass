# evenglass

> Real-time relay between **Even Realities G2** smart glasses, an Android **phone hub**, a **Phoenix/Elixir** server, and a **Windows PC**. Goal: use the G2 as a PC peripheral (mic input + display output).

> ⚠️ **Status: archived (2026-05-04).** Development stopped before the "G2 as a Windows microphone" loop closed. The author doesn't wear glasses daily, the BLE audio side of G2 is still closed, and routing every byte through a phone hub turned out to be unavoidable. **The repo is left public so the working pieces — server, hub web app, and the Rust diagnostic tool — can save someone else a few weeks.**
>
> 📝 中文复盘见 [`docs/retrospective.html`](docs/retrospective.html)（包含技术总结 + 放弃理由 + 给后来者的避坑提示）。

---

## What's in this repo

```
[G2 glasses] ─BLE→ [Android phone, Even Hub Web App] ─WSS→ [Phoenix server] ─WSS→ [PC tools]
```

| Path | What it is |
|---|---|
| `lib/`, `config/`, `priv/`, `mix.exs` | **Phoenix 1.8.5 / LiveView 1.1.0** server — sessions, events, REST + Channel API, `/admin` LiveView, OpenAPI, rate limiting, TOTP, double-role channel auth |
| `hub-app/` | **TypeScript + Vite** Web App that runs inside the Even Hub container on the phone, talks to the Even Hub SDK, and pushes G2 events into the Phoenix channel |
| `tools/g2-mic-test/` | **Rust + egui** diagnostic — connects to the server channel, triggers G2 mic, decodes the relayed PCM, and writes a WAV. Includes a hand-written **Phoenix V2 wire-format** client (rare in Rust) |
| `deploy/Caddyfile` | Reverse proxy + WebSocket keep-alive for production |
| `Dockerfile` + `docker-compose.yml` | Multi-stage build (Elixir 1.18 / OTP 27 / Debian slim) + Postgres 17 |

---

## What got built — milestone-by-milestone

### Milestone A — Data model + admin live stream
- `sessions(device_id, last_seen_at)` + `events(direction up/down, type, payload jsonb, session_id)`
- `Sessions.touch_session_by_device_id!` (atomic upsert) + `Events.create_event!` (broadcasts to PubSub topic `"events:all"`)
- `/admin/events` LiveView with a 50-row stream + diff-pushed updates. Tested smooth at 60 events/min.
- Releases run migrations via `bin/evenglass eval "Evenglass.Release.migrate()"`.

### Milestone B — Real REST endpoints + per-device filtering
- `POST /api/g2/events` (phone uplink) and `POST /api/g2/commands` (PC downlink).
- `/admin/devices` listing + `/admin/events?device=<id>` filtering.

### Milestone C — Production hardening
- **Auth** — `phx.gen.auth`-based PC admin accounts with **TOTP** enrollment gate (NimbleTOTP + EQRCode).
- **Rate limiting** — Hammer 7.x ETS backend on every public POST.
- **Idempotency** — header-keyed in-process cache for duplicate POSTs.
- **OpenAPI** — `open_api_spex` generated spec at `/api/openapi`.
- **Web origin checks + CORS** — `check_origin` configured to handle both `g2.xntj.tv` and the Vite dev origin during browser e2e.

### Milestone D1a — Audio uplink
- Hub App aggregates G2 mic frames over a 100ms window and pushes them through the channel as `audio_chunk` (base64 PCM).
- Server is a pass-through for the PCM bytes (PCM is "live or never" — never buffered to disk) but writes one `audio_meta` event per second per device for `/admin/events` visibility.
- **Protocol finding** (correcting the assumption documented in some Even-G2 reverse engineering notes): the simulator's `audioPcm` payload is **not LC3 (40 B / 10 ms)**. It is **16 kHz mono S16LE PCM, 100 ms frames, 3200 B/frame**. No LC3 decoder needed downstream. (Counters logged in the D1a session memory.)

### Milestone D1b — Bidirectional control plane
- New PC socket: `pc_admin` role with its own salt-separated channel token (`Auth.Token` has two clauses — one for `device_id`, one for `pc_user_id`).
- Channel events `start_audio` / `stop_audio` are pushed by the PC, fan out via `broadcast_from!` so the hub-app receives them and the publisher does not echo to itself.
- `tools/g2-mic-test/` end-to-end verifies the loop: PC → server → hub → G2 mic → PCM → PC → WAV file. Real-time RMS shown as a dBFS meter in the egui window.

---

## What was *not* solved

- **Real-device sideload.** As of 2026-05-04, `com.even.sg` v2.2.0 (Chinese build) had no QR-scan entry to side-load custom Hub apps. All audio testing was done against the **Even Hub simulator**. Once Even Realities ships a sideload entry (or the Hub Web App distribution opens up), the same code should work on real glasses without changes.
- **G2 as a Windows microphone.** The plan was to bridge the relayed PCM into a virtual microphone via VB-Audio Cable so any app (voice-input, Teams, OBS, etc.) could pick "G2" from its mic dropdown. The bridge was designed (`tools/g2-virtual-mic/`, never written) but never built — see retrospective.
- **G2 BLE direct from PC.** Not investigated; the BLE protocol is closed-source on the audio side, and Even Hub remains the only short-term path.
- **Display downlink.** Phoenix `g2_controller.ex` accepts PC-issued `commands`, but the hub-app side that renders them on the G2 lens display was a planned Milestone D2.

---

## Run it locally

Prereqs: **Erlang/OTP 27**, **Elixir 1.18**, **Postgres 17**, **pnpm 9**, **Rust stable** (only if you want to build `tools/g2-mic-test`).

```bash
# 1. Server
mix setup
mix phx.server     # http://localhost:4000

# 2. Hub web app (separate terminal)
cd hub-app
pnpm install
pnpm dev           # opens Vite dev server, set EVENGLASS_BASE_URL in .env to point at :4000

# 3. Diagnostic tool (separate terminal)
cd tools/g2-mic-test
cargo run          # egui window — paste server URL + admin session cookie, click Connect
```

The `mix test` suite (147 tests as of D1b) needs a running Postgres on `localhost:5432` with `postgres/postgres`. CI uses the same fixtures.

---

## Deploy (reference, not maintained)

A working production deployment was running on a single Debian VM with Caddy + Docker Compose:

```bash
# On the server
cp .env.example .env       # fill in SECRET_KEY_BASE, POSTGRES_PASSWORD, salts, etc.
docker compose up -d --build
docker compose exec app /app/bin/evenglass eval \
    'Evenglass.Release.migrate()'
docker compose exec app /app/bin/evenglass eval \
    'Evenglass.Release.create_pc_admin("admin@example.com", "change-me-on-first-login")'
sudo cp deploy/Caddyfile /etc/caddy/Caddyfile && sudo systemctl reload caddy
```

The `Dockerfile` is tuned for build environments where `github.com` and the canonical `hex.pm` CDN are slow/unreachable — it pre-vendors `heroicons` and the Tailwind binary, and switches to Tencent Cloud / upyun mirrors. Strip those if you build from a fast egress.

---

## For people forking this

**Useful starting points:**
- The **Phoenix V2 wire-format client in Rust** (`tools/g2-mic-test/src/channel.rs`) is rare and was annoying to write — `phoenix.js` adds the `/websocket` suffix and 2.0.0 vsn automatically; raw clients have to do it manually. The 30s heartbeat + 5-tuple frame layout is in there.
- The **double-role socket** (`device` vs `pc_admin` clauses on a single `UserSocket`, with separate token salts so a leaked device token can't impersonate an admin) is in `lib/evenglass_web/channels/user_socket.ex` and `lib/evenglass/auth/token.ex`.
- The **TOTP enrollment gate** for first-login admins (`PCUserAuth.require_totp_enrolled/2`) is one of the few production-grade examples I've seen for `phx.gen.auth` + NimbleTOTP — most blog posts stop at the QR code render.

**Avoid:**
- Don't trust "G2 audio is LC3" without measuring on your own hardware — the Hub simulator hands back PCM. If real glasses behave differently, log frame sizes before assuming a codec.
- Don't try to integrate this into someone else's project (e.g. a third-party voice-input app) by editing their code — write a system-level audio bridge instead. Virtual-cable bridges (VB-Audio Cable etc.) are the path of least resistance on Windows; building a signed virtual audio driver yourself costs ~$300/year + weeks of kernel work.
- Don't assume sideload is available. As of writing, the Chinese `com.even.sg` build does not expose it.

**See also**
- [`docs/retrospective.html`](docs/retrospective.html) — full Chinese retrospective + architecture notes
- [Even Realities G1 EvenDemoApp](https://github.com/even-realities/EvenDemoApp) (Flutter, BLE protocol reference)
- [i-soxi/even-g2-protocol](https://github.com/i-soxi/even-g2-protocol) (Python reverse engineering)

---

## License

MIT — see [LICENSE](LICENSE).
