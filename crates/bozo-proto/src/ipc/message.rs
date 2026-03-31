use crate::protocol::{audio_modes::AudioModeInfo, battery::BatteryInfo, cnc::CncState};
use serde::{Deserialize, Serialize};

/// Request from TUI client to daemon.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", content = "data")]
pub enum IpcRequest {
    /// Get the full current state.
    GetState,
    /// Set noise cancellation level and enabled state (legacy, may not work on all models).
    SetCnc { level: u8, enabled: bool },
    /// Set the active audio mode by index (QC Ultra: 0=Quiet, 1=Aware, etc.).
    SetAudioMode { mode_index: u8 },
    /// Set standby timer in minutes.
    SetStandbyTimer { minutes: u8 },
    /// Power off the headphones.
    PowerOff,
    /// Request the daemon to reconnect.
    Reconnect,
    /// Request the daemon to disconnect.
    Disconnect,
}

/// Response from daemon to TUI client.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", content = "data")]
pub enum IpcResponse {
    /// Full headphone state.
    State(HeadphoneState),
    /// Incremental state update (pushed to clients).
    StateUpdate(StateUpdate),
    /// Error message.
    Error { message: String },
    /// Acknowledgement.
    Ok,
}

/// Full headphone state snapshot.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct HeadphoneState {
    pub connected: bool,
    pub product_name: Option<String>,
    pub battery: Vec<BatteryInfo>,
    pub cnc: Option<CncState>,
    pub audio_mode_index: Option<u8>,
    pub audio_modes: Vec<AudioModeInfo>,
    pub standby_timer_minutes: Option<u8>,
}

/// Incremental state update.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "field")]
pub enum StateUpdate {
    Connection { connected: bool },
    Battery { info: Vec<BatteryInfo> },
    Cnc(CncState),
    AudioMode { mode_index: u8 },
    AudioModeDiscovered(AudioModeInfo),
    StandbyTimer { minutes: u8 },
    ProductName { name: String },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn serialize_get_state() {
        let req = IpcRequest::GetState;
        let json = serde_json::to_string(&req).unwrap();
        assert_eq!(json, r#"{"type":"GetState"}"#);
    }

    #[test]
    fn serialize_set_cnc() {
        let req = IpcRequest::SetCnc {
            level: 5,
            enabled: true,
        };
        let json = serde_json::to_string(&req).unwrap();
        assert!(json.contains("\"type\":\"SetCnc\""));
        assert!(json.contains("\"level\":5"));
    }

    #[test]
    fn roundtrip_state() {
        let state = HeadphoneState {
            connected: true,
            product_name: Some("Bose QC Ultra".into()),
            battery: vec![BatteryInfo {
                percentage: 85,
                remaining_minutes: Some(300),
                component_id: 0,
            }],
            cnc: Some(CncState {
                current_step: 5,
                total_steps: 10,
                enabled: true,
                user_enable_disable: true,
            }),
            audio_mode_index: Some(0),
            audio_modes: vec![],
            standby_timer_minutes: Some(20),
        };
        let resp = IpcResponse::State(state);
        let json = serde_json::to_string(&resp).unwrap();
        let parsed: IpcResponse = serde_json::from_str(&json).unwrap();
        match parsed {
            IpcResponse::State(s) => {
                assert!(s.connected);
                assert_eq!(s.battery[0].percentage, 85);
            }
            _ => panic!("expected State"),
        }
    }

    #[test]
    fn roundtrip_state_update() {
        let update = StateUpdate::Cnc(CncState {
            current_step: 3,
            total_steps: 10,
            enabled: true,
            user_enable_disable: true,
        });
        let resp = IpcResponse::StateUpdate(update);
        let json = serde_json::to_string(&resp).unwrap();
        let _: IpcResponse = serde_json::from_str(&json).unwrap();
    }
}
