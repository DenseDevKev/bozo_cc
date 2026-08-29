use num_enum::{IntoPrimitive, TryFromPrimitive};

/// BMAP Function Block ID (byte 0 of packet header).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, IntoPrimitive, TryFromPrimitive)]
#[repr(u8)]
pub enum FunctionBlock {
    ProductInfo = 0x00,
    Settings = 0x01,
    Status = 0x02,
    FirmwareUpdate = 0x03,
    DeviceManagement = 0x04,
    AudioManagement = 0x05,
    CallManagement = 0x06,
    Control = 0x07,
    Debug = 0x08,
    Notification = 0x09,
    ReservedBosebuild1 = 0x0A,
    ReservedBosebuild2 = 0x0B,
    HearingAssistance = 0x0C,
    DataCollection = 0x0D,
    HeartRate = 0x0E,
    PeerBud = 0x0F,
    Vpa = 0x10,
    Wifi = 0x11,
    Authentication = 0x12,
    Experimental = 0x13,
    Cloud = 0x14,
    AugmentedReality = 0x15,
    Print = 0x16,
    AudioModes = 0x1F,
}

/// BMAP Operator (low 4 bits of byte 2).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, IntoPrimitive, TryFromPrimitive)]
#[repr(u8)]
pub enum Operator {
    Set = 0,
    Get = 1,
    SetGet = 2,
    Status = 3,
    Error = 4,
    Start = 5,
    Result = 6,
    Processing = 7,
}

impl Operator {
    pub fn is_command(self) -> bool {
        matches!(self, Self::Set | Self::Get | Self::SetGet | Self::Start)
    }

    pub fn is_response(self) -> bool {
        matches!(self, Self::Status | Self::Error | Self::Result | Self::Processing)
    }
}

/// Settings function IDs (FBlock = 0x01).
pub mod settings {
    pub const PRODUCT_NAME: u8 = 0x02;
    pub const VOICE_PROMPTS: u8 = 0x03;
    pub const STANDBY_TIMER: u8 = 0x04;
    pub const CNC: u8 = 0x05;
    pub const ANR: u8 = 0x06;
    pub const BUTTONS: u8 = 0x09;
    pub const MULTIPOINT: u8 = 0x0A;
    pub const CNC_PRESETS: u8 = 0x0F;
    pub const ON_HEAD_DETECTION: u8 = 0x10;
    pub const AUTO_AWARE_MODE: u8 = 0x1D;
}

/// Status function IDs (FBlock = 0x02).
pub mod status {
    pub const BATTERY_LEVEL: u8 = 0x02;
    pub const AUX_CABLE: u8 = 0x03;
    pub const CHARGER_DETECT: u8 = 0x05;
    pub const IN_EAR: u8 = 0x09;
    pub const BUTTON: u8 = 0x0C;
}

/// Control function IDs (FBlock = 0x07).
pub mod control {
    pub const POWER: u8 = 0x04;
    pub const FACTORY_DEFAULT: u8 = 0x05;
    pub const SHIP_MODE: u8 = 0x06;
    pub const ANR_ONLY: u8 = 0x07;
    pub const RESET: u8 = 0x0B;
}

/// AudioModes function IDs (FBlock = 0x1F).
pub mod audio_modes {
    pub const FBLOCK_INFO: u8 = 0x00;
    pub const GET_ALL: u8 = 0x01;
    pub const CAPABILITIES: u8 = 0x02;
    pub const CURRENT_MODE: u8 = 0x03;
    pub const DEFAULT_MODE: u8 = 0x04;
    pub const MODE_CONFIG: u8 = 0x06;
    pub const SETTINGS_CONFIG: u8 = 0x0A;
}

/// Product Info function IDs (FBlock = 0x00).
pub mod product_info {
    pub const BMAP_VERSION: u8 = 0x01;
    pub const PRODUCT_ID_VARIANT: u8 = 0x05;
    pub const FIRMWARE_VERSION: u8 = 0x04;
    pub const SERIAL_NUMBER: u8 = 0x07;
}
