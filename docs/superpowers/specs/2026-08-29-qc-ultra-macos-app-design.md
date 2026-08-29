# QC Ultra macOS Controller — Product and Architecture Design

**Date:** 2026-08-29  
**Status:** Ready for user review  
**Working product name:** QC Ultra Control  
**Repository:** `DenseDevKev/bozo_cc`  
**Target branch:** `design/qc-ultra-macos-app`

## 1. Summary

QC Ultra Control is a lightweight, native macOS application for controlling Bose QuietComfort Ultra Headphones Gen 1 without requiring a terminal or the proprietary Bose client for everyday controls.

The application will provide three coordinated interfaces:

1. A full desktop window for status, mode management, and advanced editing.
2. An optional menu-bar controller for fast access.
3. Optional macOS Control Center controls backed by App Intents.

The application will be written entirely in Swift, use CoreBluetooth directly, target Apple Silicon and macOS 27 or newer, and follow the native macOS design system rather than imitating it with custom glass effects. The existing Rust `bozo` implementation and the native Swift `bozo-bar` project will be treated as protocol and behavior references, not runtime dependencies.

The initial distribution target is personal use or a GitHub Release. The project will nevertheless use App Sandbox, public Apple frameworks, minimal entitlements, and an extension-safe architecture so a future Mac App Store submission does not require a major rewrite.

## 2. Product decisions

The following decisions are fixed for version 1:

- **Supported hardware:** Bose QuietComfort Ultra Headphones Gen 1 only.
- **Supported platform:** Apple Silicon Macs running macOS 27 or newer.
- **Implementation:** Native Swift and SwiftUI in Swift 6 language mode with strict concurrency, plus targeted AppKit use where macOS behavior requires it.
- **Bluetooth:** One direct CoreBluetooth session owned by the main app process.
- **Primary experience:** On first launch, the user chooses desktop-first or menu-bar-first behavior. Menu-bar-first is preselected.
- **Distribution:** Personal build or GitHub Release first; future Mac App Store compatibility is preserved.
- **Version 1 feature level:** Essential controls plus verified advanced audio-mode editing.
- **Mode ownership:** The headphones are the sole source of truth. The app will not maintain a separate preset library.
- **Control Center:** Quick, system-rendered controls only. Power Off is excluded from Control Center.
- **Editing behavior:** Advanced changes are staged, applied as a verified app-level transaction, and read back from the headphones before the UI reports success.
- **Runtime dependencies:** No third-party runtime libraries, no embedded browser, no Node process, no Rust daemon, and no local server.

## 3. Goals

### 3.1 User goals

The application should let a non-technical user:

- Connect to a paired QC Ultra headset.
- See connection state, battery level, remaining play time when available, firmware information, and the current audio mode.
- Switch among Quiet, Aware, and custom modes.
- Change Immersive Audio behavior when supported.
- Change the standby timer.
- Power off the headphones from the desktop or menu-bar interface.
- Inspect and edit verified properties of modes stored on the headphones.
- Use common actions from the menu bar or Control Center without opening the main window.
- Choose whether the app behaves primarily as a desktop app or a background menu-bar utility.

### 3.2 Engineering goals

The implementation should:

- Feel indistinguishable from a well-designed native macOS utility.
- Maintain exactly one authoritative Bluetooth session.
- Remain responsive during scans, reconnections, and command timeouts.
- Keep protocol code independent from UI and Apple lifecycle code.
- Keep CoreBluetooth delegate mechanics isolated from domain state.
- Be testable without physical headphones for most logic.
- Use event-driven updates instead of periodic polling.
- Keep idle CPU use effectively zero and avoid unnecessary wakeups.
- Preserve a clean path to code signing, notarization, sandboxing, and a future Mac App Store submission.

## 4. Non-goals

Version 1 will not include:

- Replacement or modified headphone firmware.
- Firmware installation, downgrade, or recovery tools.
- Bose earbuds, QC Ultra Gen 2, older QuietComfort models, NC 700, speakers, or generic BMAP-device support.
- Windows, Linux, iOS, iPadOS, or visionOS clients.
- Classic Bluetooth or RFCOMM transport.
- A local preset library separate from modes stored on the headphones.
- Cloud sync, user accounts, analytics, advertising, or telemetry.
- A built-in automatic updater.
- Raw packet injection or a public protocol console.
- An equalizer beyond properties that are explicitly verified as writable on the supported headset.
- One-tap Power Off from Control Center.
- Mac App Store submission work as part of the initial release.

