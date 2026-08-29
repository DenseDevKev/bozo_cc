# Native QC Ultra macOS Controller — Design Specification

**Status:** Approved for planning  
**Date:** 2026-08-29  
**Development name:** QC Ultra Controller  
**Repository:** `DenseDevKev/bozo_cc`  
**Target branch:** `design/qc-ultra-macos-app`

## 1. Summary

QC Ultra Controller is a native macOS utility for controlling Bose QuietComfort Ultra Headphones (Gen 1) without requiring a terminal or the proprietary Bose application for everyday controls.

The application will provide three coordinated surfaces:

1. A full desktop application for status, mode selection, advanced mode editing, onboarding, and settings.
2. An optional compact menu-bar interface for frequent controls.
3. WidgetKit controls that users may place in macOS Control Center or directly in the system menu bar.

The application will be implemented entirely in Swift using public Apple frameworks. It will communicate directly with the headphones over CoreBluetooth using the reverse-engineered Bose Message Access Protocol (BMAP). The existing Rust implementation remains a protocol reference and test oracle but is not linked, launched, or shipped with the native application.

The headphones are the source of truth for all device modes and device settings. The application will not create a second preset database that can drift from the headset or the Bose app.

## 2. Approved product decisions

| Area | Decision |
|---|---|
| Supported hardware | Bose QuietComfort Ultra Headphones, Gen 1 only |
| Operating system | macOS 27.0 or newer |
| Processor | Apple silicon only; arm64 release binary |
| Runtime architecture | Pure native Swift; one main application process plus one WidgetKit control extension |
| Bluetooth | Direct CoreBluetooth/BLE; no RFCOMM compatibility layer in v1 |
| Distribution | Personal builds first; optional signed and notarized GitHub release later |
| App Store posture | App Sandbox and public frameworks from the beginning to preserve a straightforward future App Store path |
| Primary experience | User chooses desktop-first or menu-bar-first during onboarding; menu-bar-first is preselected |
| Mode storage | Headphones are the sole source of truth; no local preset library |
| Mode editing | Staged edits with an explicit Apply action and device read-back verification |
| Control Center | Configurable audio-mode control, cycle mode, Immersive Audio, and reconnect; no power-off control |
| Visual direction | Native macOS 27 controls and system Liquid Glass behavior; no imitation glassmorphism |
| Network access | None required in v1 |
| Updates | Manual installation from GitHub releases; no in-app updater in v1 |

## 3. Goals

The v1 product must:

- Make the QC Ultra controllable without terminal knowledge.
- Feel structurally and visually native to macOS 27.
- Keep CPU, memory, wakeups, and Bluetooth activity low when idle.
- Expose one authoritative headphone state to every user interface.
- Reconnect predictably after temporary disconnects, Mac sleep, and headphone power cycles.
- Support the verified everyday controls already demonstrated by `bozo` and `bozo-bar`.
- Support advanced editing only for mode properties proven writable and readable on the physical QC Ultra Gen 1.
- Remain compatible with App Sandbox and a future Mac App Store submission.
- Be understandable and testable without requiring a physical headset for most development work.

## 4. Non-goals

The following are explicitly outside v1:

- Custom headphone firmware, firmware flashing, downgrading, or OTA firmware control.
- Arbitrary BMAP packet injection in the normal application.
- Bose earbuds, QC45, standard QuietComfort, NC 700, speakers, or other Bose products.
- Intel Mac support.
- Windows, Linux, iOS, or Android clients.
- Classic Bluetooth/RFCOMM control.
- App-only presets or automatic preset synchronization.
- Parametric EQ, system audio processing, virtual audio devices, or DSP modification.
- Bose accounts, cloud sync, analytics, telemetry, advertising, or crash-reporting services.
- A background privileged helper, launch daemon, XPC service, local web server, or separate Rust daemon.
- A third-party update framework.
- One-tap power-off from Control Center.

## 5. Repository and target layout

The native application will live in this fork without becoming a runtime dependency of the Rust workspace.

