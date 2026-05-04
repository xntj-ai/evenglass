//! Phoenix Channel client for the g2-mic-test tool.
//!
//! Wire protocol: Phoenix V2 JSONSerializer (array form)
//!   `[join_ref, ref, topic, event, payload]`
//!
//! The worker owns the WS and runs three concurrent paths in a `tokio::select!`:
//!   1. Outbound: `Cmd` from the UI thread (start/stop_audio, shutdown).
//!   2. Heartbeat: 30s ticker on the `phoenix` topic.
//!   3. Inbound: ws frames (phx_reply, audio_chunk, server-pushed events).
//!
//! State changes + decoded audio bytes are pushed back to the UI through
//! the `Evt` channel — egui polls this channel each frame.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

use anyhow::{anyhow, bail, Context, Result};
use base64::Engine as _;
use futures_util::{SinkExt, StreamExt};
use serde::Deserialize;
use serde_json::{json, Value};
use tokio::sync::mpsc;
use tokio::time::{interval, Duration};
use tokio_tungstenite::tungstenite::protocol::Message;
use tokio_tungstenite::connect_async;
use tracing::{debug, info, warn};

const HEARTBEAT_INTERVAL_SECS: u64 = 30;

/// Connection lifecycle observed by the UI.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChannelState {
    Disconnected,
    Connecting,
    Joined,
}

/// Configuration captured from the UI's input fields.
#[derive(Debug, Clone)]
pub struct G2Config {
    /// `wss://g2.xntj.tv/socket`
    pub wss_url: String,
    /// `https://g2.xntj.tv`
    pub api_url: String,
    /// Browser-copied PC admin session cookie value
    /// (the `_evenglass_web_pc_user_token` cookie).
    pub pc_session_cookie: String,
    /// G2 device_id whose topic this client should join.
    pub device_id: String,
}

impl G2Config {
    pub fn validate(&self) -> Result<()> {
        if self.pc_session_cookie.trim().is_empty() {
            bail!("PC session cookie is empty");
        }
        if self.device_id.trim().is_empty() {
            bail!("device_id is empty");
        }
        if !self.wss_url.starts_with("ws://") && !self.wss_url.starts_with("wss://") {
            bail!("WSS URL must start with ws:// or wss://");
        }
        Ok(())
    }

    pub fn topic(&self) -> String {
        format!("g2:device:{}", self.device_id)
    }
}

/// Commands the UI sends to the worker.
pub enum Cmd {
    StartAudio,
    StopAudio,
    Shutdown,
}

/// Events the worker sends to the UI.
pub enum Evt {
    StateChanged(ChannelState),
    Error(String),
    /// Decoded PCM s16le bytes (16kHz mono). Forwarded as-is so the UI
    /// can both compute a VU meter and write WAV without re-decoding.
    AudioChunk(Vec<u8>),
}

#[derive(Deserialize)]
struct SocketTokenResponse {
    channel_token: String,
}

/// Spawns the worker; returns the cmd sink + evt source. The worker
/// reports `StateChanged(Connecting → Joined)` (or `Error` then
/// `Disconnected`) so the UI never has to poll for connection status.
pub fn spawn_worker(
    rt: &tokio::runtime::Runtime,
    cfg: G2Config,
) -> (mpsc::UnboundedSender<Cmd>, mpsc::UnboundedReceiver<Evt>) {
    let (cmd_tx, cmd_rx) = mpsc::unbounded_channel::<Cmd>();
    let (evt_tx, evt_rx) = mpsc::unbounded_channel::<Evt>();

    rt.spawn(async move {
        let _ = evt_tx.send(Evt::StateChanged(ChannelState::Connecting));
        if let Err(e) = run(cfg, cmd_rx, evt_tx.clone()).await {
            warn!("g2-mic-test worker exited with error: {e:#}");
            let _ = evt_tx.send(Evt::Error(format!("{e:#}")));
        }
        let _ = evt_tx.send(Evt::StateChanged(ChannelState::Disconnected));
    });

    (cmd_tx, evt_rx)
}

