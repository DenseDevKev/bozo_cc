# QC Ultra macOS Controller — Product and Architecture Design

**Date:** 2026-08-29  
**Status:** Approved for implementation planning  
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
- **Implementation:** Native Swift and SwiftUI, with targeted AppKit use where macOS behavior requires it.
- **Bluetooth:** One direct CoreBluetooth session owned by the main app process.
- **Primary experience:** On first launch, the user chooses desktop-first or menu-bar-first behavior. Menu-bar-first is preselected.
- **Distribution:** Personal build or GitHub Release first; future Mac App Store compatibility is preserved.
- **Version 1 feature level:** Essential controls plus verified advanced audio-mode editing.
- **Mode ownership:** The headphones are the sole source of truth. The app will not maintain a separate preset library.
- **Control Center:** Quick, system-rendered controls only. Power Off is excluded from Control Center.
- **Editing behavior:** Advanced changes are staged and applied transactionally, then read back from the headphones before the UI reports success.
- **Runtime dependencies:** No third-party runtime libraries, no embedded browser, no Node process, no Rust daemon, and no local server.

## 3. Goals

### 3.1 User goals

The application should let a non-technical user:

- Connect to a paired QC Ultra headset.
- See connection state, battery level, remaining play time when available, and the current audio mode.
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
        ├── ControlsExtension/
        ├── Packages/
        │   └── HeadphoneCore/
        ├── Tests/
        └── Resources/
```

The release app will not link against or launch any Rust binary. The Rust code may be used to cross-check packet behavior and generate test fixtures during development.

Working identifiers:

- Main app: `dev.densedevkev.qcultracontrol`
- Control extension: `dev.densedevkev.qcultracontrol.controls`
- App Group: `group.dev.densedevkev.qcultracontrol`

The user-facing name and branding may change before a public release without changing the architecture.

## 6. Architecture

### 6.1 High-level structure

```text
Desktop Window ─┐
Menu Bar ───────┼──> Application Model ──> HeadphoneSession actor
Settings ───────┘                              │
                                                v
                                      HeadphoneCore package
                                                │
                                                v
                                         CoreBluetooth
                                                │
                                                v
                                       QC Ultra Gen 1

Control Center Extension
    ├── reads a small shared state snapshot
    └── invokes App Intents in the main app process
```

The main application process is the only component that may own a Bluetooth connection. The desktop window, menu bar, settings, and App Intents all act through the same `HeadphoneSession`.

### 6.2 `HeadphoneCore`

`HeadphoneCore` is an internal Swift package with no SwiftUI, AppKit, UserDefaults, WidgetKit, or application-lifecycle dependencies.

Responsibilities:

- BMAP packet encoding and decoding.
- BLE framing, segmentation, and reassembly.
- Typed query and command builders.
- Typed response parsers.
- Bose error decoding.
- Capability models.
- Audio-mode models.
- Protocol fixtures and deterministic unit tests.
- A transport abstraction used by session tests.

Representative public types:

```swift
struct BMAPPacket
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

### 6.3 `HeadphoneSession`

`HeadphoneSession` is a long-lived Swift actor that owns all mutable Bluetooth and device state.

Responsibilities:

- CoreBluetooth central lifecycle.
- Supported-device discovery and selection.
- Peripheral connection and service discovery.
- Notification subscription.
- BMAP transport.
- Initial capability and state loading.
- Serialized command execution.
- Timeouts and cancellation.
- Read-after-write verification.
- Reconnection and bounded backoff.
- Sleep and wake handling.
- Publishing authoritative state to the app model.
- Persisting only the selected peripheral identifier and user preferences.

Only one command that changes headset state may be in flight at a time. Read-only refreshes may be coalesced, but they must not race with a state-changing transaction.

### 6.4 Application model

A `@MainActor` application model exposes session state to SwiftUI and maps domain errors into presentation state.

It does not contain Bluetooth logic. It coordinates:

- Navigation state.
- Sheets and confirmations.
- Staged mode edits.
- Pending-action indicators.
- User preferences.
- Shared state snapshot updates for the Control extension.

Every interface observes this same model or a read-only projection of it. No interface maintains a separate copy of authoritative headphone state.

### 6.5 Control Center extension and App Intents

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
loadingState
connected
reconnecting
unavailable
failed
```

State transitions are explicit and testable. UI surfaces display friendly labels, while diagnostics preserve typed causes.

### 7.2 Initial connection flow

```text
Bluetooth permission granted
    -> scan for the selected compatible peripheral
    -> connect
    -> discover BMAP service and characteristics
    -> subscribe to notifications
    -> query capabilities
    -> query device name, battery, current mode, modes, standby, and spatial state
    -> publish connected state
```

The app must not consider the session fully connected until notifications are active and the initial state load has completed or reached a defined partial-state timeout.

### 7.3 Reconnection

Unexpected disconnects use bounded backoff:

```text
1 second -> 2 seconds -> 5 seconds -> 10 seconds -> 30 seconds maximum
```

The retry counter resets after a stable connection. Scanning pauses while the Mac sleeps and resumes after wake. A manual Reconnect action cancels the existing retry timer and begins a fresh attempt immediately.

The app avoids continuous high-duty scanning. When the selected device remains unavailable, it reduces scan frequency and exposes a clear disconnected state.

### 7.4 Command transactions

Every state-changing command follows the same transaction:

```text
validate capability and connection
    -> enqueue command
    -> write BMAP packet
    -> wait for transport acknowledgement when available
    -> query the changed property
    -> compare returned state with requested state
    -> publish success or typed failure
