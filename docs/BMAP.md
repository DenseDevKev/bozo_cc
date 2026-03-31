# BMAP Protocol Reference

BMAP (Bose Message Access Protocol) is a proprietary protocol used by Bose
headphones and speakers for device control over Bluetooth. This document
covers the BLE transport and the message formats relevant to headphone
control, reverse-engineered from the Bose Music Android app v12.1.6.

## BLE transport

### Service and characteristics

| UUID | Purpose |
|------|---------|
| `0000febe-0000-1000-8000-00805f9b34fb` | BMAP BLE service |
| `C65B8F2F-AEE2-4C89-B758-BC4892D6F2D8` | Secure (encrypted) read/write/notify |
| `D417C028-9818-4354-99D1-2AC09D074591` | Unsecure read/write/notify |

The app tries the secure characteristic first and falls back to unsecure.
All communication happens through a single characteristic: the host writes
commands and subscribes to notifications for responses.

### MTU

The Bose app negotiates MTU on connect. Known values:

| Size | Description |
|------|-------------|
| 23 | BLE default (legacy) |
| 55 | Global safe default used by the Bose app |
| 104 | Large MTU for firmware updates |

### Segmentation

BMAP packets that exceed the usable MTU are split into segments. Each
segment is a BLE write of up to 20 bytes.

**Segment header** (1 byte):

```
Bits 7-4: max_segment_index (0 = single segment)
Bits 3-0: current_segment_index
```

**Examples:**

| Header | Meaning |
|--------|---------|
| `0x00` | Single unsegmented packet (also acts as the framing byte) |
| `0x10` | First of 2 segments (max=1, current=0) |
| `0x11` | Second of 2 segments (max=1, current=1) |
| `0x20` | First of 3 segments |

Each segment carries up to 19 bytes of payload data after the 1-byte
header, for a total of 20 bytes per BLE write.

**Reassembly:** collect segments in order, strip the 1-byte header from
each, concatenate the data portions.

### Write framing

For unsegmented writes, the single-segment header byte `0x00` doubles as
the BLE write framing byte that the Bose firmware expects. The segmentation
layer naturally provides this. For segmented writes, the segment headers
carry the index information and no additional framing is needed.

Bose device responses (BLE notifications) also use segmentation with the
same header format. Notifications do **not** include an additional framing
byte beyond the segment header.

## Packet structure

Every BMAP packet has a 4-byte header followed by a variable-length payload.

```
Offset  Size  Field
0       1     Function Block ID
1       1     Function ID
2       1     Device/Port/Operator byte
3       1     Payload length (0-255)
4..     N     Payload
```

**Byte 2 bit layout:**

```
Bits 7-6: Device ID (0-3)
Bits 5-4: Port number (0-3)
Bits 3-0: Operator ID (0-15)
```

Device ID and port are typically 0 for headphones. They are used for
multi-component products (e.g. left/right earbuds, charging case).

## Operators

| ID | Name | Direction | Description |
|----|------|-----------|-------------|
| 0 | Set | Command | Write a value |
| 1 | Get | Command | Read a value |
| 2 | SetGet | Command | Write then read back |
| 3 | Status | Response | Successful response with data |
| 4 | Error | Response | Error response (payload = error code) |
| 5 | Start | Command | Initiate an operation |
| 6 | Result | Response | Operation completed with result |
| 7 | Processing | Response | Operation in progress |

A typical exchange: host sends Get, device responds with Status. For
multi-step operations the device may send Processing followed by Result.

## Error codes

Error responses (operator 4) carry an error code in the first payload byte.

| Code | Name | Description |
|------|------|-------------|
| 0x00 | Unknown | Generic error |
| 0x01 | Length | Invalid packet length |
| 0x02 | Chksum | Invalid checksum |
| 0x03 | FblockNotSupp | Function block not supported |
| 0x04 | FuncNotSupp | Function not supported |
| 0x05 | OpNotSupp | Operator not supported for this function |
| 0x06 | InvalidData | Invalid data values |
| 0x07 | DataUnavailable | Requested data not available |
| 0x08 | Runtime | Temporary read/write failure |
| 0x09 | Timeout | Operation timed out |
| 0x0A | InvalidState | Not applicable in current state |
| 0x0B | DeviceNotFound | Device not in paired list |
| 0x0C | Busy | Device busy |
| 0xFF | FblockSpecific | Function-block-specific error; an additional byte follows with the specific code |

## Function blocks