```text
apps/
└── QCUltraController/
    ├── QCUltraController.xcodeproj
    ├── QCUltraController/              # Main app target
    ├── QCUltraControlsExtension/       # WidgetKit controls
    ├── QCUltraControllerTests/
    └── QCUltraControllerUITests/

packages/
└── HeadphoneCore/
    ├── Package.swift
    ├── Sources/
    │   └── HeadphoneCore/
    └── Tests/
        └── HeadphoneCoreTests/
```

The checked-in Xcode project will contain these targets:

- `QCUltraController`: SwiftUI/AppKit application.
- `QCUltraControlsExtension`: WidgetKit control extension.
- `HeadphoneCore`: internal Swift package containing BMAP and device-domain logic.
- Unit and UI test targets.

No package in the native application will link to the Rust crates. Existing Rust sources and `docs/BMAP.md` remain reference material and can be used to construct fixtures and parity tests.

The initial development identifiers will be:

- Main app: `dev.densedevkev.qcultra`
- Control extension: `dev.densedevkev.qcultra.controls`
- App Group: `group.dev.densedevkev.qcultra`

Changing the public product name or identifiers before a public release is a release-management task, not an architectural dependency.

## 6. High-level architecture

```text
┌───────────────────────────────────────────────────────┐
│ Main macOS application                               │
│                                                       │
│  Desktop scenes   MenuBarExtra   Settings/Onboarding  │
│         \              |               /              │
│          └────────── AppModel (@MainActor) ──────────┘
│                              │
│                     HeadphoneSession actor
│                    /          |           \
│        command queue     state machine    snapshot store
│              │               │                  │
│              └──── BluetoothCentralAdapter ─────┘
│                              │
│                         CoreBluetooth
│                              │
│                   Bose QC Ultra Gen 1
└───────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────┐
│ WidgetKit control extension                          │
│                                                       │
│  Control provider ── reads App Group snapshot         │
│  App Entity query ── reads cached mode definitions    │
│  Action intent ───── executes in main app when valid  │
└───────────────────────────────────────────────────────┘
```

### 6.1 `HeadphoneCore`

`HeadphoneCore` is UI-independent and contains:

- BMAP packet encoding and decoding.
- BLE segmentation and reassembly.
- Function-block and function identifiers.
- Typed query and mutation builders.
- Typed response parsers.
- Device and mode capability models.
- Mode-draft validation rules.
- Response matching and protocol error types.
- Captured packet fixtures with identifying values removed.

It must not import SwiftUI, AppKit, WidgetKit, ServiceManagement, or application preferences.

### 6.2 `BluetoothCentralAdapter`

CoreBluetooth delegate APIs will be isolated behind a small `NSObject` adapter. It will:

- Own `CBCentralManager` and the active `CBPeripheral`.
- Run delegate callbacks on one dedicated serial dispatch queue.
- Discover the BMAP service and secure/unsecure characteristics.
- Subscribe to notifications.
- Perform BLE writes.
- Publish typed transport events to `HeadphoneSession` using async sequences or continuations.

It will not decide application policy, perform retries, edit modes, or mutate UI state.

### 6.3 `HeadphoneSession`

A single Swift actor will own the logical connection and device session. It will:

- Drive the connection state machine.
- Select and remember the chosen peripheral.
- Serialize all BMAP requests and mutations.
- Match responses to the one active command.
- Merge unsolicited state notifications.
- Apply timeouts and retry policy.
- Cache confirmed state and capabilities.
- Write shared snapshots for WidgetKit.
- Coordinate reconnect backoff.

No UI or extension may establish a second BLE session.

### 6.4 `AppModel`

A `@MainActor` observable application model will:

- Present `HeadphoneSession` state to SwiftUI.
- Expose user actions as async commands.
- Track pending actions and user-facing errors.
- Own only interface state and application preferences.

It will not parse BMAP packets or own CoreBluetooth objects.

## 7. Concurrency model

