use bozo_proto::ipc::message::{HeadphoneState, IpcRequest, IpcResponse, StateUpdate};
use tokio::sync::mpsc;

use crate::client::IpcClient;

/// Which UI element is focused for interaction.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Focus {
    AudioMode,
    StandbyTimer,
}

impl Focus {
    pub fn next(self) -> Self {
        match self {
            Focus::AudioMode => Focus::StandbyTimer,
            Focus::StandbyTimer => Focus::AudioMode,
        }
    }
}

/// Confirmation dialog state.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Confirm {
    PowerOff,
}

pub struct App {
    pub state: HeadphoneState,
    pub focus: Focus,
    pub confirm: Option<Confirm>,
    pub status_msg: Option<String>,
    pub update_count: usize,
    pub should_quit: bool,
    pub client: IpcClient,
    pub ipc_rx: mpsc::UnboundedReceiver<IpcResponse>,
}

impl App {
    pub fn new(client: IpcClient, ipc_rx: mpsc::UnboundedReceiver<IpcResponse>) -> Self {
        Self {
            state: HeadphoneState::default(),
            focus: Focus::AudioMode,
            confirm: None,
            status_msg: None,
            update_count: 0,
            should_quit: false,
            client,
            ipc_rx,
        }
    }

    /// Drain all pending IPC responses and apply to state.
    pub fn poll_ipc(&mut self) {
        while let Ok(resp) = self.ipc_rx.try_recv() {
            self.update_count += 1;
            match resp {
                IpcResponse::State(s) => {
                    self.status_msg = Some(format!("state loaded ({})", self.update_count));
                    self.state = s;
                }
                IpcResponse::StateUpdate(update) => {
                    self.status_msg = Some(format!("update: {:?} ({})", update, self.update_count));
                    self.apply_update(update);
                }
                IpcResponse::Error { message } => {
                    self.status_msg = Some(format!("error: {message}"));
                }
                IpcResponse::Ok => {
                    self.status_msg = Some(format!("ok ({})", self.update_count));
                }
            }
        }
    }

    fn apply_update(&mut self, update: StateUpdate) {
        match update {
            StateUpdate::Connection { connected } => self.state.connected = connected,
            StateUpdate::Battery { info } => self.state.battery = info,
            StateUpdate::Cnc(cnc) => self.state.cnc = Some(cnc),
            StateUpdate::AudioMode { mode_index } => {
                self.state.audio_mode_index = Some(mode_index)
            }
            StateUpdate::AudioModeDiscovered(info) => {
                if let Some(existing) = self
                    .state
                    .audio_modes
                    .iter_mut()
                    .find(|m| m.mode_index == info.mode_index)
                {
                    *existing = info;
                } else {
                    self.state.audio_modes.push(info);
                    self.state.audio_modes.sort_by_key(|m| m.mode_index);
                }
            }
            StateUpdate::StandbyTimer { minutes } => {
                self.state.standby_timer_minutes = Some(minutes)
            }
            StateUpdate::ProductName { name } => self.state.product_name = Some(name),
        }
    }

    pub async fn audio_mode_adjust(&mut self, delta: i8) {
        let modes = &self.state.audio_modes;
        let current = match self.state.audio_mode_index {
            Some(idx) => idx,
            None => return,
        };

        if modes.is_empty() {
            // No discovered modes, just adjust raw index
            let new_mode = (current as i8 + delta).max(0) as u8;
            if new_mode != current {
                let _ = self
                    .client
                    .send(&IpcRequest::SetAudioMode {
                        mode_index: new_mode,
                    })
                    .await;
            }
            return;
        }

        // Find current position in discovered modes and cycle
        let pos = modes
            .iter()
            .position(|m| m.mode_index == current)
            .unwrap_or(0);
        let new_pos = if delta > 0 {
            (pos + 1) % modes.len()
        } else {
            (pos + modes.len() - 1) % modes.len()
        };
        let new_mode = modes[new_pos].mode_index;
        if new_mode != current {
            let _ = self
                .client
                .send(&IpcRequest::SetAudioMode {
                    mode_index: new_mode,
                })
                .await;
        }
    }

    pub async fn standby_cycle(&mut self) {
        const OPTIONS: &[u8] = &[0, 5, 10, 20, 30, 60, 120];
        let current = self.state.standby_timer_minutes.unwrap_or(0);
        let next = OPTIONS
            .iter()
            .find(|&&m| m > current)
            .copied()
            .unwrap_or(OPTIONS[0]);
        let _ = self
            .client
            .send(&IpcRequest::SetStandbyTimer { minutes: next })
            .await;
    }

    pub async fn power_off(&mut self) {
        let _ = self.client.send(&IpcRequest::PowerOff).await;
        self.status_msg = Some("Power off sent".into());
    }

    pub async fn reconnect(&mut self) {
        let _ = self.client.send(&IpcRequest::Reconnect).await;
        self.status_msg = Some("Reconnecting...".into());
    }
}
