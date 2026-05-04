//! g2-mic-test — minimal egui app that proves the G2 → server → PC audio
//! relay end-to-end.
//!
//! Wire steps the user executes in the UI:
//!   1. Paste device_id + the `_evenglass_web_pc_user_token` cookie value
//!      copied from a logged-in browser session.
//!   2. Click **Connect** → the worker mints a `:pc_admin` channel_token
//!      via `POST /api/pc/socket-token` and joins `g2:device:<id>`.
//!   3. Click **Start G2 mic** → pushes `start_audio` on the channel; the
//!      Hub App receives it (broadcast_from!) and calls `audioControl(true)`.
//!   4. Watch the VU meter fill as audio_chunk frames arrive.
//!   5. Optionally **Record** to capture the PCM stream as a 16kHz mono
//!      S16LE wav file, named with the current local timestamp.
//!
//! Architecture: egui owns app state in immediate-mode; a single tokio
//! worker (spawned on Connect) runs the WS + heartbeat. UI ↔ worker
//! communicate via `tokio::sync::mpsc` channels — no shared mutexes.

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod channel;
mod config;

use std::path::PathBuf;
use std::sync::Arc;

use anyhow::{Context, Result};
use eframe::egui;
use hound::{SampleFormat, WavSpec, WavWriter};
use tokio::sync::mpsc;
use tracing::warn;

use channel::{spawn_worker, ChannelState, Cmd, Evt, G2Config};
use config::PersistedConfig;

const SAMPLE_RATE: u32 = 16_000;

/// VU smoothing factor — higher = snappier meter, lower = smoother.
/// 0.3 gives ~3-frame settle at 10Hz audio_chunk rate, matching the eye.
const VU_ALPHA: f32 = 0.3;

fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "g2_mic_test=info,channel=info".into()),
        )
        .init();

    let rt = Arc::new(
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .worker_threads(2)
            .build()
            .context("build tokio runtime")?,
    );

    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([520.0, 540.0])
            .with_title("G2 Mic Test"),
        ..Default::default()
    };

    let persisted = PersistedConfig::load();

    eframe::run_native(
        "G2 Mic Test",
        options,
        Box::new(move |_cc| Ok(Box::new(App::new(rt.clone(), persisted)))),
    )
    .map_err(|e| anyhow::anyhow!("eframe: {e}"))?;
    Ok(())
}

struct App {
    rt: Arc<tokio::runtime::Runtime>,

    // Config inputs
    wss_url: String,
    api_url: String,
    device_id: String,
    cookie: String,

    // Connection state
    state: ChannelState,
    last_error: Option<String>,

    // Audio mic flag — purely a UI toggle hint; the actual state is on the
    // Hub App side. We send Cmd::StartAudio/StopAudio.
    mic_on: bool,

    // VU meter state
    vu: f32,
    bytes_received: u64,

    // Worker channels (Some after Connect, None after Disconnect)
    cmd_tx: Option<mpsc::UnboundedSender<Cmd>>,
    evt_rx: Option<mpsc::UnboundedReceiver<Evt>>,

    // Recording state
    recording: bool,
    record_path: Option<PathBuf>,
    record_writer: Option<WavWriter<std::io::BufWriter<std::fs::File>>>,
    record_samples: u64,
}

impl App {
    fn new(rt: Arc<tokio::runtime::Runtime>, persisted: PersistedConfig) -> Self {
        Self {
            rt,
            wss_url: persisted.wss_url,
            api_url: persisted.api_url,
            device_id: persisted.device_id,
            cookie: persisted.cookie,
            state: ChannelState::Disconnected,
            last_error: None,
            mic_on: false,
            vu: 0.0,
            bytes_received: 0,
            cmd_tx: None,
            evt_rx: None,
            recording: false,
            record_path: None,
            record_writer: None,
            record_samples: 0,
        }
    }