- SwiftUI and AppKit state remain on the main actor.
- `HeadphoneSession` serializes logical state and commands as an actor.
- CoreBluetooth delegate callbacks remain on a dedicated serial queue inside `BluetoothCentralAdapter`.
- The adapter bridges events into the session actor without blocking its delegate queue.
- Exactly one command that expects a BMAP response may be in flight at a time because BMAP responses do not provide a general request identifier.
- Shared snapshots are encoded away from the main actor and replaced atomically in the App Group container.
- No synchronous wait, semaphore, spin loop, or blocking file operation is permitted on the main actor.

## 8. Connection state machine

The authoritative connection phase is:

```swift
enum ConnectionPhase: Equatable, Sendable {
    case unconfigured
    case permissionRequired
    case idle
    case scanning
    case connecting
    case synchronizing
    case connected
    case reconnecting(attempt: Int)
    case unavailable(UnavailableReason)
    case failed(SessionError)
}
```

Expected transitions:

```text
unconfigured
  └─ device selected ──> connecting

permissionRequired
  └─ permission granted ──> scanning/connecting

idle
  └─ launch, wake, or reconnect ──> connecting or scanning

scanning
  ├─ selected device found ──> connecting
  └─ bounded scan expires ──> reconnecting

connecting
  ├─ services and notifications ready ──> synchronizing
  └─ timeout/error ──> reconnecting

synchronizing
  ├─ required initial queries complete ──> connected
  └─ transport loss ──> reconnecting

connected
  ├─ unexpected disconnect ──> reconnecting
  ├─ intentional power-off ──> unavailable(poweredOff)
  ├─ forget device ──> unconfigured
  └─ Mac sleep ──> idle

reconnecting
  ├─ connection restored ──> synchronizing
  └─ auto reconnect disabled ──> idle
```

Automatic reconnect delays are bounded:

```text
1 second → 2 seconds → 5 seconds → 10 seconds → 30 seconds maximum
```

A reconnect attempt consists of a bounded lookup/scan and connection attempt. The application must not scan continuously. The backoff resets after a stable successful connection.

Power-off is treated as an expected disconnect. The app will not immediately fight the user action by reconnecting to a headset that is intentionally shutting down. It returns to normal reconnect behavior when the selected peripheral is observed again or the user requests reconnect.

Mac sleep cancels active scans and command timeouts. A wake notification triggers a fresh selected-device lookup followed by the normal reconnect sequence.

## 9. Supported-device validation

Advertisement names are not authoritative because users can rename Bluetooth devices. Selection and validation follow this sequence:

1. Discover a peripheral exposing the BMAP service.
2. Connect and subscribe to BMAP notifications.
3. Query product identity and required capability blocks.
4. Accept the peripheral only when it matches the validated QC Ultra Gen 1 identity/capability signature.
5. Reject unsupported hardware with a clear explanation and do not persist it as the selected device.

The exact product identifier and capability signature will be recorded during the first hardware feasibility work. There is no compatibility override in normal v1 builds.

## 10. BMAP command model

Each logical command is represented by a typed descriptor containing:

- Request packet or ordered request packets.
- Expected function block, function ID, and response operator.
- Response parser.
- Timeout.
- Whether a GET retry is safe.
- Optional post-mutation read-back query.

Rules:

- GET operations may retry once after a timeout when the transport remains connected.
- Mutating commands do not retry automatically because blindly repeating a write can create unintended partial changes.
- The app never reports a mutation as successful merely because CoreBluetooth accepted the write.
- A mutation is complete only after the relevant state is read back and matches the requested value.
- Protocol `Error` responses become typed errors with the function block, function, and Bose error code preserved for diagnostics.
- Disconnecting cancels in-flight and queued commands with a connection-lost result.
- Unsolicited state notifications update the confirmed state even when no command is pending.

Default timing policy:

- Peripheral connection attempt: 10 seconds.
- Ordinary BMAP response: 3 seconds.
- Multi-step mode apply operation: 15 seconds total.
- A short device-settle delay may precede a read-back query when hardware testing proves it necessary.

These values are constants covered by session tests and can be tuned without changing the architecture.

## 11. Device state and source of truth

`HeadphoneState` contains only confirmed device values:

- Connection phase.
- Product identity and firmware version when available.
- Battery percentage and remaining play time when available.
- Current audio-mode index.
- Discovered mode definitions.
- Standby timer.
- Immersive Audio state.
- Confirmed advanced mode properties.
- Capabilities and mutability flags.
- Timestamp of the last confirmed device response.

The UI may show a pending indicator, but it must not overwrite confirmed state with an optimistic value. After a command succeeds, the confirmed read-back updates all surfaces.

Locally persisted data is limited to:

- Selected CoreBluetooth peripheral identifier.
- Onboarding version.
- Desktop-first/menu-bar-first preference.
- Menu-bar visibility and battery-title preference.
- Launch-at-login preference.
- Automatic reconnect preference.
- Hidden diagnostics preference.
- Last shared read-only snapshot for system controls.

No device mode or device setting is persisted as a second authoritative copy.

## 12. Advanced mode editing

The Modes screen lists only mode configurations reported by the headphones.

Selecting a mode creates a `ModeDraft` from the latest confirmed `ModeConfiguration`. The editor displays only properties whose device capability flags and verified protocol support indicate they are editable.

Candidate properties for validation are:

- Mode name.
- Favorite status.
- ANC/CNC strength.
- Automatic noise-control behavior.
- Wind filtering.
- Immersive Audio behavior.
- ANC enable/disable behavior when exposed by the mode.

Rules:

- Unsupported or unverified properties are hidden, not disabled with speculative behavior.
- The mode-name field enforces the actual encoded byte limit; it does not silently truncate a UTF-8 name.
- Favorite constraints reported by the headset are validated before Apply.
- ANC ranges are derived from validated device data rather than hard-coded assumptions.
- Apply is disabled while disconnected, synchronizing, or another mutation is pending.
- Navigating away with dirty edits requires Discard or Continue Editing.

Apply flow:

1. Fetch the latest mode configuration if the draft is stale.
2. Validate the draft against current capabilities.
3. Compute a field-level diff.
4. Build an ordered mutation sequence using only verified commands.
5. Execute the sequence through the shared command queue.
6. Query the complete mode configuration again.
7. Replace the UI with confirmed values.
8. Report any mismatched fields explicitly.

BMAP does not provide a true transaction or guaranteed rollback. If only part of a multi-field sequence succeeds, the application will not issue a blind rollback. It will show the confirmed partial result, identify fields that failed verification, and let the user retry from current device state.

## 13. First-launch onboarding

Onboarding is functional and short:

1. **Welcome** — explains direct local Bluetooth control, no account, and unofficial/non-affiliated status.
2. **Bluetooth Access** — requests permission in response to an explicit user action and explains recovery if denied.
3. **Select Headphones** — lists compatible candidates, validates the chosen device, and stores its identifier.
4. **Choose App Behavior** — desktop-first or menu-bar-first, with menu-bar-first preselected.
5. **System Integration** — optional launch at login, menu-bar battery text, and instructions for adding system controls.

Onboarding is complete only after the selected device passes the QC Ultra Gen 1 validation handshake. A user can leave onboarding and resume later without losing prior interface choices.

## 14. Main desktop application

The main window uses a native `NavigationSplitView` with three destinations.

### 14.1 Overview

- Product name.
- Connected, reconnecting, unavailable, or failed state.
- Battery percentage and remaining play time.
- Last confirmed update time when state is stale.
- Current mode.
- Quick mode selection for all discovered modes.
- Immersive Audio control when supported.
- Standby timer.
- Reconnect action.
- Power-off action with confirmation.

### 14.2 Modes

- Headset-reported mode list.
- Current/favorite indicators.
- Staged advanced editor.
- Apply, Revert, and dirty-state handling.
- Field-level validation and post-apply verification results.

### 14.3 Settings

- Desktop-first or menu-bar-first behavior.
- Show/hide app menu-bar item.
- Menu-bar icon only or icon plus battery percentage.
- Launch at login using `SMAppService`.
- Automatic reconnect.
- Forget selected headphones.
- Restore interface preferences.
- Hidden diagnostics switch.
- Version, MIT license, upstream attribution, privacy statement, and unofficial-product disclaimer.