## 5. Repository and project structure

The existing Rust workspace remains intact as a protocol reference. The native app will be added as a separate product under the same repository so development can begin without disrupting the original command-line implementation.

```text
bozo_cc/
├── crates/                         Existing Rust protocol, daemon, and TUI
├── docs/
│   └── superpowers/specs/          Product and implementation specifications
├── fixtures/
│   └── bmap/                       Sanitized protocol fixtures shared by tests
└── apps/
    └── QCUltraControl/
        ├── QCUltraControl.xcodeproj
        ├── App/
        │   ├── Application/
        │   ├── Bluetooth/
        │   ├── Features/
        │   └── Resources/
        ├── ControlsExtension/
        ├── Packages/
        │   └── HeadphoneCore/
        └── Tests/
```

The release app will not link against or launch any Rust binary. The Rust code may be used to cross-check packet behavior and generate test fixtures during development.

Working identifiers:

- Main app: `dev.densedevkev.qcultracontrol`
- Control extension: `dev.densedevkev.qcultracontrol.controls`
- App Group: `group.dev.densedevkev.qcultracontrol`

The working user-facing name is **QC Ultra Control**. A later branding change does not alter package boundaries, identifiers, or architecture unless explicitly chosen before public release.

## 6. Architecture

### 6.1 High-level structure

```text
Desktop Window ─┐
Menu Bar ───────┼──> Application Model ──> HeadphoneSession actor
Settings ───────┘                              │
                                                ├──> HeadphoneCore package
                                                │
                                                └──> CoreBluetoothTransport
                                                          │
                                                          v
                                                   CoreBluetooth
                                                          │
                                                          v
                                                 QC Ultra Gen 1

Control Center Extension
    ├── reads a versioned shared state snapshot
    └── invokes App Intents in the main app process
```

The main application process is the only component that may own a Bluetooth connection. The desktop window, menu bar, settings, and App Intents all act through the same `HeadphoneSession`.

### 6.2 `HeadphoneCore`

`HeadphoneCore` is an internal Swift package with no SwiftUI, AppKit, UserDefaults, WidgetKit, CoreBluetooth, or application-lifecycle dependencies.

Responsibilities:

- BMAP packet encoding and decoding.
- BLE framing, segmentation, and reassembly.
- Typed query and command builders.
- Typed response parsers.
- Bose error decoding.
- Device-identity and firmware models.
- Capability models.
- Audio-mode models.
- Protocol fixtures and deterministic unit tests.
- A transport protocol used by session tests.

Representative public types:

```swift
struct BMAPPacket
struct HeadphoneIdentity
struct HeadphoneCapabilities
struct HeadphoneState
struct AudioMode
struct AudioModeConfiguration
struct BatteryStatus
enum SpatialAudioMode
enum BMAPError
protocol HeadphoneTransport
```

The package must not contain UI-facing status strings. It returns typed data and typed errors; the app layer maps those into user-facing language.

### 6.3 `CoreBluetoothTransport`

CoreBluetooth uses delegate callbacks and Objective-C runtime conventions that should not leak into the session actor. A small `NSObject`-based adapter isolates those mechanics.

Responsibilities:

- Own `CBCentralManager` and `CBPeripheral` delegate conformance.
- Run delegate work on one dedicated serial dispatch queue.
- Discover peripherals, services, and characteristics.
- Subscribe to notifications.
- Perform BLE writes.
- Convert delegate callbacks into small `Sendable` transport events.
- Expose events to `HeadphoneSession` through an `AsyncStream` or equivalent structured-concurrency boundary.

It does not:

- Parse BMAP domain messages beyond BLE framing needs.
- Decide reconnection policy.
- Mutate application state.
- Present errors to the user.
- Maintain command queues or capability rules.

This boundary keeps non-Sendable Apple objects confined to one implementation layer while the actor consumes value-type events.

### 6.4 `HeadphoneSession`

`HeadphoneSession` is a long-lived Swift actor that owns all authoritative device and command state. It owns a `CoreBluetoothTransport`, but does not directly serve as a CoreBluetooth delegate.

Responsibilities:

- Supported-device discovery and selection policy.
- Product identity and firmware validation.
- Connection state machine.
- BMAP request and response handling.
- Initial capability and state loading.
- Serialized command execution.
- Timeouts and cancellation.
- Read-after-write verification.
- Best-effort rollback for multi-field edits.
- Reconnection and bounded backoff.
- Sleep and wake handling.
- Rate-limited state refreshes.
- Publishing authoritative state to the app model.
- Persisting only the selected peripheral identifier and user preferences.

Only one command that changes headset state may be in flight at a time. Read-only refreshes may be coalesced, but they must not race with a state-changing transaction.

### 6.5 Application model

A `@MainActor` application model exposes session state to SwiftUI and maps domain errors into presentation state.

It does not contain Bluetooth logic. It coordinates:

- Navigation state.
- Sheets and confirmations.
- Staged mode edits and their baseline values.
- Pending-action indicators.
- User preferences.
- Shared state snapshot updates for the Control extension.

Every interface observes this same model or a read-only projection of it. No interface maintains a separate copy of authoritative headphone state.

### 6.6 Shared Control snapshot

The main app writes a compact, versioned snapshot to the App Group container using an atomic replace operation.

The snapshot contains only what Control Center needs:

```swift
struct SharedHeadphoneSnapshot: Codable, Sendable {
    let schemaVersion: Int
    let updatedAt: Date
    let connectionPhase: SharedConnectionPhase
    let batteryPercentage: UInt8?
    let currentModeID: UInt8?
    let modes: [SharedAudioMode]
    let immersiveAudio: SharedImmersiveAudioMode?
}
```

The extension treats old or unreadable schema versions as unavailable, and treats snapshots older than a defined staleness threshold as stale. It never interprets cached state as proof that a Bluetooth command succeeded.

### 6.7 Control Center extension and App Intents

The WidgetKit Control extension is intentionally small. It may:

- Read the latest sanitized state snapshot from the App Group container.
- Render system-provided control templates.
- Invoke an App Intent.
- Request a control refresh after an action completes.

It may not:

- Create a CoreBluetooth central manager.
- Scan for headphones.
- Maintain a second connection.
- Directly encode or write BMAP commands.

Initial intents:

- `SetAudioModeIntent`
- `CycleAudioModeIntent`
- `SetImmersiveAudioIntent`
- `ReconnectHeadphonesIntent`

The Set Audio Mode control is configurable and uses cached mode identifiers and names. If a cached mode no longer exists, the intent reports that the configuration is stale and prompts the user to open the app.

A feasibility gate will verify how macOS 27 executes these intents when the app is running, windowless, suspended, or not running. The required behavior is:

1. Prefer execution in the main app process and reuse the existing session.
2. Allow the system to activate the app without opening a normal window when supported.
3. If the system will not provide a reliable background execution path, fail safely with an action that opens the app and reconnects.

The extension must never claim an action succeeded until the main app confirms the Bluetooth transaction.

## 7. Connection and command model

### 7.1 Connection state machine

The authoritative connection phase is one of:

```text
unconfigured
permissionRequired
bluetoothUnavailable
scanning
connecting
validatingDevice
loadingState
connected
reconnecting
unavailable
failed
```

State transitions are explicit and testable. UI surfaces display friendly labels, while diagnostics preserve typed causes.

### 7.2 Device identification and firmware policy

A matching BLE service makes a peripheral a connection candidate, not automatically a supported headset.

After connecting, the session queries product identity, model information available through BMAP, and firmware version before enabling controls. It then applies these rules:

- A confirmed QC Ultra Gen 1 proceeds to capability loading.
- A known unsupported product is rejected with a clear message.
- An ambiguous product is not given write access until identity can be confirmed.
- Essential controls may remain available on a new firmware only after required capability queries and safe read paths succeed.
- Advanced editing is disabled for firmware that has not passed the physical-device compatibility checks unless its responses exactly match a validated capability profile.

Firmware version is visible in About/Device information and included in diagnostics, but never used as a substitute for runtime capability checks.

### 7.3 Initial connection flow

```text
Bluetooth permission granted
    -> locate or scan for the selected candidate peripheral
    -> connect
    -> discover BMAP service and characteristics
    -> subscribe to notifications
    -> query and validate product identity and firmware
    -> query capabilities
    -> query device name, battery, current mode, modes, standby, and spatial state
    -> publish connected state
```