async fn run(
    cfg: G2Config,
    mut cmd_rx: mpsc::UnboundedReceiver<Cmd>,
    evt_tx: mpsc::UnboundedSender<Evt>,
) -> Result<()> {
    cfg.validate()?;

    let channel_token = fetch_channel_token(&cfg)
        .await
        .context("fetch /api/pc/socket-token")?;

    // Phoenix's `socket "/socket", UserSocket` mounts the websocket at
    // `/socket/websocket` and the longpoll at `/socket/longpoll`. The
    // phoenix.js client appends `/websocket` for you; raw tungstenite
    // does not, so we have to do it explicitly here. The user-facing
    // config field stays `wss://.../socket` to match Phoenix conventions.
    let base = cfg.wss_url.trim_end_matches('/');
    let url = format!("{base}/websocket?token={channel_token}&vsn=2.0.0");
    let (ws, _resp) = connect_async(&url)
        .await
        .with_context(|| format!("connect_async {url}"))?;
    info!("g2-mic-test: ws connected");

    let topic = cfg.topic();
    let (mut sink, mut stream) = ws.split();
    let ref_counter = Arc::new(AtomicU64::new(1));
    let join_ref = next_ref(&ref_counter);

    // phx_join: msg_ref equals join_ref by Phoenix convention.
    let join_frame = encode_frame(Some(&join_ref), Some(&join_ref), &topic, "phx_join", json!({}));
    sink.send(Message::Text(join_frame))
        .await
        .context("send phx_join")?;

    let mut hb = interval(Duration::from_secs(HEARTBEAT_INTERVAL_SECS));
    hb.tick().await; // skip the first immediate tick

    let mut joined = false;

    loop {
        tokio::select! {
            cmd = cmd_rx.recv() => {
                match cmd {
                    Some(Cmd::StartAudio) => {
                        let mref = next_ref(&ref_counter);
                        let frame = encode_frame(
                            Some(&join_ref), Some(&mref), &topic, "start_audio",
                            json!({ "seq": mref.parse::<u64>().unwrap_or(0) }),
                        );
                        if let Err(e) = sink.send(Message::Text(frame)).await {
                            return Err(anyhow!("send start_audio: {e}"));
                        }
                    }
                    Some(Cmd::StopAudio) => {
                        let mref = next_ref(&ref_counter);
                        let frame = encode_frame(
                            Some(&join_ref), Some(&mref), &topic, "stop_audio",
                            json!({ "seq": mref.parse::<u64>().unwrap_or(0) }),
                        );
                        if let Err(e) = sink.send(Message::Text(frame)).await {
                            return Err(anyhow!("send stop_audio: {e}"));
                        }
                    }
                    Some(Cmd::Shutdown) | None => {
                        let leave_ref = next_ref(&ref_counter);
                        let frame = encode_frame(
                            Some(&join_ref), Some(&leave_ref), &topic, "phx_leave", json!({}),
                        );
                        let _ = sink.send(Message::Text(frame)).await;
                        let _ = sink.close().await;
                        return Ok(());
                    }
                }
            }

            _ = hb.tick() => {
                let mref = next_ref(&ref_counter);
                let frame = encode_frame(None, Some(&mref), "phoenix", "heartbeat", json!({}));
                if let Err(e) = sink.send(Message::Text(frame)).await {
                    return Err(anyhow!("send heartbeat: {e}"));
                }
            }

            inbound = stream.next() => {
                let Some(item) = inbound else {
                    info!("g2-mic-test: ws stream ended");
                    return Ok(());
                };
                match item {
                    Ok(Message::Text(t)) => {
                        match decode_frame(&t) {
                            Ok(frame) => handle_inbound(frame, &topic, &evt_tx, &mut joined),
                            Err(e) => warn!("decode frame: {e}; raw={t}"),
                        }
                    }
                    Ok(Message::Binary(_)) => {}
                    Ok(Message::Ping(p)) => {
                        let _ = sink.send(Message::Pong(p)).await;
                    }
                    Ok(Message::Close(_)) => {
                        info!("g2-mic-test: ws received Close");
                        return Ok(());
                    }
                    Ok(_) => {}
                    Err(e) => return Err(anyhow!("ws read: {e}")),
                }
            }
        }
    }
}

async fn fetch_channel_token(cfg: &G2Config) -> Result<String> {
    let url = format!("{}/api/pc/socket-token", cfg.api_url.trim_end_matches('/'));
    // _evenglass_key is the Plug.Session encrypted-cookie name (see
    // EvenglassWeb.Endpoint @session_options). It carries the encrypted
    // :pc_user_token field; Phoenix decrypts it using secret_key_base
    // and PCUserAuth.fetch_current_scope_for_pc_user/2 reads the token.
    let cookie_value = format!("_evenglass_key={}", cfg.pc_session_cookie);

    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(10))
        .build()
        .context("build reqwest client")?;

    let resp = client
        .post(&url)
        .header("Cookie", cookie_value)
        .header("accept", "application/json")
        .send()
        .await
        .with_context(|| format!("POST {url}"))?;

    let status = resp.status();
    if !status.is_success() {
        let body = resp.text().await.unwrap_or_default();
        bail!("socket-token endpoint returned {status}: {body}");
    }

    let parsed: SocketTokenResponse = resp.json().await.context("parse SocketTokenResponse")?;
    Ok(parsed.channel_token)
}

fn next_ref(counter: &Arc<AtomicU64>) -> String {
    counter.fetch_add(1, Ordering::Relaxed).to_string()
}