    fn pump_events(&mut self) {
        // Drain into a buffer first to release the &mut borrow on
        // self.evt_rx — handlers below need &mut self for stop_recording etc.
        let mut events: Vec<Evt> = Vec::new();
        if let Some(rx) = self.evt_rx.as_mut() {
            while let Ok(evt) = rx.try_recv() {
                events.push(evt);
            }
        }
        for evt in events {
            match evt {
                Evt::StateChanged(s) => {
                    self.state = s;
                    if s == ChannelState::Disconnected {
                        // Reset transient flags when the worker dies.
                        self.cmd_tx = None;
                        self.mic_on = false;
                        if self.recording {
                            self.stop_recording();
                        }
                    }
                }
                Evt::Error(msg) => {
                    warn!("worker error: {msg}");
                    self.last_error = Some(msg);
                }
                Evt::AudioChunk(bytes) => {
                    self.bytes_received += bytes.len() as u64;
                    let rms = compute_rms_s16le(&bytes);
                    self.vu = self.vu * (1.0 - VU_ALPHA) + rms * VU_ALPHA;

                    if let Some(w) = self.record_writer.as_mut() {
                        for chunk in bytes.chunks_exact(2) {
                            let sample = i16::from_le_bytes([chunk[0], chunk[1]]);
                            if let Err(e) = w.write_sample(sample) {
                                warn!("wav write failed: {e}");
                                break;
                            }
                            self.record_samples += 1;
                        }
                    }
                }
            }
        }
    }

    fn connect(&mut self) {
        let cfg = G2Config {
            wss_url: self.wss_url.trim().to_string(),
            api_url: self.api_url.trim().to_string(),
            pc_session_cookie: self.cookie.trim().to_string(),
            device_id: self.device_id.trim().to_string(),
        };
        if let Err(e) = cfg.validate() {
            self.last_error = Some(format!("config invalid: {e}"));
            return;
        }
        self.last_error = None;
        self.bytes_received = 0;
        self.vu = 0.0;

        // Persist now (not on Joined) — cookie/device may already be wrong,
        // but the user clearly wants these inputs remembered for the next
        // launch either way; correct ones overwrite as soon as they retry.
        let to_save = PersistedConfig {
            wss_url: cfg.wss_url.clone(),
            api_url: cfg.api_url.clone(),
            device_id: cfg.device_id.clone(),
            cookie: cfg.pc_session_cookie.clone(),
        };
        if let Err(e) = to_save.save() {
            warn!("config save failed: {e:#}");
        }

        let (cmd_tx, evt_rx) = spawn_worker(&self.rt, cfg);
        self.cmd_tx = Some(cmd_tx);
        self.evt_rx = Some(evt_rx);
    }

    fn disconnect(&mut self) {
        if let Some(tx) = self.cmd_tx.as_ref() {
            let _ = tx.send(Cmd::Shutdown);
        }
        // The worker will emit StateChanged(Disconnected) which we handle
        // in pump_events — no need to clear cmd_tx here.
    }

    fn start_g2_mic(&mut self) {
        if let Some(tx) = self.cmd_tx.as_ref() {
            if tx.send(Cmd::StartAudio).is_ok() {
                self.mic_on = true;
            }
        }
    }

    fn stop_g2_mic(&mut self) {
        if let Some(tx) = self.cmd_tx.as_ref() {
            if tx.send(Cmd::StopAudio).is_ok() {
                self.mic_on = false;
            }
        }
    }

    fn start_recording(&mut self) {
        let stamp = chrono::Local::now().format("%Y%m%d-%H%M%S").to_string();
        let path = PathBuf::from(format!("g2-mic-{stamp}.wav"));
        let spec = WavSpec {
            channels: 1,
            sample_rate: SAMPLE_RATE,
            bits_per_sample: 16,
            sample_format: SampleFormat::Int,
        };
        match WavWriter::create(&path, spec) {
            Ok(w) => {
                self.record_writer = Some(w);
                self.record_path = Some(path);
                self.record_samples = 0;
                self.recording = true;
            }
            Err(e) => {
                warn!("create wav failed: {e}");
                self.last_error = Some(format!("wav create: {e}"));
            }
        }
    }

