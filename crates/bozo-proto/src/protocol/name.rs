use crate::bmap::{
    enums::{settings, FunctionBlock, Operator},
    packet::{BmapPacket, PacketError},
};

/// Build a GET product name request.
pub fn query() -> BmapPacket {
    BmapPacket::new(
        FunctionBlock::Settings,
        settings::PRODUCT_NAME,
        Operator::Get,
        vec![],
    )
}

/// Parse a product name response. The payload is a UTF-8 string.
pub fn parse_response(packet: &BmapPacket) -> Result<String, PacketError> {
    if packet.function_block != FunctionBlock::Settings
        || packet.function != settings::PRODUCT_NAME
    {
        return Err(PacketError::InvalidFunctionBlock(packet.function_block.into()));
    }

    // Payload may have a leading null byte or trailing null bytes
    let payload = &packet.payload;
    let trimmed: Vec<u8> = payload.iter().copied().filter(|&b| b != 0).collect();
    Ok(String::from_utf8_lossy(&trimmed).into_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn query_packet() {
        assert_eq!(query().to_bytes(), vec![0x01, 0x02, 0x01, 0x00]);
    }

    #[test]
    fn parse_name() {
        let mut payload = vec![0x00]; // leading null
        payload.extend_from_slice(b"Bose QC Ultra");
        let pkt = BmapPacket::new(
            FunctionBlock::Settings,
            settings::PRODUCT_NAME,
            Operator::Status,
            payload,
        );
        assert_eq!(parse_response(&pkt).unwrap(), "Bose QC Ultra");
    }
}
