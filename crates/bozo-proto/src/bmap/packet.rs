use super::enums::{FunctionBlock, Operator};
use thiserror::Error;

/// Header size in bytes.
const HEADER_SIZE: usize = 4;

#[derive(Debug, Error)]
pub enum PacketError {
    #[error("packet too short: need at least {HEADER_SIZE} bytes, got {0}")]
    TooShort(usize),
    #[error("invalid function block: 0x{0:02x}")]
    InvalidFunctionBlock(u8),
    #[error("invalid operator: 0x{0:02x}")]
    InvalidOperator(u8),
    #[error("payload length mismatch: header says {expected}, but {actual} bytes available")]
    PayloadLengthMismatch { expected: usize, actual: usize },
}

/// A single BMAP packet.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BmapPacket {
    pub function_block: FunctionBlock,
    pub function: u8,
    pub device_id: u8,
    pub port: u8,
    pub operator: Operator,
    pub payload: Vec<u8>,
}

impl BmapPacket {
    pub fn new(
        function_block: FunctionBlock,
        function: u8,
        operator: Operator,
        payload: Vec<u8>,
    ) -> Self {
        Self {
            function_block,
            function,
            device_id: 0,
            port: 0,
            operator,
            payload,
        }
    }

    /// Serialize to wire format.
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut buf = Vec::with_capacity(HEADER_SIZE + self.payload.len());
        buf.push(self.function_block.into());
        buf.push(self.function);
        buf.push(
            (self.device_id << 6) | (self.port << 4) | (u8::from(self.operator) & 0x0F),
        );
        buf.push(self.payload.len() as u8);
        buf.extend_from_slice(&self.payload);
        buf
    }

    /// Parse a single packet from a byte slice.
    pub fn from_bytes(data: &[u8]) -> Result<Self, PacketError> {
        if data.len() < HEADER_SIZE {
            return Err(PacketError::TooShort(data.len()));
        }

        let function_block = FunctionBlock::try_from(data[0])
            .map_err(|_| PacketError::InvalidFunctionBlock(data[0]))?;
        let function = data[1];
        let byte2 = data[2];
        let device_id = byte2 >> 6;
        let port = (byte2 >> 4) & 0x03;
        let operator = Operator::try_from(byte2 & 0x0F)
            .map_err(|_| PacketError::InvalidOperator(byte2 & 0x0F))?;
        let payload_len = (data[3] & 0xFF) as usize;

        let available = data.len() - HEADER_SIZE;
        if available < payload_len {
            return Err(PacketError::PayloadLengthMismatch {
                expected: payload_len,
                actual: available,
            });
        }

        let payload = data[HEADER_SIZE..HEADER_SIZE + payload_len].to_vec();

        Ok(Self {
            function_block,
            function,
            device_id,
            port,
            operator,
            payload,
        })
    }

    /// Parse multiple concatenated packets from a buffer (as seen in SPP reads).
    pub fn parse_many(data: &[u8]) -> Vec<Result<Self, PacketError>> {
        let mut results = Vec::new();
        let mut offset = 0;

        while offset < data.len() {
            if offset + HEADER_SIZE > data.len() {
                results.push(Err(PacketError::TooShort(data.len() - offset)));
                break;
            }

            let payload_len = data[offset + 3] as usize;
            let packet_len = HEADER_SIZE + payload_len;

            if offset + packet_len > data.len() {
                results.push(Err(PacketError::PayloadLengthMismatch {
                    expected: payload_len,
                    actual: data.len() - offset - HEADER_SIZE,
                }));
                break;
            }

            results.push(Self::from_bytes(&data[offset..offset + packet_len]));
            offset += packet_len;
        }

        results
    }

    /// Total wire size of this packet.
    pub fn wire_len(&self) -> usize {
        HEADER_SIZE + self.payload.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::bmap::enums::{settings, status, control};

    #[test]
    fn serialize_get_battery() {
        let pkt = BmapPacket::new(
            FunctionBlock::Status,
            status::BATTERY_LEVEL,
            Operator::Get,
            vec![],
        );
        assert_eq!(pkt.to_bytes(), vec![0x02, 0x02, 0x01, 0x00]);
    }

    #[test]
    fn serialize_set_cnc() {
        let pkt = BmapPacket::new(
            FunctionBlock::Settings,
            settings::CNC,
            Operator::SetGet,
            vec![5, 1], // level=5, enabled=true
        );
        assert_eq!(pkt.to_bytes(), vec![0x01, 0x05, 0x02, 0x02, 0x05, 0x01]);
    }

    #[test]
    fn serialize_power_off() {
        let pkt = BmapPacket::new(
            FunctionBlock::Control,
            control::POWER,
            Operator::Start,
            vec![0x00],
        );
        assert_eq!(pkt.to_bytes(), vec![0x07, 0x04, 0x05, 0x01, 0x00]);
    }

    #[test]
    fn roundtrip() {
        let original = BmapPacket::new(
            FunctionBlock::Settings,
            settings::CNC,
            Operator::SetGet,
            vec![5, 1],
        );
        let bytes = original.to_bytes();
        let parsed = BmapPacket::from_bytes(&bytes).unwrap();
        assert_eq!(original, parsed);
    }

    #[test]
    fn roundtrip_with_device_id_and_port() {
        let original = BmapPacket {
            function_block: FunctionBlock::Status,
            function: status::BATTERY_LEVEL,
            device_id: 2,
            port: 1,
            operator: Operator::Status,
            payload: vec![85, 0x01, 0x2C, 0x00], // 85%, 300min, component 0
        };
        let bytes = original.to_bytes();
        // byte 2: (2 << 6) | (1 << 4) | 3 = 0x80 | 0x10 | 0x03 = 0x93
        assert_eq!(bytes[2], 0x93);
        let parsed = BmapPacket::from_bytes(&bytes).unwrap();
        assert_eq!(original, parsed);
    }

    #[test]
    fn parse_too_short() {
        assert!(BmapPacket::from_bytes(&[0x01, 0x02]).is_err());
    }

    #[test]
    fn parse_payload_mismatch() {
        // Header says 5 bytes payload but only 2 available
        assert!(BmapPacket::from_bytes(&[0x01, 0x05, 0x02, 0x05, 0xAA, 0xBB]).is_err());
    }

    #[test]
    fn parse_many_concatenated() {
        // Two packets: GET battery + GET CNC
        let mut data = vec![0x02, 0x02, 0x01, 0x00]; // GET battery
        data.extend_from_slice(&[0x01, 0x05, 0x01, 0x00]); // GET CNC

        let results = BmapPacket::parse_many(&data);
        assert_eq!(results.len(), 2);
        let pkt1 = results[0].as_ref().unwrap();
        assert_eq!(pkt1.function_block, FunctionBlock::Status);
        assert_eq!(pkt1.function, status::BATTERY_LEVEL);
        let pkt2 = results[1].as_ref().unwrap();
        assert_eq!(pkt2.function_block, FunctionBlock::Settings);
        assert_eq!(pkt2.function, settings::CNC);
    }

    #[test]
    fn parse_many_with_payload() {
        // CNC status response: [currentStep=5, numSteps=10, flags=0x01]
        let data = vec![0x01, 0x05, 0x03, 0x03, 0x05, 0x0A, 0x01];
        let results = BmapPacket::parse_many(&data);
        assert_eq!(results.len(), 1);
        let pkt = results[0].as_ref().unwrap();
        assert_eq!(pkt.operator, Operator::Status);
        assert_eq!(pkt.payload, vec![0x05, 0x0A, 0x01]);
    }
}
