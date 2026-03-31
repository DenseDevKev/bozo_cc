use crate::bmap::{
    enums::{control, FunctionBlock, Operator},
    packet::BmapPacket,
};

/// Build a power off command.
pub fn power_off() -> BmapPacket {
    BmapPacket::new(
        FunctionBlock::Control,
        control::POWER,
        Operator::Start,
        vec![0x00],
    )
}

/// Build a power on command.
pub fn power_on() -> BmapPacket {
    BmapPacket::new(
        FunctionBlock::Control,
        control::POWER,
        Operator::Start,
        vec![0x01],
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn power_off_packet() {
        assert_eq!(
            power_off().to_bytes(),
            vec![0x07, 0x04, 0x05, 0x01, 0x00]
        );
    }

    #[test]
    fn power_on_packet() {
        assert_eq!(
            power_on().to_bytes(),
            vec![0x07, 0x04, 0x05, 0x01, 0x01]
        );
    }
}