The app must not consider the session fully connected until notifications are active, identity is supported, and the initial state load has completed or reached a defined partial-state timeout.

### 7.4 State refresh policy

The session refreshes state on:

- Initial connection.
- Relevant headset notifications.
- Successful state-changing commands.
- App activation.
- Menu-bar controller presentation.
- Mac wake.
- Explicit user refresh or reconnect.

Lifecycle-triggered reads are rate-limited and coalesced. There is no permanent background polling timer. This keeps battery and mode state current when the user interacts with the app without creating unnecessary wakeups.

### 7.5 Reconnection

Unexpected disconnects use bounded backoff:

```text
1 second -> 2 seconds -> 5 seconds -> 10 seconds -> 30 seconds maximum
```

The retry counter resets after a stable connection. Scanning pauses while the Mac sleeps and resumes after wake. A manual Reconnect action cancels the existing retry timer and begins a fresh attempt immediately.

The app avoids continuous high-duty scanning. When the selected device remains unavailable, it reduces scan frequency and exposes a clear disconnected state.

### 7.6 Single-setting command transactions

Every state-changing command follows the same transaction:

```text
validate identity, capability, and connection
    -> enqueue command
    -> write BMAP packet
    -> wait for transport acknowledgement when available
    -> query the changed property
    -> compare returned state with requested state
    -> publish success or typed failure
```

The UI may show an optimistic pending selection, but it must visually distinguish pending state from confirmed state. If verification fails, the UI returns to the last confirmed value and presents an error.

A command is not successful merely because bytes were queued for Bluetooth transmission.

### 7.7 Multi-field mode Apply transaction

The headphones may not support an atomic write for a complete mode configuration. Therefore, **transactional** means an app-coordinated, verified sequence rather than a promise of hardware atomicity.

When Apply is pressed:

1. Capture the last confirmed mode configuration as the rollback baseline.
2. Validate every changed field against capabilities.
3. Write changed fields in a defined safe order.
4. Query the complete mode configuration.
5. Compare every intended field while preserving unknown fields.
6. Report success only when the read-back matches.
7. On failure, attempt a best-effort restoration of fields already changed.
8. Query the complete configuration again and display the actual headset state.

If restoration is incomplete, the app explicitly reports a partial apply. It never pretends that the baseline was restored when the headset reports otherwise.

### 7.8 Timeouts and cancellation

- Each command has an explicit timeout appropriate to the operation.
- A disconnect cancels commands that require the old connection.
- A superseding user action may cancel an older queued action that has not started.
- Power Off ends the session after the write is accepted by the transport and does not wait for a read-back that cannot occur after shutdown.
- Repeated identical commands are coalesced.

## 8. Capability-driven behavior

The app must not hard-code that every QC Ultra exposes every property. On connection, it builds a `HeadphoneCapabilities` model from verified protocol responses.

The UI follows these rules:

- Unsupported properties are hidden.
- Read-only properties are displayed but not editable.
- Writable properties are enabled only after successful capability validation.
- Unknown flags and bytes are preserved when rewriting a mode configuration.
- A mode edit writes only fields that changed.
- Advanced writes require a supported identity, compatible firmware profile, and a validated response shape.
- Any property that cannot be safely written and read back during the feasibility phase is removed from version 1.

Candidate advanced properties for validation:

- Mode name.
- Favorite status.
- ANC/CNC level.
- Automatic noise-control behavior.
- Wind filtering.
- ANC toggle behavior.
- Immersive Audio mode or behavior.

The specification does not assume all candidate properties will survive validation. Version 1 includes only properties proven safe on the physical QC Ultra Gen 1.

## 9. User experience

### 9.1 First-launch onboarding

Onboarding is short and functional:

1. **Welcome** — explains direct local control, no Bose account, and no cloud service.
2. **Bluetooth Access** — requests permission and gives a recovery path if denied.
3. **Select Headphones** — lists QC Ultra connection candidates, connects to the selection, and validates that it is a supported Gen 1 headset before saving it.
4. **Choose App Behavior** — menu-bar-first is preselected; desktop-first is the alternative.
5. **Optional Integration** — launch at login, battery in menu bar, and instructions for adding Control Center controls.

Known unsupported Bose products are omitted or labeled unsupported. An ambiguous candidate is validated after connection and rejected safely if it is not the target headset.