The application prevents an inaccessible configuration. A user cannot simultaneously hide every in-app entry surface while running with accessory activation policy.

## 15. Menu-bar experience

The optional app-owned `MenuBarExtra` uses window style and contains:

- Device name and connection state.
- Battery.
- Current audio mode.
- Quick selection for all discovered headset modes.
- Immersive Audio control when supported.
- Reconnect.
- Power off with confirmation.
- Open Full App.
- Settings.
- Quit.

Advanced mode editing remains in the desktop window.

In menu-bar-first mode, the app uses accessory activation policy after onboarding and does not open the main window automatically. Opening the full app changes focus normally without creating a second application instance. In desktop-first mode, the app uses regular activation policy and opens the main window on launch.

Closing the main window does not quit the application while the menu-bar item is enabled. Quit tears down the session and terminates the process.

## 16. Control Center and system menu-bar controls

The WidgetKit extension provides:

1. **Set Audio Mode** — configurable to one headset-reported mode.
2. **Cycle Audio Mode** — advances through available/favorite modes in the confirmed order.
3. **Immersive Audio** — toggle when the headset reports support.
4. **Reconnect Headphones** — requests connection restoration.

Power Off is intentionally excluded.

The extension reads a compact `SharedHeadphoneSnapshot` from the App Group container. The snapshot contains:

- Selected device identity token.
- Connection/staleness state.
- Battery percentage.
- Current mode identifier and name.
- Cached mode identifiers and names for control configuration.
- Immersive Audio support/state.
- Last-updated timestamp.

The snapshot is display and configuration data only. It is not a second authoritative settings store.

Action intents are shared between the app and extension. The preferred execution target is the main app process so the action reaches the single `HeadphoneSession`. Entity/configuration queries may execute in the WidgetKit extension because they only read the shared snapshot.

The extension must never instantiate CoreBluetooth or maintain its own connection.

Because the relevant macOS 27 execution-target API is pre-release during this design, implementation begins with a feasibility gate:

- Preferred behavior: macOS executes the action in the main app process, including when no app window is open.
- Required fallback: when the system cannot reliably revive or execute the hidden app session, the intent requests foreground continuation or opens the application to perform the action.

The product will not duplicate the Bluetooth engine in an extension to avoid foregrounding.

After confirmed state changes, the app writes a new snapshot and requests WidgetKit control reloads. An old snapshot is not presented as live connection state; staleness is evaluated from its timestamp.

## 17. Application lifecycle

Startup flow:

1. Load interface preferences.
2. Initialize the application model.
3. Create the single headphone session.
4. Check Bluetooth authorization.
5. Retrieve the saved peripheral when configured.
6. Connect or start a bounded scan according to reconnect settings.
7. Show the appropriate desktop/menu-bar experience.

The application observes Mac sleep and wake through documented workspace notifications. It pauses scanning and command timers before sleep and begins a new connection attempt after wake.

Launch at login uses `SMAppService.mainApp`. No launch agent plist or helper executable is installed.

The app does not rely on continuous timers for battery or state polling. Refreshes occur on:

- Initial connection.
- Headset notifications.
- Explicit commands and their read-backs.
- App foregrounding when the last confirmed state is stale.
- Mac wake.
- Manual refresh/reconnect.

## 18. Error handling and user feedback

Normal users receive concise errors with a useful next action. Raw protocol details stay in diagnostics.

| Condition | User-facing behavior |
|---|---|
| Bluetooth permission denied | Explain the missing permission and provide a System Settings recovery action/instructions |
| Bluetooth powered off | Show unavailable state and wait for adapter state change |
| Selected headset not found | Show reconnecting state and bounded retry schedule; provide Reconnect and Forget Device |
| Connection timeout | Enter reconnect backoff without blocking the UI |
| Unsupported Bose device | Reject selection and explain v1 supports QC Ultra Gen 1 only |
| BMAP error response | Preserve confirmed state, identify the failed action, and offer retry where safe |
| Command timeout | Cancel pending UI state; retry only safe GET operations |
| Disconnect during Apply | Cancel remaining writes, reconnect, refresh mode, and show confirmed partial result |
| Read-back mismatch | Show the actual confirmed value and identify the rejected field |
| Power-off disconnect | Treat as expected and do not show an error |
| Stale Control Center snapshot | Show unavailable/stale state and route action through the main app |

