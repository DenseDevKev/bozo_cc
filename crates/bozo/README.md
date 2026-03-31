# bozo

Terminal UI for controlling Bose headphones. Connects to the `bozod` daemon
over a Unix socket and displays real-time headphone state.

## Features

- Auto-spawns `bozod` if it isn't already running
- Real-time battery, audio mode, and standby timer display
- Audio mode switching (Quiet, Aware, Adaptive, etc.)
- Standby timer cycling
- Power off with confirmation
- Discovers mode names from the device on startup

## Running

```sh
# From app bundle (recommended on macOS)
make run

# Or directly
cargo run -p bozo
```

The TUI looks for `bozod` next to its own binary (for app bundle use) or
on `PATH`. If no daemon is running on `/tmp/bozod.sock`, it spawns one and
waits up to 15 seconds for the socket to appear.

## Keybindings

| Key | Action |
|-----|--------|
| `+` / `=` / `Right` | Next audio mode |
| `-` / `Left` | Previous audio mode |
| `t` / `T` | Cycle standby timer (0 / 5 / 10 / 20 / 30 / 60 / 120 min) |
| `p` / `P` | Power off (prompts y/n) |
| `r` / `R` | Reconnect to headphones |
| `Tab` | Switch focus between sections |
| `q` / `Q` | Quit TUI (daemon keeps running) |

## macOS app bundle

The `make build` target packages `bozo` as the main executable inside
`bozo.app`, with `bozod` copied alongside it. The `Info.plist` includes
`NSBluetoothAlwaysUsageDescription` so macOS grants Bluetooth access to
the bundle. The TUI is the responsible process for TCC -- users grant
permission once to `bozo.app` and both binaries can use CoreBluetooth.