fn encode_frame(
    join_ref: Option<&str>,
    msg_ref: Option<&str>,
    topic: &str,
    event: &str,
    payload: Value,
) -> String {
    let arr: Vec<Value> = vec![
        join_ref.map(|s| Value::String(s.to_string())).unwrap_or(Value::Null),
        msg_ref.map(|s| Value::String(s.to_string())).unwrap_or(Value::Null),
        Value::String(topic.to_string()),
        Value::String(event.to_string()),
        payload,
    ];
    Value::Array(arr).to_string()
}

#[derive(Debug)]
struct InboundFrame {
    topic: String,
    event: String,
    payload: Value,
}

fn decode_frame(text: &str) -> Result<InboundFrame> {
    let v: Value = serde_json::from_str(text).context("parse json")?;
    let arr = v
        .as_array()
        .ok_or_else(|| anyhow!("expected array, got {v}"))?;
    if arr.len() != 5 {
        bail!("expected 5-element array, got {} elements", arr.len());
    }
    let take_str = |idx: usize| -> Result<String> {
        match &arr[idx] {
            Value::String(s) => Ok(s.clone()),
            other => bail!("expected string at idx {idx}, got {other}"),
        }
    };
    Ok(InboundFrame {
        topic: take_str(2)?,
        event: take_str(3)?,
        payload: arr[4].clone(),
    })
}

fn handle_inbound(
    frame: InboundFrame,
    topic: &str,
    evt_tx: &mpsc::UnboundedSender<Evt>,
    joined: &mut bool,
) {
    if frame.topic != topic && frame.topic != "phoenix" {
        debug!("ignoring frame for topic {}", frame.topic);
        return;
    }

    match frame.event.as_str() {
        "phx_reply" => {
            let status = frame
                .payload
                .get("status")
                .and_then(|s| s.as_str())
                .unwrap_or("?");
            if !*joined && frame.topic == topic {
                if status == "ok" {
                    *joined = true;
                    let _ = evt_tx.send(Evt::StateChanged(ChannelState::Joined));
                } else {
                    let response = frame.payload.get("response").cloned().unwrap_or(Value::Null);
                    let _ = evt_tx.send(Evt::Error(format!(
                        "phx_join rejected (status={status} response={response})"
                    )));
                }
            }
        }

        "audio_chunk" => {
            let Some(pcm_b64) = frame.payload.get("pcm_b64").and_then(|v| v.as_str()) else {
                warn!("audio_chunk missing pcm_b64");
                return;
            };
            match base64::engine::general_purpose::STANDARD.decode(pcm_b64) {
                Ok(bytes) => {
                    let _ = evt_tx.send(Evt::AudioChunk(bytes));
                }
                Err(e) => warn!("base64 decode failed: {e}"),
            }
        }

        "start_audio" | "stop_audio" => {
            // Echo of our own broadcast (broadcast_from! skips the channel
            // server pid, but we re-subscribed via our own join). Not an
            // error condition — log only.
            debug!("observed {} echo on {}", frame.event, frame.topic);
        }

        "phx_close" | "phx_error" => {
            let _ = evt_tx.send(Evt::Error(format!(
                "server sent {} on {}",
                frame.event, frame.topic
            )));
        }

        other => debug!("ignoring event {other}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn topic_is_g2_device_prefix() {
        let cfg = G2Config {
            wss_url: "wss://g2.xntj.tv/socket".into(),
            api_url: "https://g2.xntj.tv".into(),
            pc_session_cookie: "x".into(),
            device_id: "abc-123".into(),
        };
        assert_eq!(cfg.topic(), "g2:device:abc-123");
    }

    #[test]
    fn validate_rejects_empty_cookie_or_device() {
        let bad = G2Config {
            wss_url: "wss://g2.xntj.tv/socket".into(),
            api_url: "https://g2.xntj.tv".into(),
            pc_session_cookie: "  ".into(),
            device_id: "x".into(),
        };
        assert!(bad.validate().is_err());
    }

    #[test]
    fn validate_rejects_http_wss() {
        let bad = G2Config {
            wss_url: "https://g2.xntj.tv/socket".into(),
            api_url: "https://g2.xntj.tv".into(),
            pc_session_cookie: "x".into(),
            device_id: "x".into(),
        };
        assert!(bad.validate().is_err());
    }

    #[test]
    fn frame_roundtrip() {
        let f = encode_frame(Some("1"), Some("2"), "g2:device:x", "ping", json!({"a": 1}));
        let d = decode_frame(&f).expect("decode");
        assert_eq!(d.topic, "g2:device:x");
        assert_eq!(d.event, "ping");
        assert_eq!(d.payload, json!({"a": 1}));
    }
}
