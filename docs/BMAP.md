# BMAP Protocol Reference

BMAP (Bose Message Access Protocol) is a proprietary protocol used by Bose
headphones and speakers for device control over Bluetooth. This document
covers the BLE transport and the message formats relevant to headphone
control, reverse-engineered from the Bose Music Android app and checked
against physical-device captures from open-source Bose control projects.

## BLE transport

### Service and characteristics

| UUID | Purpose |
|------|---------|
| `0000febe-0000-1000-8000-00805f9b34fb` | BMAP BLE service |
| `C65B8F2F-AEE2-4C89-B758-BC4892D6F2D8` | Secure (encrypted) read/write/notify |
| `D417C028-9818-4354-99D1-2AC09D074591` | Unsecure read/write/notify |

The app tries the secure characteristic first and falls back to unsecure.
All communication happens through one characteristic: the host writes
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

```text
Bits 7-4: max_segment_index (0 = single segment)
Bits 3-0: current_segment_index
```

| Header | Meaning |
|--------|---------|
| `0x00` | Single unsegmented packet and framing byte |
| `0x10` | First of 2 segments (max=1, current=0) |
| `0x11` | Second of 2 segments (max=1, current=1) |
| `0x20` | First of 3 segments |

Each segment carries up to 19 bytes after the header. Reassembly collects
all segments for a packet, removes each segment header, and concatenates the
remaining bytes. Notifications use the same segmentation format.

## Packet structure

Every BMAP packet has a 4-byte header followed by a variable-length payload.

```text
Offset  Size  Field
0       1     Function Block ID
1       1     Function ID
2       1     Device/Port/Operator byte
3       1     Payload length (0-255)
4..     N     Payload
```

Byte 2 uses bits 7-6 for device ID, bits 5-4 for port, and bits 3-0 for the
operator. Device ID and port are normally zero for over-ear headphones.

## Operators

| ID | Name | Direction | Description |
|----|------|-----------|-------------|
| 0 | Set | Command | Write a value |
| 1 | Get | Command | Read a value |
| 2 | SetGet | Command | Write then return the resulting value |
| 3 | Status | Response | Successful state response |
| 4 | Error | Response | Error response |
| 5 | Start | Command | Initiate an operation or response stream |
| 6 | Result | Response | Operation completed |
| 7 | Processing | Response | Operation in progress |

A normal read is GET followed by STATUS. A START command can yield multiple
STATUS packets before a RESULT packet.

## Error codes

Error responses carry the error code in the first payload byte.

| Code | Name | Description |
|------|------|-------------|
| `0x00` | Unknown | Generic error |
| `0x01` | Length | Invalid packet length |
| `0x02` | Chksum | Invalid checksum |
| `0x03` | FblockNotSupp | Function block not supported |
| `0x04` | FuncNotSupp | Function not supported |
| `0x05` | OpNotSupp | Operator not supported for this function |
| `0x06` | InvalidData | Invalid data values |
| `0x07` | DataUnavailable | Requested data not available |
| `0x08` | Runtime | Temporary read/write failure |
| `0x09` | Timeout | Operation timed out |
| `0x0A` | InvalidState | Not applicable in the current state |
| `0x0B` | DeviceNotFound | Device not in paired list |
| `0x0C` | Busy | Device busy |
| `0xFF` | FblockSpecific | Additional byte contains a block-specific code |

## Function blocks

| ID | Name | Purpose |
|----|------|---------|
| `0x00` | ProductInfo | Device identity and firmware metadata |
| `0x01` | Settings | User configuration |
| `0x02` | Status | Real-time state such as battery |
| `0x03` | FirmwareUpdate | OTA update flow |
| `0x04` | DeviceManagement | Pairing and connection routing |
| `0x05` | AudioManagement | Audio source, playback, and volume functions |
| `0x06` | CallManagement | Voice-call handling |
| `0x07` | Control | Power and reset operations |
| `0x08` | Debug | Diagnostic output |
| `0x09` | Notification | Event subscriptions |
| `0x0C` | HearingAssistance | Hearing-assistance features |
| `0x0D` | DataCollection | Analytics and telemetry |
| `0x0E` | HeartRate | Biometric sensors |
| `0x10` | Vpa | Voice-assistant configuration |
| `0x11` | Wifi | Wi-Fi configuration |
| `0x12` | Authentication | Device authentication |
| `0x14` | Cloud | Cloud and OTA state |
| `0x1F` | AudioModes | QC Ultra noise-control and immersive settings |

---

## Implemented messages

### Product name — Settings `[1.2]`

| | Packet |
|---|---|
| Query | `[0x01, 0x02, 0x01, 0x00]` |
| Response | STATUS |
| Payload | Optional null framing plus UTF-8 product name |

### Battery level — Status `[2.2]`

| | Packet |
|---|---|
| Query | `[0x02, 0x02, 0x01, 0x00]` |
| Response | STATUS |

The payload repeats a four-byte component record:

```text
Offset  Size  Field
0       1     Battery percentage (0-100)
1       2     Remaining play time in minutes, big-endian (FFFF = unknown)
3       1     Component ID
```

### CNC — Settings `[1.5]`

This endpoint is read-only on QC Ultra. A legacy SETGET returns `0x05`
(OpNotSupp); mode switching and live noise-control values use AudioModes.

| | Packet |
|---|---|
| Query | `[0x01, 0x05, 0x01, 0x00]` |
| Legacy set | `[0x01, 0x05, 0x02, 0x02, level, enabled]` |
| Response | STATUS |

