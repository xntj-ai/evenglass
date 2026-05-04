# g2-mic-test

Standalone PC tool to verify the **G2 → server → PC audio relay** end-to-end.
Subscribes to the production Phoenix Channel `g2:device:<id>`, pushes
`start_audio` / `stop_audio` like any future PC client (voice-input or a
virtual-mic bridge) would, decodes the streamed S16LE PCM, shows a live
VU meter, and optionally records to a 16 kHz mono WAV.

It deliberately does **not** integrate with voice-input or anything else —
it's a diagnostic tool for the relay link itself.

## Run

```sh
cd tools/g2-mic-test
cargo run --release
```

## Usage

1. Log in to https://g2.xntj.tv/admin in a browser (admin email + TOTP).
2. Open DevTools → Application → Cookies, copy the value of
   `_evenglass_web_pc_user_token`.
3. Open admin → /admin/devices, copy the `device_id` you want to listen to.
4. Paste both into the tool and click **Connect**.
5. Click **▶ Start G2 mic** to push `start_audio` on the channel — the Hub
   App receives it and calls `audioControl(true)`. Watch the VU meter fill.
6. Click **⏺ Start recording** to dump the stream as `g2-mic-<timestamp>.wav`.

## Wire contract

- `wss://g2.xntj.tv/socket?token=<channel_token>&vsn=2.0.0`
- `phx_join` on `g2:device:<device_id>`
- Push `start_audio` / `stop_audio` (`broadcast_from!` to Hub App)
- Receive `audio_chunk` payloads `{seq, pcm_b64, frames, bytes, sample_rate, format}`

PCM contract observed in production (commit `0a9291c`):
16 kHz, S16LE, mono, ~100ms per frame ≈ 3200 bytes.
