# bozo

Control Bose QC Ultra headphones from your terminal.

bozo is a Rust workspace that talks to Bose headphones over BLE using the
proprietary BMAP protocol. It consists of a background daemon that maintains
the Bluetooth connection and a terminal UI for viewing state and switching
audio modes.

## Architecture

```
bozo (TUI)  <--JSON-lines-->  bozod (daemon)  <--BMAP/BLE-->  headphones
             Unix socket                        CoreBluetooth
```

| Crate | Purpose |
|-------|---------|
| [bozo-proto](crates/bozo-proto/) | BMAP codec, BLE segmentation, IPC types |
| [bozod](crates/bozod/) | BLE daemon: scanning, connection, state management |
| [bozo](crates/bozo/) | Ratatui TUI client |

The TUI auto-spawns the daemon if it isn't already running. Both binaries
are packaged into a single macOS `.app` bundle so that CoreBluetooth TCC
permissions only need to be granted once.

## Quick start

```sh
# Build (requires Rust toolchain)
make build

# Or with devenv
devenv shell -- make build

# Run the TUI (spawns daemon automatically)
make run

# First time on macOS: grant Bluetooth permission
make grant-bluetooth
```

## TUI keybindings

| Key | Action |
|-----|--------|
| `+` / `-` | Switch audio mode (Quiet, Aware, etc.) |
| `t` | Cycle standby timer |
| `p` | Power off (with y/n confirmation) |
| `r` | Reconnect |
| `Tab` | Switch focus |
| `q` | Quit |

## macOS Bluetooth permissions

CoreBluetooth requires the binary to live inside a `.app` bundle with
`NSBluetoothAlwaysUsageDescription` in its `Info.plist`. The `make build`
target produces `bozo.app` containing both binaries. On first launch macOS
will prompt for Bluetooth access -- grant it to `bozo.app`.

If you run the TUI from a terminal emulator managed by a window manager
(e.g. AeroSpace), grant Bluetooth to the window manager process, not the
terminal app.

## Protocol

The BMAP protocol was reverse-engineered from the Bose Music Android app
(v12.1.6). See [docs/BMAP.md](docs/BMAP.md) for the full protocol reference.

## Supported devices

Developed and tested with **Bose QuietComfort Ultra Headphones (Gen 1)**.
Other Bose products using BMAP over BLE may work with minor adjustments.
The QC Ultra uses the AudioModes function block (0x1F) for noise control
rather than the legacy Settings/CNC path used by older models.

## License

[MIT](LICENSE)
