# bozod

Background daemon that maintains a BLE connection to Bose headphones and
exposes headphone state over a Unix socket.

## What it does

1. Scans for Bose BLE peripherals (by name prefix `LE-` or service UUID)
2. Connects and discovers the BMAP characteristic (secure or unsecure)
3. Queries initial device state (name, battery, audio mode, standby timer)
4. Listens for BLE notifications and parses BMAP responses
5. Serves clients on `/tmp/bozod.sock` with JSON-lines IPC
6. Pushes real-time state updates to all connected clients

## Running

The daemon is normally auto-spawned by the `bozo` TUI. To run it manually:

```sh
# From the app bundle (required on macOS for BLE permissions)
make run

# Or directly with logging
RUST_LOG=bozod=debug target/debug/bozod

# Scan for devices without connecting
target/debug/bozod --scan-only
```

## IPC protocol

Clients connect to `/tmp/bozod.sock` and exchange newline-delimited JSON.

**Requests** (client to daemon):

| Type | Data | Description |
|------|------|-------------|
| `GetState` | -- | Fetch full `HeadphoneState` snapshot |
| `SetAudioMode` | `{mode_index}` | Switch active audio mode |
| `SetStandbyTimer` | `{minutes}` | Set auto-off timer (0 = never) |
| `SetCnc` | `{level, enabled}` | Legacy CNC control (may not work on all models) |
| `PowerOff` | -- | Power off headphones |
| `Reconnect` | -- | Reconnect BLE |
| `Disconnect` | -- | Disconnect BLE |

**Responses** (daemon to client):

| Type | Data | Description |
|------|------|-------------|
| `State` | `HeadphoneState` | Full state snapshot (reply to `GetState`) |
| `StateUpdate` | `StateUpdate` | Incremental state change (pushed) |
| `Ok` | -- | Command acknowledged |
| `Error` | `{message}` | Error description |

State updates are pushed to all connected clients whenever the headphone
state changes (battery, mode switch, timer change, connection status, etc.).

## Architecture

```
BLE notifications
      |
      v
ConnectionManager --broadcast--> StateManager --broadcast--> Server
      ^                                                        |
      |                                                        v
  BleCommand <---mpsc--- handle_request() <---socket--- IPC clients
```

- **ConnectionManager**: Owns the BLE peripheral, sends/receives BMAP packets
- **StateManager**: Parses BMAP responses into typed state, broadcasts updates
- **Server**: Accepts Unix socket clients, forwards requests and pushes updates