| ID | Name | Purpose |
|----|------|---------|
| 0x00 | ProductInfo | Device identification, firmware version, serial |
| 0x01 | Settings | User configuration (name, timers, buttons, NC) |
| 0x02 | Status | Real-time state (battery, aux, in-ear) |
| 0x03 | FirmwareUpdate | OTA update flow |
| 0x04 | DeviceManagement | Pairing, connection routing, device list |
| 0x05 | AudioManagement | Audio source, volume, spatial audio |
| 0x06 | CallManagement | Voice call handling |
| 0x07 | Control | Power, reset, factory default |
| 0x08 | Debug | Diagnostic output |
| 0x09 | Notification | Event subscriptions |
| 0x0C | HearingAssistance | Hearing aid features |
| 0x0D | DataCollection | Analytics and telemetry |
| 0x0E | HeartRate | Biometric sensors (Bose Frames) |
| 0x10 | Vpa | Voice assistant (Alexa, Google) |
| 0x11 | Wifi | WiFi configuration (soundbars) |
| 0x12 | Authentication | Device authentication and encryption |
| 0x14 | Cloud | Cloud sync and OTA state |
| 0x1F | AudioModes | Audio mode switching (QC Ultra) |

---

## Implemented messages

### ProductInfo (0x00)

#### Product Name -- Settings 0x01 / 0x02

Note: the product name is under the Settings function block despite being
product info. The ProductInfo block has a separate `OriginalProductName`.

| | Packet |
|---|---|
| Query | `[0x01, 0x02, 0x01, 0x00]` |
| Response operator | Status (3) |
| Payload | `[0x00?, name_bytes...]` -- UTF-8 string, may have leading/trailing null bytes |

### Status (0x02)

#### Battery Level -- 0x02

| | Packet |
|---|---|
| Query | `[0x02, 0x02, 0x01, 0x00]` |
| Response operator | Status (3) |

**Payload** (4 bytes per component, repeating):

```
Offset  Size  Field
0       1     Battery percentage (0-100)
1       2     Remaining play time in minutes (big-endian, 0xFFFF = unknown)
3       1     Component ID (0 = primary, 1+ = case/buds)
```

Multiple 4-byte chunks for multi-component devices (e.g. earbuds + case).

### Settings (0x01)

#### CNC (Noise Cancellation) -- 0x05

Read-only on QC Ultra (SetGet returns error 0x05 OpNotSupp). Use
AudioModes for mode switching on newer devices.

| | Packet |
|---|---|
| Query | `[0x01, 0x05, 0x01, 0x00]` |
| Set (legacy) | `[0x01, 0x05, 0x02, 0x02, level, enabled]` |
| Response operator | Status (3) |

**Response payload** (3 bytes):

```
Offset  Size  Field
0       1     Current step (0-255; may exceed total_steps for special modes)
1       1     Total steps (number of NC levels)
2       1     Flags:
              - Bit 0: enabled (1 = on)
              - Bit 1: user enable/disable allowed (inverted: 0 = allowed)
```

#### Standby Timer -- 0x04

| | Packet |
|---|---|
| Query | `[0x01, 0x04, 0x01, 0x00]` |
| Set | `[0x01, 0x04, 0x02, 0x01, minutes]` |
| Response operator | Status (3) |

**Payload** (variable, first byte is minutes):

```
Offset  Size  Field
0       1     Minutes until auto-off (0 = never)
```

Common values: 0, 5, 10, 20, 30, 60, 120.

### Control (0x07)

#### Power -- 0x04

| | Packet |
|---|---|
| Power off | `[0x07, 0x04, 0x05, 0x01, 0x00]` |
| Power on | `[0x07, 0x04, 0x05, 0x01, 0x01]` |
| Operator | Start (5) |

**Payload** (1 byte):

```
0x00 = power off
0x01 = power on
```

### AudioModes (0x1F)

The AudioModes function block is used by newer Bose products (QC Ultra,
QC45, NC 700, etc.) for noise control mode switching. It replaces the
legacy Settings/CNC SetGet path.

#### Current Mode -- 0x03

| | Packet |
|---|---|
| Query | `[0x1F, 0x03, 0x01, 0x00]` |
| Set | `[0x1F, 0x03, 0x05, 0x02, mode_index, voice_prompt]` |
| Response operator | Status (3) |

**Set payload** (2 bytes):

```
Offset  Size  Field
0       1     Mode index (device-specific, typically 0-4)
1       1     Play voice prompt (0x00 = no, 0x01 = yes)
```

**Response payload** (1 byte):

```
Offset  Size  Field
0       1     Current mode index
```

#### Mode Config -- 0x06

Retrieves the full configuration for a specific mode index.