Errors do not silently disappear when the user needs to act, but transient reconnect events do not produce repeated modal alerts.

## 19. Visual and interaction design

The interface uses standard macOS 27 components so the operating system supplies appropriate Liquid Glass behavior:

- Native windows, sidebars, toolbars, sheets, menus, popovers, forms, pickers, toggles, gauges, buttons, and inspectors.
- SF Symbols for functional icons.
- System typography and semantic colors.
- System selection, focus, hover, disabled, and active-window states.
- Regular content surfaces rather than custom translucent cards.
- Liquid Glass only where standard controls and system materials naturally apply it.

The app will not use fake reflections, decorative blur stacks, persistent animated backgrounds, or a custom imitation of Apple controls.

Accessibility requirements:

- Full keyboard navigation.
- VoiceOver labels and values for all controls.
- Meaning is never conveyed by color alone.
- Support for light/dark appearances, increased contrast, reduced transparency, reduced motion, and larger accessibility text where macOS provides it.
- Pending, connected, and failed states are communicated in text as well as iconography.

The app icon and visual assets must be original and must not use Bose logos or imply official affiliation.

## 20. Privacy, sandboxing, and security

The project starts with App Sandbox enabled.

Expected entitlements are limited to:

- App Sandbox.
- Bluetooth device access.
- App Group shared container.
- The entitlements required by the WidgetKit extension.

The app has no network entitlement in v1. It collects no analytics, account data, audio content, listening history, or cloud data.

The selected peripheral identifier and preferences are not secrets and remain in sandboxed preferences. No Keychain storage is required in v1.

Logging uses `os.Logger` with privacy annotations. Device serial numbers, Bluetooth addresses, and raw packet payloads are not emitted in normal logs. Raw BMAP payload logging is available only when the hidden diagnostics switch is enabled and remains local.

FirmwareUpdate, Authentication experimentation, arbitrary packet injection, and undocumented system APIs are not exposed by the production app.

## 21. Performance and energy requirements

The implementation optimizes for native idle behavior rather than synthetic micro-optimization.

Requirements:

- arm64-only release configuration.
- No Electron, embedded browser, Node runtime, Rust daemon, or local server.
- No third-party runtime framework unless a later design explicitly justifies it.
- One CoreBluetooth central and one active peripheral connection.
- At most one active BLE scan.
- Bounded scans with reconnect backoff.
- No periodic polling loop while connected and idle.
- No continuous animation when the relevant surface is hidden.
- Shared snapshot writes only when meaningful state changes.
- Diagnostics views and packet rendering are lazy.
- Instruments checks for idle CPU, wakeups, memory growth, retained peripherals, and energy impact are release gates.

An idle connected app should spend effectively all time asleep between Bluetooth/system events. Exact numeric budgets will be recorded from a baseline Apple-silicon Mac during implementation and treated as regression thresholds.

## 22. Diagnostics

Diagnostics remain hidden from normal users and are enabled from Settings.

The diagnostic view may show:

- App and OS version.
- Headset product and firmware version.
- Current connection phase.
- Selected peripheral identifier in redacted form.
- Active BMAP characteristic type.
- Recent connection transitions.
- Recent command names, durations, and result categories.
- Packet metadata: direction, function block, function, operator, and payload length.

Raw payload bytes are off by default, never included in ordinary release logs, and never transmitted anywhere. V1 does not include an arbitrary command console.

## 23. Testing strategy

### 23.1 `HeadphoneCore` unit tests

- Packet encode/decode round trips.
- Multiple packets in one notification.
- Single and multi-segment BLE framing.
- Missing, duplicated, out-of-order, and malformed segments.
- Battery, product, standby, audio-mode, capability, and Immersive Audio parsers.
- Protocol error parsing.
- Mode-name UTF-8 byte validation.
- Mode-draft capability validation.
- Captured QC Ultra packet fixtures.

