# QC Ultra Baseline Probe

**Status:** The signed probe reached the physical headset and exposed an
operator mismatch during the first startup sync. The invalid requests have
been corrected; a clean physical rerun and evidence capture are still
required before this gate is complete.

## Environment

- macOS build: Not recorded; capture it on the corrected rerun.
- Xcode build: Not recorded; capture the local Xcode 27 build used for signing.
- Mac model: Not recorded; capture the Apple-silicon Mac used for validation.
- Headphone firmware: Not recorded; read it from Bose's device-information screen before validation.

## BLE discovery

| Check | Result | Evidence |
|---|---|---|
| Retrieve connected BMAP peripheral | Reached during first run | The probe connected far enough to receive a typed BMAP error response. |
| Filtered BMAP scan | Implemented | Five-second scan using service `FEBE`. |
| Bounded name-hint fallback | Implemented | Five-second unfiltered fallback; candidates remain unverified until identity is parsed. |
| BMAP service discovery | Reached during first run | A device-level BMAP error proves the service, characteristic, framing, and response path were active. |
| Characteristic selection | Pending transcript capture | Prefer secure notify-and-write; fall back to unsecure. |
| Notification subscription | Reached during first run | The probe decoded `0x05` OpNotSupp from a headset notification. |

## BMAP reads

| Function | Request hex | Response model | Sanitized response hex | Parsed value |
|---|---|---|---|---|
| Product name | `01020100` | STATUS | Not recorded | Not recorded |
| Battery | `02020100` | STATUS | Not recorded | Not recorded |
| AudioModes capabilities | `1F020100` | STATUS | Not recorded | Not recorded |
| Current mode | `1F030100` | STATUS | Not recorded | Not recorded |
| Standby | `01040100` | STATUS | Not recorded | Not recorded |
| Live audio settings | `1F0A0100` | STATUS, five-byte `[31.10]` state | Pending corrected rerun | Pending |
| AudioModes snapshot | `1F010500` | START, then multiple STATUS frames and optional RESULT | Pending corrected rerun | Pending |
| Every ModeConfig | Delivered by the snapshot as `[31.6]` STATUS packets | STATUS | Pending corrected rerun | Pending |

The first probe version incorrectly sent `[31.1]` with GET (`1F010100`) and
also queried an unverified AudioManagement `[5.15]` endpoint (`050F0100`).
Both requests can produce `0x05` because those operators/endpoints are not
the QC Ultra control path. The corrected probe uses START for `[31.1]` and
AudioModes SettingsConfig `[31.10]` for live immersive state.

## Essential write and restoration

| Operation | Original | Requested | Confirmed | Restored |
|---|---|---|---|---|
| Existing audio mode | Not run | Not run | Not run | Not run |
| Standby timer | Not run | Not run | Not run | Not run |
| Immersive audio, when supported | Not run | Not run | Not run | Not run |
| Power Off, performed last | Not run | Off | Expected disconnect not observed yet | Not applicable |

Immersive changes now use a safe read/modify/write sequence: read all five
bytes from `[31.10]`, replace only the immersive byte, SETGET the complete
state, and read it back again. This preserves CNC, auto-CNC/ActiveSense,
wind-block, and ANC values.

## Reconnect repetitions

| Attempt | Discovery path | Characteristic | Initial sync result |
|---|---|---|---|
| 1 | Pending corrected rerun | Not recorded | Not run |
| 2 | Pending corrected rerun | Not recorded | Not run |
| 3 | Pending corrected rerun | Not recorded | Not run |

## Identity fingerprint used by production

No production fingerprint has been admitted yet. Physical validation must
record the product response, AudioModes capability flags, valid ModeConfig
indexes, and stable non-user-editable product or firmware metadata. The
user-editable Bluetooth name is never sufficient by itself.

## Unsupported or ambiguous behavior

- Exact firmware response path has not yet been established in the Swift probe.
- The corrected `[31.1]` snapshot must be verified on the user's firmware.
- The corrected `[31.10]` live settings read and restoration flow must be verified physically.
- Simultaneous access with the Bose application has not been tested.

## Fixtures added

Shared Rust/Swift fixtures now cover:

- AudioModes snapshot START: `1F010500`
- Live audio settings GET: `1F0A0100`
- Full-state live audio SETGET while selecting Still mode

Add scrubbed physical response fixtures after the corrected read-only and
restoration checks are complete.

## Gate conclusion

**Pending corrected physical execution.** Plan 1 is not complete until the
signed probe reads the physical QC Ultra without unexpected startup errors,
repeats the reconnect flow three times, safely restores each essential
setting, powers off last, and commits sanitized evidence.