### 9.2 Desktop window

The main window uses a native `NavigationSplitView` with three destinations.

#### Overview

- Product name.
- Connection phase.
- Battery percentage and remaining time when available.
- Current mode.
- Quick Quiet, Aware, and discovered custom-mode controls.
- Immersive Audio selector when supported.
- Standby timer.
- Reconnect.
- Power Off with confirmation.
- Last confirmed state time when data may be stale.

#### Modes

- Lists modes stored on the headphones.
- Selecting a mode opens a native detail editor.
- Shows only properties supported by that mode and headset.
- Edits are staged locally against a captured baseline.
- Apply performs the verified multi-field sequence.
- Cancel discards staged changes.
- A failed or partially rejected sequence refreshes the confirmed headset state and explains whether rollback succeeded.

There is no app-only preset library.

#### Settings

- Desktop-first or menu-bar-first behavior.
- Show or hide the menu-bar item, subject to the accessibility rule in Section 11.
- Menu-bar icon only or icon plus battery percentage.
- Launch at login.
- Automatic reconnect.
- Forget selected headphones.
- Reset interface preferences.
- Optional developer diagnostics switch.
- Version, license, privacy, and attribution information.

### 9.3 Menu bar

The menu-bar controller remains compact:

- Product name and connection state.
- Battery.
- Current mode.
- Quiet, Aware, and discovered custom modes.
- Immersive Audio when supported.
- Reconnect.
- Power Off with confirmation.
- Open Full App.
- Settings.
- Quit.

Advanced mode editing remains in the desktop window.

Closing the desktop window does not terminate the application when menu-bar operation is enabled. Quit terminates the session and process.

### 9.4 Control Center

Version 1 exposes:

- Configurable Set Audio Mode control.
- Cycle Audio Mode control.
- Immersive Audio toggle.
- Reconnect control.

Power Off is intentionally excluded because it is destructive and Control Center may not provide a consistent confirmation experience.

## 10. Visual design

The app uses standard macOS 27 components so the system supplies current Liquid Glass behavior automatically.

Design rules:

- Use native windows, sidebars, toolbars, inspectors, menus, sheets, forms, pickers, toggles, sliders, gauges, and buttons.
- Use SF Symbols for functional icons.
- Use semantic system colors and materials.
- Keep information and editing surfaces on standard content backgrounds.
- Let the system apply Liquid Glass to navigation, controls, and transient surfaces.
- Do not create custom glass cards, fake reflections, heavy bloom, excessive blur, or permanent decorative animation.
- Support light mode, dark mode, increased contrast, reduced transparency, reduced motion, keyboard navigation, and VoiceOver.
- Preserve native active-window, inactive-window, focus-ring, and hover behavior.

The target visual reference is a first-party macOS accessory settings panel, not a branded dashboard.

## 11. App lifecycle and preferences

The onboarding choice controls launch and Dock behavior.

### Menu-bar-first

- Launch as an accessory-style application with no initial desktop window and no Dock icon.
- Keep the menu-bar item visible.
- **Open Full App** switches to regular activation, shows the Dock icon, activates the app, and opens the Overview window.
- Closing the last desktop window returns the app to accessory behavior when the user remains in menu-bar-first mode.

### Desktop-first

- Launch as a regular application.
- Show the Dock icon.
- Activate the app and open the Overview window.
- Closing the window leaves the app running only when the menu-bar item is enabled; otherwise normal app termination behavior applies.

The menu-bar item cannot be disabled while menu-bar-first mode is active and no regular Dock presence is configured. The user must switch to desktop-first before hiding their only persistent access point.

All activation-policy changes use documented public AppKit APIs and must be covered by lifecycle UI tests.

Preferences stored locally:

- Selected CoreBluetooth peripheral identifier.
- App behavior choice.
- Menu-bar visibility and battery-label preference.
- Launch-at-login preference.
- Automatic reconnect preference.
- Developer diagnostics preference.

Headphone modes and audio settings are not duplicated into a persistent app preset database.

## 12. Privacy, security, and App Store compatibility

The initial app remains local-only.

Requirements:

- App Sandbox enabled from the first functional build.
- Bluetooth entitlement only, plus the App Group required by the Control extension.
- No network client entitlement in version 1.
- No private frameworks or undocumented macOS APIs.
- No privileged helper, launch daemon, kernel extension, or background service outside normal app mechanisms.
- No analytics, crash-upload service, account, or cloud storage.
- Use `os.Logger` with privacy annotations.
- Release logs must not expose serial numbers, stable device identifiers, or raw packet payloads by default.
- Debug packet logging is opt-in, local, visibly marked, and excluded from normal release behavior.
- A privacy manifest and clear Bluetooth usage description are included.
- Launch at Login uses the current public ServiceManagement API.

For a public release:

- Include the MIT license and required attribution for any ported code.
- State clearly that the project is unofficial and not affiliated with or endorsed by Bose.
- Do not use Bose logos or imitate official product artwork in the app icon.

## 13. Performance targets

The app is ARM64-only and has no third-party runtime dependencies.

Targets for a release build on an Apple Silicon Mac:

- Effectively zero sustained CPU use while connected and idle.
- No periodic high-frequency polling.
- No continuous animation when the relevant UI is hidden.
- One Bluetooth central and one active headset connection.
- Resident memory target below 50 MB during ordinary menu-bar use.
- Release bundle target below 25 MB excluding symbols and installer packaging.
- Initial state visible within three seconds after the BLE connection and notifications become ready under normal conditions.
- A mode change normally confirmed within two seconds.

These targets are validated with Instruments rather than assumed from implementation language.

## 14. Error handling

Errors are divided into typed categories:

- Permission denied.
- Bluetooth powered off or unavailable.
- Supported device not found.
- Unsupported or ambiguous product identity.
- Unvalidated firmware for advanced writes.
- Connection failed.
- Service or characteristic unavailable.
- Protocol parse failure.
- Headphone-reported BMAP error.
- Command timeout.
- Read-back mismatch.
- Partial multi-field apply.
- Rollback failure.
- Unsupported operation.
- Stale Control Center configuration.

Normal UI presents concise recovery-oriented messages. Developer diagnostics may expose firmware version, function block, function ID, operator, and error code, but raw packet inspection is never part of the default interface.

No interface should silently ignore a failed command or display unconfirmed settings as final.

## 15. Testing strategy

### 15.1 Protocol tests

`HeadphoneCore` unit tests cover:

- Packet serialization and parsing.
- Operator and error handling.
- Segmentation and reassembly.
- Multi-packet notifications.
- Incomplete, malformed, and out-of-order data.
- Product identity and firmware parsing.
- Battery parsing.
- Capability parsing.
- Mode-list and mode-configuration parsing.
- Standby parsing.
- Spatial-audio parsing.
- Preservation of unknown mode fields.
- Known sanitized fixtures captured from the physical headset.

### 15.2 Transport and session tests

A fake `HeadphoneTransport` covers:

- Every connection-state transition.
- Candidate-device validation.
- Initial state loading.
- Command serialization.
- Write failure.
- Timeout.
- Disconnect during a command.
- Reconnection and backoff.
- Rejected properties.
- Read-back mismatch.
- Partial multi-field apply.
- Successful and failed rollback.
- Superseded and coalesced commands.
- Sleep and wake behavior.
- Refresh coalescing and rate limiting.
- Control Center requests while connected and disconnected.

CoreBluetooth adapter tests verify event translation and confinement without duplicating session policy tests.

### 15.3 UI and accessibility tests

Tests cover:

- Onboarding.
- Device selection and unsupported-device rejection.
- Desktop-first and menu-bar-first launch behavior.
- Dock and menu-bar transitions.
- Prevention of an inaccessible no-Dock/no-menu configuration.
- Mode staging, Apply, Cancel, partial apply, and rollback reporting.
- Settings persistence.
- Power-off confirmation.
- Keyboard navigation.
- VoiceOver labels.
- Increased contrast.
- Reduced transparency.
- Reduced motion.

### 15.4 Physical-device release checklist

Every release candidate is tested with the target headset for:

- Fresh pairing and first launch.
- Permission denial and recovery.
- Product identity and firmware reporting.
- Cold launch.
- Automatic reconnection.
- Quiet, Aware, and custom-mode switching.
- Immersive Audio changes.
- Every advanced property retained for version 1.
- Multi-field apply and rollback behavior.
- Standby timer.
- Power Off.
- Menu-bar operation.
- Desktop-window operation.
- Sleep and wake.
- Control Center controls.
- Operation after the Bose app was recently used.
- Headphones becoming unavailable mid-command.

