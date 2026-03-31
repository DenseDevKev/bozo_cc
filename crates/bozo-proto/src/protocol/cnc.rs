use crate::bmap::{
    enums::{settings, FunctionBlock, Operator},
    packet::{BmapPacket, PacketError},
};
use serde::{Deserialize, Serialize};

/// Noise cancellation state.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CncState {
    /// Current step (0 to total_steps).
    pub current_step: u8,
    /// Total number of steps available.
    pub total_steps: u8,
    /// Whether CNC is enabled.
    pub enabled: bool,
    /// Whether user can toggle enable/disable.
    pub user_enable_disable: bool,
}

/// Build a GET CNC request.
pub fn query() -> BmapPacket {
    BmapPacket::new(FunctionBlock::Settings, settings::CNC, Operator::Get, vec![])
}

/// Build a SET CNC request.
pub fn set(level: u8, enabled: bool) -> BmapPacket {
    BmapPacket::new(
        FunctionBlock::Settings,
        settings::CNC,
        Operator::SetGet,
        vec![level, if enabled { 1 } else { 0 }],
    )
}

/// Parse a CNC status response.
///
/// Payload: [currentStep, numSteps, flags]
/// flags bit 0: enabled, flags bit 1: userEnableDisable (inverted in APK)
pub fn parse_response(packet: &BmapPacket) -> Result<CncState, PacketError> {
    if packet.function_block != FunctionBlock::Settings || packet.function != settings::CNC {
        return Err(PacketError::InvalidFunctionBlock(packet.function_block.into()));
    }

    let payload = &packet.payload;
    if payload.len() < 3 {
        return Err(PacketError::PayloadLengthMismatch {
            expected: 3,
            actual: payload.len(),
        });
    }

    let current_step = payload[0];
    let total_steps = payload[1];
    let flags = payload[2];
    let enabled = (flags & 1) == 1;
    let user_enable_disable = ((flags >> 1) & 1) == 0; // inverted per APK

    Ok(CncState {
        current_step,
        total_steps,
        enabled,
        user_enable_disable,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn query_packet() {
        let pkt = query();
        assert_eq!(pkt.to_bytes(), vec![0x01, 0x05, 0x01, 0x00]);
    }

    #[test]
    fn set_packet() {
        let pkt = set(5, true);
        assert_eq!(pkt.to_bytes(), vec![0x01, 0x05, 0x02, 0x02, 0x05, 0x01]);
    }

    #[test]
    fn set_disabled() {
        let pkt = set(0, false);
        assert_eq!(pkt.to_bytes(), vec![0x01, 0x05, 0x02, 0x02, 0x00, 0x00]);
    }

    #[test]
    fn parse_cnc_response() {
        let pkt = BmapPacket::new(
            FunctionBlock::Settings,
            settings::CNC,
            Operator::Status,
            vec![5, 10, 0x01], // step=5, total=10, enabled=true, userEnableDisable=true (bit1=0)
        );
        let state = parse_response(&pkt).unwrap();
        assert_eq!(state.current_step, 5);
        assert_eq!(state.total_steps, 10);
        assert!(state.enabled);
        assert!(state.user_enable_disable);
    }

    #[test]
    fn parse_cnc_disabled() {
        let pkt = BmapPacket::new(
            FunctionBlock::Settings,
            settings::CNC,
            Operator::Status,
            vec![0, 10, 0x02], // step=0, total=10, enabled=false, userEnableDisable=false
        );
        let state = parse_response(&pkt).unwrap();
        assert_eq!(state.current_step, 0);
        assert!(!state.enabled);
        assert!(!state.user_enable_disable);
    }
}