    fn stop_recording(&mut self) {
        self.recording = false;
        if let Some(w) = self.record_writer.take() {
            if let Err(e) = w.finalize() {
                warn!("finalize wav failed: {e}");
                self.last_error = Some(format!("wav finalize: {e}"));
            }
        }
    }
}

impl eframe::App for App {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        self.pump_events();

        // Repaint while connected so the VU meter stays smooth even when
        // the user isn't moving the mouse.
        if self.state != ChannelState::Disconnected || self.mic_on {
            ctx.request_repaint_after(std::time::Duration::from_millis(33));
        }

        egui::CentralPanel::default().show(ctx, |ui| {
            ui.heading("G2 Mic Test");
            ui.separator();

            // Config section
            ui.label("Server (Phoenix WSS):");
            ui.add(egui::TextEdit::singleline(&mut self.wss_url).desired_width(f32::INFINITY));
            ui.label("API base:");
            ui.add(egui::TextEdit::singleline(&mut self.api_url).desired_width(f32::INFINITY));
            ui.label("device_id:");
            ui.add(egui::TextEdit::singleline(&mut self.device_id).desired_width(f32::INFINITY));
            ui.label("PC admin session cookie (_evenglass_key value):");
            ui.add(
                egui::TextEdit::singleline(&mut self.cookie)
                    .password(true)
                    .desired_width(f32::INFINITY),
            );

            ui.separator();

            // Connection controls
            ui.horizontal(|ui| {
                let connected = self.cmd_tx.is_some();
                if !connected {
                    if ui.button("Connect").clicked() {
                        self.connect();
                    }
                } else if ui.button("Disconnect").clicked() {
                    self.disconnect();
                }

                let (color, label) = match self.state {
                    ChannelState::Disconnected => (egui::Color32::GRAY, "Disconnected"),
                    ChannelState::Connecting => (egui::Color32::YELLOW, "Connecting…"),
                    ChannelState::Joined => (egui::Color32::from_rgb(80, 200, 120), "Joined"),
                };
                ui.colored_label(color, format!("● {label}"));
            });

            if let Some(err) = &self.last_error {
                ui.colored_label(egui::Color32::from_rgb(220, 80, 80), err);
            }

            ui.separator();

            // Audio section
            ui.label("G2 microphone:");
            ui.horizontal(|ui| {
                let joined = self.state == ChannelState::Joined;
                if ui
                    .add_enabled(joined && !self.mic_on, egui::Button::new("▶ Start G2 mic"))
                    .clicked()
                {
                    self.start_g2_mic();
                }
                if ui
                    .add_enabled(joined && self.mic_on, egui::Button::new("⏹ Stop G2 mic"))
                    .clicked()
                {
                    self.stop_g2_mic();
                }
            });

            // VU meter — display the RMS on a dBFS scale (-60..0) instead of
            // raw linear, because the ear is logarithmic. "Normal speech"
            // sits around -20 dBFS so the bar lands at ~70% with this curve;
            // otherwise the same level barely registers as 6%.
            ui.label("Volume:");
            let vu_pct = vu_to_dbfs_norm(self.vu);
            let pb = egui::ProgressBar::new(vu_pct).show_percentage();
            ui.add(pb);
            ui.label(format!(
                "{}    bytes received: {}",
                vu_dbfs_label(self.vu),
                self.bytes_received
            ));

            ui.separator();

            // Recording section
            ui.label("Record to wav:");
            ui.horizontal(|ui| {
                if !self.recording {
                    if ui
                        .add_enabled(
                            self.state == ChannelState::Joined,
                            egui::Button::new("⏺ Start recording"),
                        )
                        .clicked()
                    {
                        self.start_recording();
                    }
                } else if ui.button("⏹ Stop recording").clicked() {
                    self.stop_recording();
                }
            });

            if self.recording {
                let secs = self.record_samples as f32 / SAMPLE_RATE as f32;
                ui.label(format!(
                    "● recording   {secs:.1}s   →   {}",
                    self.record_path
                        .as_ref()
                        .map(|p| p.display().to_string())
                        .unwrap_or_else(|| "?".into())
                ));
            } else if let Some(p) = &self.record_path {
                let secs = self.record_samples as f32 / SAMPLE_RATE as f32;
                ui.label(format!("last clip: {} ({:.1}s)", p.display(), secs));
            }
        });
    }
}