| | Packet |
|---|---|
| Query | `[0x1F, 0x06, 0x01, 0x01, mode_index]` |
| Response operator | Status (3) |

**Response payload** (up to 48 bytes):

```
Offset  Size  Field
0       1     Mode index
1       1     Prompt ID byte 1 (always 0x00 for Bose modes)
2       1     Prompt ID byte 2 (see prompt table below)
3       1     User configurable (0/1)
4       1     User configured (0/1)
5       1     Favorite (0/1)
6       32    Mode name (null-terminated UTF-8)
38      3     Reserved
41      1     Flags:
              - Bit 0: CNC level mutable
              - Bit 1: Auto-CNC mutable
              - Bit 2: Spatial audio mutable
              - Bit 3: ANR wind toggle mutable
              - Bit 4: ANC toggle mutable
42      1     CNC level
43      1     Auto-CNC enabled (0/1)
44      1     Spatial audio mode
45      1     Reserved
46      1     Wind block toggle
47      1     ANC toggle
```

Non-existent mode indices return an Error response.

#### Capabilities -- 0x02

| | Packet |
|---|---|
| Query | `[0x1F, 0x02, 0x01, 0x00]` |
| Response operator | Status (3) |

**Response payload** (7+ bytes):

```
Offset  Size  Field
0       1     Number of Bose modes
1       1     Number of user modes
2-4     3     Reserved
5       1     Feature flags:
              - Bit 0: CNC supported
              - Bit 1: Auto-CNC supported
              - Bit 2: Spatial audio supported
              - Bit 3: ANR wind toggle supported
              - Bit 4: User favorites supported
              - Bit 5: ANC toggle supported
6       1     Min simultaneous favorite modes (optional)
```

#### Names Supported -- 0x0B

Returns a bitmap of which mode prompt IDs the device supports.

| | Packet |
|---|---|
| Query | `[0x1F, 0x0B, 0x01, 0x00]` |
| Response operator | Status (3) |

**Response payload** (up to 5 bytes): bitmap where each bit represents
a prompt ID. Byte 0 bit 0 = prompt 0, byte 0 bit 1 = prompt 1, etc.

### Audio mode prompt table

The Bose app defines 36 named audio mode prompts. These are the names
the headset can announce via voice prompt, indexed by the prompt ID
in the ModeConfig response (byte 2):

| ID | Name | ID | Name | ID | Name |
|----|------|----|------|----|------|
| 0 | (none) | 13 | Focus | 25 | Whisper |
| 1 | Quiet | 14 | Relax | 26 | Hearing |
| 2 | Aware | 15 | Flight | 27 | Learn |
| 3 | Transparent | 16 | Airport | 28 | Podcast |
| 4 | Transparency | 17 | Driving | 29 | Audiobook |
| 5 | Masking | 18 | Training | 30 | Calm |
| 6 | Comfort | 19 | Gym | 31 | Sleep |
| 7 | Commute | 20 | Run | 32 | Meditate |
| 8 | Outdoor | 21 | Walk | 33 | Yoga |
| 9 | Workout | 22 | Hike | 34 | Immersion |
| 10 | Home | 23 | Talk | 35 | Stereo |
| 11 | Work | 24 | Call | 36 | Cinema |
| 12 | Music | | | | |

Note: the prompt ID is **not** the same as the mode index. Each device
mode has its own index (typically 0-4 on QC Ultra) and maps to a prompt
ID via the ModeConfig response. Mode names can also be custom strings
set by the user in the Bose app.

---

## Not yet implemented

These function blocks and functions are defined in the protocol but not
yet used by bozo:

- **DeviceManagement (0x04)**: Device list, pairing mode, multipoint routing
- **AudioManagement (0x05)**: Volume, now playing, spatial audio
- **FirmwareUpdate (0x03)**: OTA update flow
- **Authentication (0x12)**: Challenge-response device auth
- **Notification (0x09)**: Event subscription system
- **VPA (0x10)**: Voice assistant configuration
- **Settings**: Buttons, multipoint, on-head detection, voice prompts, ANR

## References

- Protocol details derived from Bose Music APK v12.1.6 (decompiled with jadx)
- Key source files in the APK:
  - `com.bose.bmap.messages.packets.*` -- packet constructors
  - `com.bose.bmap.messages.responses.*` -- response parsers
  - `com.bose.bmap.messages.enums.spec.*` -- protocol constants
  - `com.bose.bmap.ble.BleConnectionManager` -- BLE connection and framing
  - `com.bose.bmap.utils.PacketSegmentationUtil` -- segmentation