### 23.2 Session tests with a fake transport

- Every connection-state transition.
- Selected-device restoration.
- Connection and command timeouts.
- Safe GET retry and no automatic SET retry.
- Serialized commands.
- Unsolicited notifications while idle and while a command is pending.
- Disconnect during initial synchronization.
- Disconnect during multi-field Apply.
- Read-back mismatch.
- Expected disconnect after power-off.
- Reconnect backoff and reset.
- Sleep/wake cancellation and restart.
- App Group snapshot freshness.

### 23.3 App and UI tests

- First-launch onboarding.
- Permission-denied state.
- Device selection and unsupported-device rejection.
- Desktop-first and menu-bar-first startup.
- Main-window navigation.
- Mode dirty-state protection.
- Apply progress, success, partial failure, and mismatch states.
- Settings persistence.
- Forget device.
- Menu-bar controls.
- Power-off confirmation.
- Accessibility labels and keyboard navigation.

### 23.4 App Intent and WidgetKit tests

- Configuration from cached mode entities.
- Connected and disconnected action results.
- Stale or missing snapshot.
- App running with a window open.
- App running without a window.
- App not currently running.
- Permission denied.
- Control reload after state change.

### 23.5 Physical-device release checklist

Every release candidate is tested against the actual QC Ultra Gen 1 for:

- Clean install and onboarding.
- Cold launch.
- Automatic reconnect.
- Quiet, Aware, and custom-mode switching.
- Immersive Audio changes.
- Standby timer.
- Every enabled advanced mode field.
- Mode read-back after Apply.
- Partial failure recovery.
- Menu-bar behavior.
- Control Center behavior.
- Desktop-first/menu-bar-first switching.
- Mac sleep and wake.
- Headset power cycle.
- Power off.
- Interaction when the Bose app is installed or recently used.

### 23.6 Performance tests

- Release build startup.
- Idle connected energy usage.
- Idle disconnected/reconnecting energy usage.
- Scan duty cycle.
- Memory stability across repeated reconnects.
- No retained `CBPeripheral` or command continuations after disconnect.

## 24. Required feasibility gates

These gates occur before broad feature implementation.

### Gate 1: Advanced mode-writing validation

Purpose: prove exact, safe write and read-back behavior for candidate advanced properties.

Method:

- Compare existing BMAP documentation and native/Rust implementations.
- Capture or derive the Bose app's relevant commands where legally and technically appropriate.
- Execute narrowly scoped writes on the physical QC Ultra Gen 1.
- Read the complete mode configuration after each write.
- Record supported firmware version and packet fixtures.
- Avoid the FirmwareUpdate function block entirely.

Exit criteria:

- Each v1 editor field has a verified builder, response behavior, read-back, and failure case.
- Unsupported fields are removed from v1 UI.
- No field is shipped based only on a guessed packet layout.

### Gate 2: Control Center execution validation

Purpose: prove the WidgetKit control-to-main-session lifecycle on macOS 27.

Test matrix:

- App open and visible.
- App running with no window.
- Menu-bar-first accessory mode.
- App terminated.
- Launch at login.
- Bluetooth permission denied.
- Headphones unavailable.
- Mac sleep and wake.

Exit criteria:

- Use direct main-process execution when macOS reliably launches or reaches the main app session.
- Otherwise use the defined foreground-continuation/open-app fallback.
- Do not move BLE ownership into the extension.
- Revalidate against the final macOS 27 SDK before any public release because the execution-target API is pre-release at design time.

## 25. Distribution and release design

Development begins with local signed builds.

An optional GitHub release will contain an arm64 application packaged as a ZIP or DMG. Before public distribution it will be:

- Signed with Developer ID.
- Hardened-runtime enabled.
- Notarized and stapled.
- Accompanied by the MIT license, upstream attribution, privacy statement, and installation notes.

V1 has no automatic update service. The app may display its installed version and provide a user-invoked route to the repository release page only if network access is later explicitly added; otherwise version checking remains outside the app.