/// Compute RMS of an S16LE PCM byte slice, normalized to [0.0, 1.0].
fn compute_rms_s16le(bytes: &[u8]) -> f32 {
    if bytes.len() < 2 {
        return 0.0;
    }
    let mut sum_sq: f64 = 0.0;
    let mut n: usize = 0;
    for chunk in bytes.chunks_exact(2) {
        let s = i16::from_le_bytes([chunk[0], chunk[1]]) as f64 / i16::MAX as f64;
        sum_sq += s * s;
        n += 1;
    }
    if n == 0 {
        return 0.0;
    }
    (sum_sq / n as f64).sqrt() as f32
}

/// Map RMS [0.0, 1.0] → friendly dBFS label (-∞..0).
fn vu_dbfs_label(rms: f32) -> String {
    if rms <= 1e-6 {
        "–∞ dBFS".to_string()
    } else {
        format!("{:>6.1} dBFS", 20.0 * rms.log10())
    }
}

/// Map linear RMS [0.0, 1.0] → progress-bar fraction [0.0, 1.0] using a
/// -60..0 dBFS window. Below -60 dBFS reads as silence (0); 0 dBFS pegs
/// the meter (1.0). The ear is logarithmic, so this curve makes the bar
/// move proportionally to perceived loudness instead of cramming all
/// useful signal into the bottom 10%.
fn vu_to_dbfs_norm(rms: f32) -> f32 {
    const FLOOR_DBFS: f32 = -60.0;
    if rms <= 1e-6 {
        return 0.0;
    }
    let dbfs = 20.0 * rms.log10();
    ((dbfs - FLOOR_DBFS) / -FLOOR_DBFS).clamp(0.0, 1.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rms_zero_for_silence() {
        let silence = vec![0u8; 320];
        assert!(compute_rms_s16le(&silence) < 1e-6);
    }

    #[test]
    fn rms_full_scale_is_near_one() {
        // alternating ±32767 saturates RMS to 1.0
        let mut bytes = Vec::with_capacity(320);
        for i in 0..160 {
            let s: i16 = if i % 2 == 0 { i16::MAX } else { -i16::MAX };
            bytes.extend_from_slice(&s.to_le_bytes());
        }
        let r = compute_rms_s16le(&bytes);
        assert!((r - 1.0).abs() < 1e-3, "rms = {r}");
    }

    #[test]
    fn dbfs_norm_maps_speech_to_middle() {
        // -20 dBFS is roughly normal speech RMS; should sit ~67% on a
        // -60..0 window. (-20 - -60) / 60 = 0.667.
        let rms = 10f32.powf(-20.0 / 20.0); // = 0.1
        let norm = vu_to_dbfs_norm(rms);
        assert!((norm - 2.0 / 3.0).abs() < 1e-3, "norm = {norm}");
    }

    #[test]
    fn dbfs_norm_clamps_silence_to_zero() {
        assert_eq!(vu_to_dbfs_norm(0.0), 0.0);
    }

    #[test]
    fn dbfs_norm_clamps_full_scale_to_one() {
        assert!((vu_to_dbfs_norm(1.0) - 1.0).abs() < 1e-6);
    }
}