### Standby timer — Settings `[1.4]`

| | Packet |
|---|---|
| Query | `[0x01, 0x04, 0x01, 0x00]` |
| SetGet | `[0x01, 0x04, 0x02, 0x01, minutes]` |
| Response | STATUS |

The first payload byte is the number of minutes; zero means never.
Common values are 0, 5, 10, 20, 30, 60, and 120.

### Power — Control `[7.4]`

| | Packet |
|---|---|
| Power off | `[0x07, 0x04, 0x05, 0x01, 0x00]` |
| Power on | `[0x07, 0x04, 0x05, 0x01, 0x01]` |
| Operator | START |

Power off normally completes through the expected Bluetooth disconnect.

## AudioModes `[31.x]`

AudioModes is the authoritative QC Ultra block for modes, ANC-related live
state, and immersive audio.

### GetAll snapshot — `[31.1]`

| | Packet |
|---|---|
| Start snapshot | `[0x1F, 0x01, 0x05, 0x00]` |
| Operator | START, not GET |
| Response | A burst of STATUS packets for supported AudioModes functions |

`[31.1]` is not a list-valued GET endpoint. Sending
`[0x1F, 0x01, 0x01, 0x00]` can return `0x05` because GET is not supported.
The snapshot can include capabilities, current/default mode, one ModeConfig
packet per stored mode, favorites, live SettingsConfig, and supported names.
A RESULT packet may terminate the stream. Mode IDs come from byte zero of
each `[31.6]` ModeConfig payload.

### Capabilities — `[31.2]`

| | Packet |
|---|---|
| Query | `[0x1F, 0x02, 0x01, 0x00]` |
| Response | STATUS |

```text
Offset  Size  Field
0       1     Number of Bose modes
1       1     Number of user modes
2-4     3     Reserved
5       1     Feature flags
6       1     Minimum favorite count, when present
```

Feature bits are CNC, auto-CNC/ActiveSense, immersive audio, wind block,
favorites, and ANC toggle in bits 0 through 5.

### Current mode — `[31.3]`

| | Packet |
|---|---|
| Query | `[0x1F, 0x03, 0x01, 0x00]` |
| Set | `[0x1F, 0x03, 0x05, 0x02, mode_index, voice_prompt]` |
| Response | STATUS for GET; START may acknowledge with RESULT |

The STATUS payload is the current mode index. For SET, the second payload
byte controls whether the headphones play the mode voice prompt.

### ModeConfig — `[31.6]`

| | Packet |
|---|---|
| Query | `[0x1F, 0x06, 0x01, 0x01, mode_index]` |
| Response | STATUS |

The QC Ultra configuration payload is at least 48 bytes:

```text
Offset  Size  Field
0       1     Mode index
1-2     2     Prompt ID
3       1     User configurable (0/1)
4       1     User configured (0/1)
5       1     Favorite (0/1)
6       32    Null-terminated UTF-8 name
38      3     Reserved
41      1     Mutable-field mask
42      1     CNC level
43      1     Auto-CNC/ActiveSense enabled
44      1     Immersive mode
45      1     Reserved
46      1     Wind block enabled
47      1     ANC enabled
```

The mutable mask uses bits 0-4 for CNC level, auto-CNC, immersive mode, wind
block, and ANC respectively. Extra trailing bytes must be preserved until
their meaning is verified.

### Live SettingsConfig — `[31.10]`

This is the live five-byte audio state for the active mode. It is also the
correct endpoint for changing immersive audio on QC Ultra Headphones.
AudioManagement `[5.15]` is not the QC Ultra immersive endpoint and a GET
there can return `0x05`.

| | Packet |
|---|---|
| Query | `[0x1F, 0x0A, 0x01, 0x00]` |
| SetGet | `[0x1F, 0x0A, 0x02, 0x05, cnc, auto_cnc, immersive, wind, anc]` |
| Response | STATUS with the complete five-byte state |

```text
Offset  Field
0       CNC level
1       Auto-CNC/ActiveSense enabled (0/1)
2       Immersive mode: 0=Off, 1=Still, 2=Motion
3       Wind block enabled (0/1)
4       ANC enabled (0/1)
```

A client changing only immersive mode must first read `[31.10]`, replace
byte two, and write all five bytes back. Sending a one-byte spatial payload
would risk replacing or invalidating the other live settings.

### Names supported — `[31.11]`

| | Packet |
|---|---|
| Query | `[0x1F, 0x0B, 0x01, 0x00]` |
| Response | STATUS |

The payload is a bitmap of supported spoken mode prompt IDs.

### Audio-mode prompt table

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

Prompt ID and mode index are different values. ModeConfig maps a stored mode
index to its prompt ID and optional custom name.

---

## Not yet implemented

- DeviceManagement pairing, routing, and paired-device list
- AudioManagement playback/source/volume functions
- FirmwareUpdate OTA flow
- Authentication challenge-response
- Notification subscriptions
- Voice-assistant configuration
- Remaining Settings endpoints such as buttons, multipoint, and wear sensing

## References

- Bose Music Android app v12.1.6 decompilation (`com.bose.bmap.*`)
- `depau/bosectl-android` protocol notes and QC Ultra-family captures
- `aaronsb/bosectl` QC Ultra Headphones implementation and captures
- Physical validation performed through the sandboxed Ultra Controller probe