Future Mac App Store preparation should require entitlement and metadata work rather than an architectural rewrite. The app therefore avoids privileged helpers, private APIs, executable downloads, non-sandbox file access, and external runtimes from the start.

## 26. Compatibility with upstream work

- The existing MIT license and attribution are preserved.
- `bozo` remains a protocol and behavioral reference.
- `bozo-bar` remains a native implementation reference.
- Ported code must preserve required copyright notices.
- New production code is reorganized around the architecture in this document rather than copying the prototype's single large Bluetooth manager.
- Changes useful to upstream protocol understanding may be proposed separately, but v1 delivery does not depend on upstream acceptance.

## 27. Key risks and mitigations

| Risk | Mitigation |
|---|---|
| Bose firmware changes packet behavior | Capability-driven UI, firmware version in diagnostics, fixtures, safe failure, no speculative writes |
| Advanced fields are read-only or differ by mode | Gate 1; hide anything not verified |
| Control Center cannot reliably reach a terminated app | Gate 2; foreground/open-app fallback; never duplicate BLE in extension |
| Pre-release macOS 27 API changes | Revalidate with final SDK and avoid public release from beta SDK |
| Connection conflicts or timing issues with Bose app | Physical test matrix, serialized commands, reconnect handling, confirmed read-back |
| Multi-field Apply partially succeeds | No blind rollback; refresh and expose confirmed partial result |
| Continuous scanning harms battery life | Bounded scan windows and capped reconnect backoff |
| Prototype code becomes an oversized manager | Enforced separation between adapter, session actor, core protocol, app model, and views |
| App appears officially associated with Bose | Original name/assets and explicit unofficial/non-affiliated disclosure |
| App Group/signing setup complicates local builds | Keep shared schema small and configure entitlements in the checked-in Xcode project from the first implementation milestone |

## 28. Acceptance criteria for v1

V1 is complete only when all of the following are true:

1. A clean install can request Bluetooth access, discover, validate, and save a QC Ultra Gen 1.
2. Unsupported Bose devices are rejected without becoming the selected device.
3. The user can choose desktop-first or menu-bar-first and change the choice later.
4. Desktop, menu bar, and system controls reflect one confirmed state.
5. Battery, connection, current mode, Immersive Audio, and standby state load after connection.
6. All headset-reported modes can be selected.
7. Mode changes are verified by device read-back before success is shown.
8. Every visible advanced editor field passed Gate 1.
9. Dirty mode edits cannot be lost accidentally.
10. Partial advanced-mode failure produces an accurate confirmed state and understandable error.
11. Reconnect works after transient disconnect, headset power cycle, and Mac wake without continuous scanning.
12. Power off requires confirmation in the app and is absent from Control Center.
13. Control Center actions pass Gate 2 using either direct main-process execution or the defined foreground fallback.
14. Closing the desktop window preserves menu-bar operation when enabled.
15. Launch at login uses `SMAppService`.
16. App Sandbox remains enabled and the app uses only public Apple frameworks.
17. The production app performs no network requests and collects no telemetry.
18. Protocol/session tests pass without a physical headset.
19. The physical-device release checklist passes on the supported firmware/device.
20. Instruments finds no continuous idle polling, runaway scans, reconnect memory growth, or leaked Bluetooth objects.
21. The arm64 release can be signed and notarized without changing application architecture.
22. License, upstream attribution, privacy, and unofficial-product disclosures are present.

## 29. Planning boundary

The implementation plan must begin with project scaffolding and the two feasibility gates. It must not schedule the full advanced editor or final Control Center integration until their respective gates pass.

The plan should preserve vertical milestones that remain runnable:

1. Native project, sandbox, signing, and core package.
2. Protocol parity fixtures and basic QC Ultra connection.
3. Read-only desktop status.
4. Reliable command queue and everyday controls.
5. Menu-bar experience and lifecycle.
6. Advanced-mode feasibility and verified editor.
7. Control Center feasibility and controls.
8. Accessibility, performance, packaging, and release hardening.

This section defines sequencing constraints only; task-level implementation steps belong in the separate implementation plan.
