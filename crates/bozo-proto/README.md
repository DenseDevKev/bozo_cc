# bozo-proto

Protocol library for the Bose BMAP (Bose Message Access Protocol) over BLE,
plus IPC types for daemon-client communication.

## Modules

### `bmap` -- BMAP packet codec

- **`packet`** -- Serialize/deserialize BMAP packets (4-byte header + payload).
  Supports parsing single packets and concatenated multi-packet buffers.
- **`segment`** -- BLE segmentation layer. Splits large BMAP packets into
  20-byte BLE chunks (1-byte header + 19 bytes data) and reassembles them.
- **`enums`** -- Function block IDs, operator types, and function constants
  for each supported BMAP subsystem.

### `protocol` -- Typed BMAP message builders and parsers

Each module provides `query()`, `set(...)`, and `parse_response(...)` functions
for a specific BMAP function:

| Module | FBlock | Function | Description |
|--------|--------|----------|-------------|
| `battery` | Status (0x02) | 0x02 | Battery level and remaining time |
| `cnc` | Settings (0x01) | 0x05 | Noise cancellation level (legacy, read-only on QC Ultra) |
| `audio_modes` | AudioModes (0x1F) | 0x03/0x06 | Audio mode switching and config discovery |
| `standby` | Settings (0x01) | 0x04 | Auto-off timer |
| `name` | Settings (0x01) | 0x02 | Product name |
| `power` | Control (0x07) | 0x04 | Power on/off |

### `ipc` -- Daemon/client IPC

- **`message`** -- `IpcRequest`, `IpcResponse`, `HeadphoneState`, `StateUpdate`
  enums and structs, serde-tagged for JSON encoding.
- **`transport`** -- `IpcReader` / `IpcWriter` for async JSON-lines framing
  over any tokio `AsyncRead` / `AsyncWrite` (typically a Unix socket).

## Usage

```rust
use bozo_proto::bmap::packet::BmapPacket;
use bozo_proto::protocol::{battery, audio_modes};

// Build a battery query
let pkt = battery::query();
let bytes = pkt.to_bytes(); // [0x02, 0x02, 0x01, 0x00]

// Parse a response
let parsed = BmapPacket::from_bytes(&response_bytes)?;
let info = battery::parse_response(&parsed)?;
println!("battery: {}%", info[0].percentage);

// Switch audio mode
let cmd = audio_modes::set_current_mode(1); // mode index 1
```