```

The UI may show an optimistic pending selection, but it must visually distinguish pending state from confirmed state. If verification fails, the UI returns to the last confirmed value and presents an error.

A command is not successful merely because bytes were queued for Bluetooth transmission.

### 7.5 Timeouts and cancellation

- Each command has an explicit timeout appropriate to the operation.
- A disconnect cancels commands that require the old connection.
- A superseding user action may cancel an older queued action that has not started.
- Power Off ends the session immediately after the command is accepted and does not wait for a read-back that cannot occur after shutdown.
- Repeated identical commands are coalesced.

## 8. Capability-driven behavior

The app must not hard-code that every QC Ultra exposes every property. On connection, it builds a `HeadphoneCapabilities` model from verified protocol responses.

The UI follows these rules:

- Unsupported properties are hidden.
- Read-only properties are displayed but not editable.
- Writable properties are enabled only after successful capability validation.
- Unknown flags are preserved when rewriting a mode configuration.
- A mode edit writes only fields that changed.
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
3. **Select Headphones** — lists compatible QC Ultra Gen 1 devices and stores the selected peripheral identifier.
4. **Choose App Behavior** — menu-bar-first is preselected; desktop-first is the alternative.
5. **Optional Integration** — launch at login, battery in menu bar, and instructions for adding Control Center controls.

Unsupported Bose products are shown as unsupported or omitted; the app does not attempt uncertain compatibility.

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
- Edits are staged locally.
- Apply performs a verified transaction.
- Cancel discards staged changes.
- A failed or partially rejected transaction restores the confirmed headset state and explains what failed.

There is no app-only preset library.

#### Settings

- Desktop-first or menu-bar-first behavior.
- Show or hide the menu-bar item.
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

The onboarding choice controls launch behavior:

- **Menu-bar-first:** the app launches without presenting the main window and keeps a menu-bar item available.
- **Desktop-first:** the app activates normally and opens the Overview window.

The choice is changeable later. The app may adjust Dock visibility using public macOS APIs, but it must always provide a discoverable way to reopen the full window.

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
- Connection failed.
- Service or characteristic unavailable.
- Protocol parse failure.
- Headphone-reported BMAP error.
- Command timeout.
- Read-back mismatch.
- Unsupported operation.
- Stale Control Center configuration.

Normal UI presents concise recovery-oriented messages. Developer diagnostics may expose function block, function ID, operator, and error code, but raw packet inspection is never part of the default interface.

No interface should silently ignore a failed command or display unconfirmed settings as final.

## 15. Testing strategy

### 15.1 Protocol tests

`HeadphoneCore` unit tests cover:

- Packet serialization and parsing.
- Operator and error handling.
- Segmentation and reassembly.
- Multi-packet notifications.
- Incomplete, malformed, and out-of-order data.
- Battery parsing.
- Capability parsing.
- Mode-list and mode-configuration parsing.
- Standby parsing.
- Spatial-audio parsing.
- Known sanitized fixtures captured from the physical headset.

### 15.2 Session tests

A fake `HeadphoneTransport` covers:

- Every connection-state transition.
- Initial state loading.
- Command serialization.
- Write failure.
- Timeout.
- Disconnect during a command.
- Reconnection and backoff.
- Rejected properties.
- Read-back mismatch.
- Superseded and coalesced commands.
- Sleep and wake behavior.
- Control Center requests while connected and disconnected.

### 15.3 UI and accessibility tests

Tests cover:

- Onboarding.
- Device selection.
- Desktop-first and menu-bar-first launch behavior.
- Mode staging, Apply, Cancel, and failure restoration.
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
- Cold launch.
- Automatic reconnection.
- Quiet, Aware, and custom-mode switching.
- Immersive Audio changes.
- Every advanced property retained for version 1.
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

1. A first-time user can grant permission, select a QC Ultra Gen 1, choose desktop-first or menu-bar-first behavior, and connect without terminal use.
2. Desktop and menu-bar interfaces display one consistent, confirmed state.
3. Battery, current mode, mode switching, Immersive Audio when supported, standby, reconnect, and power-off work reliably.
4. Every included advanced mode property passes the validation gate and uses read-after-write verification.
5. Control Center controls execute safely or provide a clear open-app fallback.
6. The app survives disconnects, sleep/wake, and headset unavailability without hanging or spinning.
7. Protocol, session, UI, accessibility, and physical-device release checks pass.
8. The release build is sandboxed, local-only, ARM64, and free of a Rust daemon or third-party runtime dependency.
9. Idle performance meets the defined CPU, memory, and wakeup targets or deviations are documented before release.
10. The project can be prepared for a Mac App Store submission without an architectural rewrite.

## 19. Decision record

| Decision | Selected option | Reason |
|---|---|---|
| Hardware scope | QC Ultra Gen 1 only | Smallest reliable protocol and test surface |
| Default experience | User chooses during onboarding | Supports both desktop and menu-bar workflows |
| Distribution | Personal/GitHub first, store-compatible | Avoids premature submission work without creating migration debt |
| Feature scope | Essential controls plus advanced editing | Useful daily controller without turning the app into a protocol lab |
| Preset ownership | Headphones only | Avoids synchronization conflicts and duplicated state |
| Runtime architecture | Pure native Swift | Lowest integration complexity and best macOS fit |
| Process model | Main app owns one BLE session | Prevents competing connections and inconsistent state |
| Platform | macOS 27+, Apple Silicon | Enables current native design and removes legacy compatibility burden |
| Mode editing | Staged, Apply, then read back | Prevents UI drift and excessive Bluetooth writes |
| Control Center Power Off | Excluded | Destructive action lacks a dependable confirmation surface |

This design is the authoritative input to the implementation plan.