### 15.5 Performance and energy tests

Use Instruments to verify:

- Idle CPU.
- Memory use and leaks.
- Energy impact.
- Unexpected timers and wakeups.
- Bluetooth scan duration and duty cycle.
- Retained view models, tasks, and CoreBluetooth delegates.

## 16. Feasibility gates

Implementation planning begins with two technical spikes. They are part of the plan, not optional follow-up work.

### Gate 1: Advanced mode writing

Using the physical QC Ultra Gen 1, verify the exact BMAP read and write behavior for each candidate advanced property:

- ANC/CNC level.
- Automatic noise-control behavior.
- Wind filtering.
- Favorite status.
- Mode name.
- ANC toggle behavior.
- Immersive Audio behavior.

A property remains in version 1 only if it can be:

1. Read reliably.
2. Changed using a deterministic packet.
3. Read back and matched.
4. Restored safely.
5. Used repeatedly without corrupting other mode fields.

Anything that fails these conditions is omitted rather than approximated.

### Gate 2: Control Center execution

Build a minimal Control extension and App Intent path that proves behavior when the app is:

- Running with a visible window.
- Running with no visible window.
- Running as a menu-bar utility.
- Not currently running.
- Disconnected from the headphones.

The spike must establish a safe lifecycle contract for main-process execution, headless activation, timeout reporting, and fallback to opening the app. The production Control Center architecture follows measured macOS behavior.

## 17. Release strategy

### Personal alpha

- Development signing.
- Direct local installation.
- Physical-headset protocol validation.
- No updater.

### GitHub release

- Release ARM64 build.
- Signed and notarized when distributed to others.
- ZIP or DMG packaging.
- Manual update installation.
- Changelog and known-supported firmware/device statement.

### Future Mac App Store

The same codebase should be submittable after adding store metadata, review documentation, and final signing configuration. The application must not require a daemon removal, sandbox rewrite, transport replacement, or extension redesign to reach that stage.

## 18. Acceptance criteria for version 1

Version 1 is complete when:

1. A first-time user can grant permission, select and validate a QC Ultra Gen 1, choose desktop-first or menu-bar-first behavior, and connect without terminal use.
2. Desktop and menu-bar interfaces display one consistent, confirmed state.
3. Battery, current mode, mode switching, Immersive Audio when supported, standby, reconnect, and power-off work reliably.
4. Every included advanced mode property passes the validation gate and uses read-after-write verification.
5. Multi-field Apply reports confirmed success, confirmed rollback, or the actual partial state; it never hides uncertainty.
6. Control Center controls execute safely or provide a clear open-app fallback.
7. The app survives disconnects, sleep/wake, and headset unavailability without hanging or spinning.
8. Protocol, transport, session, UI, accessibility, and physical-device release checks pass.
9. The release build is sandboxed, local-only, ARM64, and free of a Rust daemon or third-party runtime dependency.
10. Idle performance meets the defined CPU, memory, and wakeup targets or deviations are documented before release.
11. The project can be prepared for a Mac App Store submission without an architectural rewrite.

## 19. Decision record

| Decision | Selected option | Reason |
|---|---|---|
| Hardware scope | QC Ultra Gen 1 only | Smallest reliable protocol and test surface |
| Default experience | User chooses during onboarding | Supports both desktop and menu-bar workflows |
| Distribution | Personal/GitHub first, store-compatible | Avoids premature submission work without creating migration debt |
| Feature scope | Essential controls plus advanced editing | Useful daily controller without turning the app into a protocol lab |
| Preset ownership | Headphones only | Avoids synchronization conflicts and duplicated state |
| Runtime architecture | Pure native Swift | Lowest integration complexity and best macOS fit |
| Bluetooth boundary | Delegate adapter plus session actor | Confines Apple callback objects and keeps domain state testable |
| Process model | Main app owns one BLE session | Prevents competing connections and inconsistent state |
| Platform | macOS 27+, Apple Silicon | Enables current native design and removes legacy compatibility burden |
| Mode editing | Staged, Apply, read back, best-effort rollback | Prevents UI drift without pretending the headset supports atomic writes |
| Control Center Power Off | Excluded | Destructive action lacks a dependable confirmation surface |

Once approved by the user, this design becomes the authoritative input to the implementation plan.