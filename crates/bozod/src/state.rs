use bozo_proto::bmap::enums::{self, FunctionBlock, Operator};
use bozo_proto::bmap::packet::BmapPacket;
use bozo_proto::ipc::message::{HeadphoneState, StateUpdate};
use bozo_proto::protocol::{audio_modes, battery, cnc, name, standby};
use std::sync::Arc;
use tokio::sync::{broadcast, RwLock};
use tracing::{debug, info, warn};

use crate::event::DaemonEvent;

/// Manages cached headphone state, updating it from received BMAP packets.
pub struct StateManager {
    pub state: Arc<RwLock<HeadphoneState>>,
    event_tx: broadcast::Sender<DaemonEvent>,
}

impl StateManager {
    pub fn new(event_tx: broadcast::Sender<DaemonEvent>) -> Self {
        Self {
            state: Arc::new(RwLock::new(HeadphoneState::default())),
            event_tx,
        }
    }

    /// Returns the list of initial query packets to send on connect.
    pub fn initial_queries() -> Vec<BmapPacket> {
        let mut queries = vec![
            name::query(),
            battery::query(),
            cnc::query(),
            audio_modes::query_current_mode(),
            standby::query(),
        ];
        // Query mode configs for indices 0..10 to discover available modes.
        // The device will return Error for non-existent indices, which we ignore.
        for i in 0..10 {
            queries.push(audio_modes::query_mode_config(i));
        }
        queries
    }

    /// Process a received BMAP packet, update cached state, and broadcast the change.
    pub async fn process_packet(&self, packet: &BmapPacket) {
        if let Some(update) = self.parse_and_update(packet).await {
            match self.event_tx.send(DaemonEvent::StateUpdated(update)) {
                Ok(n) => debug!("broadcast StateUpdated to {n} receivers"),
                Err(e) => warn!("broadcast StateUpdated failed (no receivers): {e}"),
            }
        }
    }

    async fn parse_and_update(&self, packet: &BmapPacket) -> Option<StateUpdate> {
        // Only process Status/Result responses, not Error/Processing
        if !packet.operator.is_response() || packet.operator == Operator::Error {
            if packet.operator == Operator::Error {
                warn!(
                    "device error: fblock={:?} func=0x{:02x} error_code={:?}",
                    packet.function_block,
                    packet.function,
                    packet.payload.first()
                );
            }
            return None;
        }

        match (packet.function_block, packet.function) {
            (FunctionBlock::Status, enums::status::BATTERY_LEVEL) => {
                match battery::parse_response(packet) {
                    Ok(info) => {
                        debug!("battery update: {:?}", info);
                        let mut state = self.state.write().await;
                        state.battery = info.clone();
                        Some(StateUpdate::Battery { info })
                    }
                    Err(e) => {
                        warn!("failed to parse battery response: {}", e);
                        None
                    }
                }
            }
            (FunctionBlock::Settings, enums::settings::CNC) => {
                match cnc::parse_response(packet) {
                    Ok(cnc_state) => {
                        debug!("CNC update: {:?}", cnc_state);
                        let mut state = self.state.write().await;
                        state.cnc = Some(cnc_state.clone());
                        Some(StateUpdate::Cnc(cnc_state))
                    }
                    Err(e) => {
                        warn!("failed to parse CNC response: {}", e);
                        None
                    }
                }
            }
            (FunctionBlock::Settings, enums::settings::PRODUCT_NAME) => {
                match name::parse_response(packet) {
                    Ok(product_name) => {
                        info!("product name: {}", product_name);
                        let mut state = self.state.write().await;
                        state.product_name = Some(product_name.clone());
                        Some(StateUpdate::ProductName { name: product_name })
                    }
                    Err(e) => {
                        warn!("failed to parse product name response: {}", e);
                        None
                    }
                }
            }
            (FunctionBlock::Settings, enums::settings::STANDBY_TIMER) => {
                match standby::parse_response(packet) {
                    Ok(minutes) => {
                        debug!("standby timer: {} min", minutes);
                        let mut state = self.state.write().await;
                        state.standby_timer_minutes = Some(minutes);
                        Some(StateUpdate::StandbyTimer { minutes })
                    }
                    Err(e) => {
                        warn!("failed to parse standby timer response: {}", e);
                        None
                    }
                }
            }
            (FunctionBlock::AudioModes, enums::audio_modes::CURRENT_MODE) => {
                match audio_modes::parse_current_mode(packet) {
                    Some(mode_index) => {
                        debug!("audio mode: {}", mode_index);
                        let mut state = self.state.write().await;
                        state.audio_mode_index = Some(mode_index);
                        Some(StateUpdate::AudioMode { mode_index })
                    }
                    None => {
                        warn!("failed to parse audio mode response");
                        None
                    }
                }
            }
            (FunctionBlock::AudioModes, enums::audio_modes::MODE_CONFIG) => {
                match audio_modes::parse_mode_config(packet) {
                    Some(info) => {
                        debug!("discovered mode {}: {:?}", info.mode_index, info.name);
                        let mut state = self.state.write().await;
                        // Replace or insert, keeping sorted by index
                        if let Some(existing) = state
                            .audio_modes
                            .iter_mut()
                            .find(|m| m.mode_index == info.mode_index)
                        {
                            *existing = info.clone();
                        } else {
                            state.audio_modes.push(info.clone());
                            state.audio_modes.sort_by_key(|m| m.mode_index);
                        }
                        Some(StateUpdate::AudioModeDiscovered(info))
                    }
                    None => None,
                }
            }
            _ => {
                debug!(
                    "unhandled response: fblock={:?} func=0x{:02x} op={:?} payload={:02x?}",
                    packet.function_block, packet.function, packet.operator, packet.payload
                );
                None
            }
        }
    }
}
