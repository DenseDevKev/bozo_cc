use crate::bmap::{
    enums::{status, FunctionBlock, Operator},
    packet::{BmapPacket, PacketError},
};
use serde::{Deserialize, Serialize};

/// Battery info for a single component (headset, case, etc.).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct BatteryInfo {
    /// Battery percentage (0-100).
    pub percentage: u8,
    /// Remaining play time in minutes, if known.
    pub remaining_minutes: Option<u16>,
    /// Component identifier (0 = primary, others = case/buds).
    pub component_id: u8,
}

/// Build a GET battery level request.
pub fn query() -> BmapPacket {
    BmapPacket::new(FunctionBlock::Status, status::BATTERY_LEVEL, Operator::Get, vec![])
}

/// Parse a battery level response payload into a list of battery readings.
///
/// Payload format: repeating 4-byte chunks [percentage, remaining_hi, remaining_lo, component_id].
/// If payload is 1-3 bytes, treat as a single reading with available fields.
pub fn parse_response(packet: &BmapPacket) -> Result<Vec<BatteryInfo>, PacketError> {
    if packet.function_block != FunctionBlock::Status || packet.function != status::BATTERY_LEVEL {
        return Err(PacketError::InvalidFunctionBlock(packet.function_block.into()));
    }

    let payload = &packet.payload;
    if payload.is_empty() {
        return Ok(vec![]);
    }

    let mut results = Vec::new();

    if payload.len() < 4 {
        // Short response: just percentage
        results.push(BatteryInfo {
            percentage: payload[0],
            remaining_minutes: None,
            component_id: payload.get(3).copied().unwrap_or(0),
        });
    } else {
        let mut offset = 0;
        while offset + 4 <= payload.len() {
            let percentage = payload[offset];
            let remaining_raw =
                ((payload[offset + 1] as u16) << 8) | (payload[offset + 2] as u16);
            let remaining_minutes = if remaining_raw == 0xFFFF {
                None
            } else {
                Some(remaining_raw)
            };
            let component_id = payload[offset + 3];

            results.push(BatteryInfo {
                percentage,
                remaining_minutes,
                component_id,
            });
            offset += 4;
        }
    }

    Ok(results)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn query_packet() {
        let pkt = query();
        assert_eq!(pkt.to_bytes(), vec![0x02, 0x02, 0x01, 0x00]);
    }

    #[test]
    fn parse_single_battery() {
        let pkt = BmapPacket::new(
            FunctionBlock::Status,
            status::BATTERY_LEVEL,
            Operator::Status,
            vec![85, 0x01, 0x2C, 0x00], // 85%, 300 min, component 0
        );
        let info = parse_response(&pkt).unwrap();
        assert_eq!(info.len(), 1);
        assert_eq!(info[0].percentage, 85);
        assert_eq!(info[0].remaining_minutes, Some(300));
        assert_eq!(info[0].component_id, 0);
    }

    #[test]
    fn parse_two_batteries() {
        let pkt = BmapPacket::new(
            FunctionBlock::Status,
            status::BATTERY_LEVEL,
            Operator::Status,
            vec![
                85, 0x01, 0x2C, 0x00, // 85%, 300 min, component 0
                50, 0xFF, 0xFF, 0x01, // 50%, unknown remaining, component 1
            ],
        );
        let info = parse_response(&pkt).unwrap();
        assert_eq!(info.len(), 2);
        assert_eq!(info[0].percentage, 85);
        assert_eq!(info[1].percentage, 50);
        assert_eq!(info[1].remaining_minutes, None);
        assert_eq!(info[1].component_id, 1);
    }
}
