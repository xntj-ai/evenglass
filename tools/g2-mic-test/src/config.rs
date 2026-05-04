//! Persisted UI inputs (server URL / device_id / PC admin cookie).
//!
//! Saved to `%LOCALAPPDATA%\g2-mic-test\config.json` on Windows (or the
//! XDG equivalent elsewhere). The cookie value is a session token that
//! grants admin access to the production deployment, so we keep the
//! file inside the user's local profile and skip cross-machine sync —
//! same threat model as a browser cookie jar.

use std::path::PathBuf;

use anyhow::{anyhow, Context, Result};
use serde::{Deserialize, Serialize};

const DEFAULT_WSS: &str = "wss://g2.xntj.tv/socket";
const DEFAULT_API: &str = "https://g2.xntj.tv";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PersistedConfig {
    #[serde(default = "default_wss")]
    pub wss_url: String,
    #[serde(default = "default_api")]
    pub api_url: String,
    #[serde(default)]
    pub device_id: String,
    #[serde(default)]
    pub cookie: String,
}

impl Default for PersistedConfig {
    fn default() -> Self {
        Self {
            wss_url: default_wss(),
            api_url: default_api(),
            device_id: String::new(),
            cookie: String::new(),
        }
    }
}

fn default_wss() -> String {
    DEFAULT_WSS.to_string()
}

fn default_api() -> String {
    DEFAULT_API.to_string()
}

impl PersistedConfig {
    pub fn load() -> Self {
        match read_from_disk() {
            Ok(cfg) => cfg,
            Err(e) => {
                tracing::debug!("config load failed (using defaults): {e:#}");
                Self::default()
            }
        }
    }

    pub fn save(&self) -> Result<()> {
        let path = config_path()?;
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir).context("create config dir")?;
        }
        let json = serde_json::to_string_pretty(self).context("serialize config")?;
        std::fs::write(&path, json).with_context(|| format!("write {}", path.display()))?;
        Ok(())
    }
}

fn read_from_disk() -> Result<PersistedConfig> {
    let path = config_path()?;
    let text = std::fs::read_to_string(&path)
        .with_context(|| format!("read {}", path.display()))?;
    let cfg: PersistedConfig = serde_json::from_str(&text).context("parse config json")?;
    Ok(cfg)
}

fn config_path() -> Result<PathBuf> {
    let dir = dirs::data_local_dir()
        .ok_or_else(|| anyhow!("could not locate platform local data dir"))?
        .join("g2-mic-test");
    Ok(dir.join("config.json"))
}
