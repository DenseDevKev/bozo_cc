use crate::bmap::{
    enums::{settings, FunctionBlock, Operator},
    packet::{BmapPacket, PacketError},
};

/// Build a GET standby timer request.
pub fn query() -> BmapPacket {
    BmapPacket::new(
        FunctionBlock::Settings,
        settings::STANDBY_TIMER,
        Operator::Get,
        vec![],
    )
}

/// Build a SET standby timer request.
pub fn set(minutes: u8) -> BmapPacket {
    BmapPacket::new(
        FunctionBlock::Settings,
        settings::STANDBY_TIMER,
        Operator::SetGet,
        vec![minutes],
    )
}

/// Parse a standby timer response. Returns the timeout in minutes.
pub fn parse_response(packet: &BmapPacket) -> Result<u8, PacketError> {
    if packet.function_block != FunctionBlock::Settings
        || packet.function != settings::STANDBY_TIMER
    {
        return Err(PacketError::InvalidFunctionBlock(packet.function_block.into()));
    }

    packet
        .payload
        .first()
        .copied()
        .ok_or(PacketError::PayloadLengthMismatch {
            expected: 1,
            actual: 0,
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn query_packet() {
        assert_eq!(query().to_bytes(), vec![0x01, 0x04, 0x01, 0x00]);
    }

    #[test]
    fn set_20_minutes() {
        assert_eq!(set(20).to_bytes(), vec![0x01, 0x04, 0x02, 0x01, 0x14]);
    }

    #[test]
    fn parse_standby() {
        let pkt = BmapPacket::new(
            FunctionBlock::Settings,
            settings::STANDBY_TIMER,
            Operator::Status,
            vec![60],
        );
        assert_eq!(parse_response(&pkt).unwrap(), 60);
    }
}
