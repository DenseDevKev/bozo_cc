# QC Ultra Baseline Probe

**Status:** Automated probe implementation is ready. Physical execution and evidence capture have not yet been performed.

## Environment

- macOS build: Not recorded; run the signed probe on the target Mac.
- Xcode build: Not recorded; record the local Xcode 27 build used for signing.
- Mac model: Not recorded; record the Apple-silicon Mac used for validation.
- Headphone firmware: Not recorded; read it from the available device information or Bose application before validation.

## BLE discovery

| Check | Result | Evidence |
|---|---|---|
| Retrieve connected BMAP peripheral | Not run | The probe calls `retrieveConnectedPeripherals` before scanning. |
| Filtered BMAP scan | Not run | Five-second scan using service `FEBE`. |
| Bounded name-hint fallback | Not run | Five-second unfiltered fallback; candidates remain unverified. |
| BMAP service discovery | Not run | Full service UUID is documented in `docs/BMAP.md`. |
| Characteristic selection | Not run | Prefer secure notify-and-write; fall back to unsecure. |
| Notification subscription | Not run | Record selected channel and write type from the probe transcript. |

## BMAP reads

| Function | Request hex | Response operator | Sanitized response hex | Parsed value |
|---|---|---|---|---|
| Product name | `01020100` | Not run | Not recorded | Not recorded |
| Battery | `02020100` | Not run | Not recorded | Not recorded |
| AudioModes capabilities | `1F020100` | Not run | Not recorded | Not recorded |
| AudioModes indexes | `1F010100` | Not run | Not recorded | Not recorded |
| Current mode | `1F030100` | Not run | Not recorded | Not recorded |
| Every reported ModeConfig | Generated from reported indexes | Not run | Not recorded | Not recorded |
| Standby | `01040100` | Not run | Not recorded | Not recorded |
| Spatial audio | `050F0100` | Not run | Not recorded | Not recorded |

## Essential write and restoration

| Operation | Original | Requested | Confirmed | Restored |
|---|---|---|---|---|
| Existing audio mode | Not run | Not run | Not run | Not run |
| Standby timer | Not run | Not run | Not run | Not run |
| Spatial audio, when supported | Not run | Not run | Not run | Not run |
| Power Off, performed last | Not run | Off | Expected disconnect not observed yet | Not applicable |

## Reconnect repetitions

| Attempt | Discovery path | Characteristic | Initial sync result |
|---|---|---|---|
| 1 | Not run | Not recorded | Not run |
| 2 | Not run | Not recorded | Not run |
| 3 | Not run | Not recorded | Not run |

## Identity fingerprint used by production

No production fingerprint has been admitted yet. Physical validation must record the product response, AudioModes capability flags, valid mode indexes, and any stable non-user-editable product or firmware metadata that can be read safely. The user-editable Bluetooth name is never sufficient by itself.

## Unsupported or ambiguous behavior

- Exact firmware response path has not yet been established in the Swift probe.
- Spatial audio may return a typed unsupported/error response; record the exact operator and code.
- Simultaneous access with the Bose application has not been tested.

## Fixtures added

The repository currently contains synthetic and documented protocol fixtures only. Add scrubbed physical request/response fixtures after the read-only and restoration checks are complete.

## Gate conclusion

**Pending physical execution.** Plan 1 is not complete until the signed probe reads the physical QC Ultra, repeats the reconnect flow three times, safely restores each essential setting, powers off last, and commits sanitized evidence.
