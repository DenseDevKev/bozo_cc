use crate::bmap::{
    enums::{audio_modes, FunctionBlock, Operator},
    packet::BmapPacket,
};
use serde::{Deserialize, Serialize};

/// Info about a single audio mode discovered from the device.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AudioModeInfo {
    pub mode_index: u8,
    pub name: String,
}

/// Build a GET current audio mode request.
pub fn query_current_mode() -> BmapPacket {
    BmapPacket::new(
        FunctionBlock::AudioModes,
        audio_modes::CURRENT_MODE,
        Operator::Get,
        vec![],
    )
}

/// Build a GET mode config request for a specific mode index.
pub fn query_mode_config(mode_index: u8) -> BmapPacket {
    BmapPacket::new(
        FunctionBlock::AudioModes,
        audio_modes::MODE_CONFIG,
        Operator::Get,
        vec![mode_index],
    )
}

/// Build a START (set) current audio mode request.
pub fn set_current_mode(mode_index: u8) -> BmapPacket {
    BmapPacket::new(
        FunctionBlock::AudioModes,
        audio_modes::CURRENT_MODE,
        Operator::Start,
        vec![mode_index, 0x00], // 0x00 = don't play voice prompt
    )
}

/// Parse a CurrentMode response. Returns the mode index.
pub fn parse_current_mode(packet: &BmapPacket) -> Option<u8> {
    if packet.function_block != FunctionBlock::AudioModes
        || packet.function != audio_modes::CURRENT_MODE
    {
        return None;
    }
    packet.payload.first().copied()
}

/// Parse a ModeConfig response. Returns mode index and name.
///
/// Payload layout (48 bytes):
///   byte 0:     mode_index
///   bytes 1-2:  prompt id (byte1, byte2)
///   bytes 3-5:  flags (userConfigurable, userConfigured, favorite)
///   bytes 6-37: mode name (null-terminated UTF-8, 32 bytes)
///   bytes 38+:  cnc/spatial config
pub fn parse_mode_config(packet: &BmapPacket) -> Option<AudioModeInfo> {
    if packet.function_block != FunctionBlock::AudioModes
        || packet.function != audio_modes::MODE_CONFIG
    {
        return None;
    }
    let payload = &packet.payload;
    if payload.len() < 7 {
        return None;
    }

    let mode_index = payload[0];

    // Name is at bytes 6..38, null-terminated
    let name_end = payload.len().min(38);
    let name_bytes = &payload[6..name_end];
    let null_pos = name_bytes.iter().position(|&b| b == 0).unwrap_or(name_bytes.len());
    let name = String::from_utf8_lossy(&name_bytes[..null_pos]).to_string();

    Some(AudioModeInfo { mode_index, name })
}
