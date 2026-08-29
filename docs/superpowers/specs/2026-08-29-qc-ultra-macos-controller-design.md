# Native QC Ultra macOS Controller — Design Specification

**Date:** 2026-08-29  
**Status:** Approved design, pending written-spec review  
**Repository:** `DenseDevKev/bozo_cc`  
**Design branch:** `design/qc-ultra-macos-app`

## 1. Executive summary

Build a lightweight, Apple-silicon-only macOS 27 application for controlling **Bose QuietComfort Ultra Headphones Gen 1** without requiring a terminal or the Bose companion app for everyday controls.

The application will be fully native Swift. It will provide:

- A conventional desktop window.
- An optional menu-bar controller.
- Optional macOS Control Center controls through WidgetKit and App Intents.
- Direct communication with the headphones through CoreBluetooth and the reverse-engineered Bose Message Access Protocol (BMAP).
- Advanced editing of headphone-stored audio modes, limited to settings that are proven writable and can be read back successfully from the physical device.

The app will not install or modify headphone firmware. It is a controller for supported BMAP settings.

The first distribution target is personal use, with a possible GitHub release later. The project must remain compatible with a future Mac App Store submission: App Sandbox stays enabled, only public Apple frameworks are used, privileges are minimal, and the Control Center extension remains properly isolated.

The internal project name is **`QCUltraController`**. User-facing branding may change before a public release without changing this architecture.

## 2. Decisions already approved

The following decisions are fixed for version 1:

- Supported hardware: Bose QuietComfort Ultra Headphones Gen 1 only.
- Unsupported in v1: earbuds, QC45, standard QuietComfort, NC 700, Gen 2 hardware, speakers, and arbitrary BMAP devices.
- Platform: macOS 27 or newer.
- CPU architecture: Apple silicon (`arm64`) only.
- Implementation: native Swift, SwiftUI, targeted AppKit integration, and CoreBluetooth.
- Runtime architecture: one main app process and one small WidgetKit/App Intents control extension.
- No Rust daemon, Unix socket, embedded browser, Electron, Node.js, local HTTP service, or privileged helper.
- The headphones are the source of truth for modes and settings.
- No app-only preset library in v1.
- First-launch onboarding asks whether the app should be desktop-first or menu-bar-first; menu-bar-first is preselected.
- Distribution begins as personal development builds and may later use GitHub Releases.
- The codebase is designed for App Store compatibility from the beginning.
- Version 1 includes essential controls plus advanced mode editing.
- Advanced edits are staged and applied explicitly, then verified by reading the state back from the headphones.
- Power Off is available in the desktop and menu-bar interfaces, but not as a one-tap Control Center action.

## 3. Problem statement

The existing `bozo` project proves that the QC Ultra can be controlled over BMAP, but its primary interface is terminal-based and its Rust architecture includes a background daemon and Unix-socket IPC. That is appropriate for a command-line tool, but it is not the right product architecture for a Mac application intended to feel native.

The existing `bozo-bar` project proves that a direct Swift/CoreBluetooth approach is practical. It is a useful reference implementation, but its current menu-bar-only structure and large Bluetooth manager should not define the architecture of the finished desktop app.

The finished product needs to make common headphone controls discoverable to non-terminal users while remaining small, fast, reliable, private, and consistent with macOS 27 interaction and visual conventions.

## 4. Product goals

### 4.1 Primary goals

1. Make all verified everyday QC Ultra controls accessible from a native Mac interface.
2. Provide desktop, menu-bar, and Control Center entry points without creating competing Bluetooth sessions.
3. Match macOS behavior and visual hierarchy by using system components rather than imitating Apple styling manually.
4. Remain nearly idle when the user is not interacting with the app.
5. Treat headphone responses as authoritative and never present an unconfirmed setting as successfully applied.
6. Preserve a clean path to signing, notarization, and a later Mac App Store submission.
7. Keep protocol code isolated and thoroughly testable without physical hardware.

### 4.2 Success criteria

Version 1 is successful when a user can:

- Install or build the app without installing Rust or using Terminal for normal operation.
- Select one compatible QC Ultra Gen 1 device during onboarding.
- Reconnect automatically when those headphones become available.
- View connection state, battery level, estimated remaining playback time when reported, and the active audio mode.
- Switch among Quiet, Aware, and headphone-stored custom modes.
- Control verified Immersive Audio behavior.
- Set the standby timer.
- Edit verified advanced properties of headphone-stored modes and confirm the final values through read-back.
- Use the same authoritative state from the desktop window and menu-bar interface.
- Add supported controls to Control Center and invoke them without a second BLE connection.
- Close the main window while continuing to use menu-bar controls when menu-bar mode is enabled.
- Sleep and wake the Mac without leaving the application in a permanently stale or reconnecting state.

## 5. Non-goals

Version 1 will not:

- Replace, patch, downgrade, upload, or otherwise alter headphone firmware.
- Support arbitrary Bose devices through best-effort detection.
- Reproduce the entire Bose companion application.
- Manage Bose accounts, cloud services, analytics, or firmware updates.
- Provide a local preset library independent of the headphone modes.
- Expose raw packet injection in the normal interface.
- Provide a general-purpose Bluetooth inspector.
- Ship a third-party automatic updater.
- Include network-dependent features.
- Include Intel (`x86_64`) compatibility.
- Guarantee simultaneous control with the Bose app on another device.
- Present guessed or undocumented settings as supported.

## 6. Repository and project strategy

The native app will initially live in this fork so the existing Rust protocol implementation and documentation remain nearby as reference material. It will be isolated from the Rust workspace and will not link against Rust at runtime.

Proposed layout:

```text
apps/QCUltraController/
├── QCUltraController.xcodeproj
├── Config/
│   ├── App.entitlements
│   ├── Controls.entitlements
│   ├── Info.plist
│   └── PrivacyInfo.xcprivacy
├── Packages/
│   └── HeadphoneCore/
│       ├── Package.swift
│       ├── Sources/HeadphoneCore/
│       └── Tests/HeadphoneCoreTests/
├── Sources/
│   ├── App/
│   ├── Session/
│   ├── Bluetooth/
│   ├── Persistence/
│   ├── Intents/
│   └── UI/
├── ControlsExtension/
├── Tests/
│   ├── SessionTests/
│   ├── IntegrationTests/
│   ├── UITests/
│   └── Fixtures/
└── Scripts/
    ├── build-release.sh
    └── verify-release.sh
```

The existing Rust crates remain unchanged except for protocol-documentation corrections or test fixtures that are directly useful to both implementations. The native app can later be split into a standalone repository without restructuring its source tree.

Development identifiers:

- Main app: `dev.densedevkev.qcultra`
- Control extension: `dev.densedevkev.qcultra.controls`
- Shared App Group: `group.dev.densedevkev.qcultra`

These are stable development identifiers. A future public release may use a different reverse-DNS prefix only as an intentional migration with corresponding signing and App Group changes.

## 7. High-level architecture

```text
┌────────────────────────────────────────────────────┐
│ Main macOS application                             │
│                                                    │
│  Desktop Window   MenuBarExtra   Settings          │
│         \              |             /             │
│          └──────── AppModel ─────────┘              │
│                       │                            │
│                HeadphoneSession actor              │
│             ┌─────────┼──────────┐                 │
│             │         │          │                 │
│       command queue  state   reconnect policy      │
│                       │                            │
│                BluetoothTransport                  │
│                       │                            │
│                  CoreBluetooth                     │
└───────────────────────┬────────────────────────────┘
                        │ BMAP over BLE
                        ▼
              Bose QC Ultra Gen 1

┌────────────────────────────────────────────────────┐
│ WidgetKit / App Intents control extension          │
│                                                    │
│  Reads versioned cached snapshot from App Group    │
│  Invokes intent routed to the main application     │
└────────────────────────────────────────────────────┘
```

### 7.1 Architectural rule

The main app is the only component allowed to own a live CoreBluetooth connection. Desktop views, menu-bar views, App Intents, and Control Center controls must all operate through one `HeadphoneSession`.

The control extension may read cached state and describe actions, but it must not create its own `CBCentralManager` or attempt a second BMAP session.

## 8. Core components

### 8.1 `HeadphoneCore`

`HeadphoneCore` is a small, UI-independent Swift package. It contains:

- BMAP packet models.
- Operator and function-block definitions.
- Packet encoding and decoding.
- BLE segmentation and reassembly.
- Typed query and command builders.
- Response parsers.
- QC Ultra capability models.
- Audio-mode models.
- Protocol error models.
- Deterministic fixtures and unit tests.

It must not import SwiftUI, AppKit, CoreBluetooth, WidgetKit, ServiceManagement, or UserDefaults.

The package must accept raw byte sequences and return typed values or explicit parsing errors. Unknown response fields must be preserved where practical or logged in diagnostics rather than causing unsafe assumptions.

### 8.2 `BluetoothTransport`

`BluetoothTransport` is the CoreBluetooth adapter. It is responsible only for:

- Creating and owning `CBCentralManager`.
- Scanning for the BMAP service.
- Connecting to a chosen `CBPeripheral`.
- Discovering the secure and unsecure BMAP characteristics.
- Selecting the supported characteristic according to the validated transport policy.
- Subscribing to notifications.
- Writing segmented BMAP packets.
- Emitting raw reassembled packets and transport events.
- Reporting actual write failures and disconnects.

CoreBluetooth delegate callbacks will run on one dedicated serial queue and bridge into Swift concurrency. The UI must never receive CoreBluetooth delegate objects directly.

### 8.3 `HeadphoneSession`

`HeadphoneSession` is a long-lived Swift actor and the sole authority for the selected headphone session. It owns:

- Connection lifecycle.
- Selected-device identity.
- Model validation.
- Initial capability and state loading.
- Command serialization.
- Request timeout handling.
- Response correlation where the protocol permits it.
- Automatic reconnect and bounded backoff.
- Sleep/wake recovery.
- Cached authoritative `HeadphoneSnapshot`.
- Mode-draft validation and apply operations.
- Emission of state snapshots to `AppModel`.

It must not mutate UI state directly.

### 8.4 `AppModel`

`AppModel` is `@MainActor` and observable by SwiftUI. It translates session snapshots into presentation state and exposes user-level actions.

Responsibilities:

- Present current connection and device state.
- Track pending UI operations.
- Expose onboarding progress and preferences.
- Manage the currently selected mode draft.
- Convert technical errors into plain-language messages.
- Write versioned state snapshots to the shared App Group for Control Center.

It must not encode BMAP packets or own Bluetooth objects.

### 8.5 Control extension

The WidgetKit/App Intents extension provides system controls and configuration entities. It:

- Reads the last versioned `SharedHeadphoneSnapshot` from the App Group.
- Displays last-known mode, connection, and battery state where supported by the system template.
- Provides dynamic mode choices from the cached headphone-stored mode list.
- Invokes App Intents that route execution to the main application.
- Requests a timeline/control refresh after an action finishes.

It does not contain protocol implementation beyond shared value types needed to describe an intent.

## 9. Domain model

### 9.1 Authoritative snapshot

`HeadphoneSnapshot` is immutable and versioned in memory. It contains:

- Session revision.
- Connection state.
- Selected peripheral identifier.
- Product name.
- Verified model family.
- Firmware version when available.
- Battery components.
- Active mode index.
- Full discovered mode list.
- Device-level capabilities.
- Standby timer.
- Immersive Audio state when supported.
- Last successful device response date.
- Last transport error summary.

Every state change produces a new snapshot. Views never assemble their own partial truth from separate properties.

### 9.2 Mode representation

Each `AudioMode` contains:

- Device mode index.
- Device-provided name.
- Prompt identifier when reported.
- Favorite state when reported.
- User-configurable state.
- User-configured state.
- Capability flags for each editable property.
- Current ANC/CNC level when reported.
- Automatic ANC state when reported.
- Immersive Audio behavior when reported.
- Wind-blocking state when reported.
- ANC enable state when reported.
- Unknown trailing bytes needed for diagnostics and future parser upgrades.

### 9.3 Mode draft

Opening the editor creates a `ModeDraft` from one `AudioMode` plus the source session revision. The draft records only user changes and remains local until Apply is pressed.

If the authoritative mode changes before Apply—for example, because the Bose app or a hardware action changed it—the editor must not silently overwrite the new device state. It displays a conflict and offers:

- Reload from headphones and discard the draft.
- Review the changed fields before creating a new draft.

Version 1 will not offer a blind force-overwrite button.

## 10. Device discovery and compatibility validation

### 10.1 Discovery

On first launch, the app scans for peripherals advertising the validated Bose BMAP service. It presents compatible candidates with:

- Local name.
- Signal strength.
- Connection status when known.

The user selects one device. Version 1 stores one chosen CoreBluetooth peripheral identifier.

### 10.2 Model validation

A device is not considered supported merely because it exposes BMAP. After connection, the app queries product information and validates that the device matches the QC Ultra Gen 1 support profile.

If validation fails, the app disconnects and presents an unsupported-device message. It does not continue in an experimental mode.

The exact validation signature—product name, product identifier, capability combination, or other stable fields—must be established during the hardware feasibility work and covered by fixtures.

### 10.3 Remembered device

The selected CoreBluetooth identifier is stored in standard app preferences. On later launches, the app first attempts to retrieve and reconnect to that peripheral. If it is unavailable, the app scans with bounded duty rather than continuously.

“Forget Headphones” removes the identifier, clears the shared control snapshot, terminates the current session, and returns to device selection.

## 11. Connection state machine

The public session state is explicit:

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

Allowed transitions are implemented and tested as a state machine rather than inferred from unrelated booleans.

### 11.1 Automatic reconnect

Unexpected disconnections use bounded exponential backoff:

```text
1 second → 2 seconds → 5 seconds → 10 seconds → 30 seconds maximum
```

Backoff resets after a stable successful connection. Reconnect attempts stop or pause when:

- Bluetooth is powered off.
- Permission is denied.
- The Mac is asleep.
- The user explicitly forgets or disconnects the device.
- The application is terminating.

The app resumes connection work after wake and after Bluetooth becomes available. It must not maintain a tight scan loop.

### 11.2 Sleep and wake

The app observes public workspace/power notifications. Before sleep it marks the session suspended and cancels obsolete command timers. After wake it revalidates CoreBluetooth state and reconnects if the selected device should be active.

### 11.3 Manual reconnect

Manual Reconnect cancels the current attempt, clears transient transport state, preserves the selected device, and immediately begins a fresh bounded connection attempt. It must perform real work rather than acknowledge a no-op.

## 12. Command and response semantics

### 12.1 Serialized commands

All writes pass through one actor-owned queue. Only one state-changing BMAP operation may be in flight unless protocol testing proves a specific operation can safely overlap.

Each operation has:

- A unique local identifier.
- A user-level description.
- One or more BMAP packets.
- A timeout.
- An expected response or read-back query.
- A cancellation policy.

### 12.2 Success definition

A command is not successful merely because CoreBluetooth accepted a write.

For user-visible settings, success requires:

1. The write was accepted by the transport.
2. No immediate BMAP error invalidated it.
3. The app queried the relevant state again.
4. The returned value matches the requested value or a documented normalized equivalent.

Only then does the UI show the operation as completed.

### 12.3 Optimistic UI

Mode-selection buttons may show a brief pending state, but the authoritative selection remains tied to the read-back response. If the device rejects or ignores the change, the UI returns to the reported mode and shows a concise error.

Advanced mode editing will not optimistically replace the authoritative mode.

### 12.4 Partial failures

Applying a multi-property mode draft may require several BMAP writes and is not assumed to be atomic on the headphones.

If a later property fails:

- Stop sending remaining writes whose prerequisites are no longer valid.
- Re-query the complete mode configuration.
- Display the actual resulting state.
- Identify which requested fields were not applied.
- Do not attempt an unverified automatic rollback.

A rollback may be added only if physical-device testing proves every affected property can be restored safely.

### 12.5 Disconnect during operation

A disconnect cancels operations that cannot be safely resumed. After reconnection, the app re-queries state instead of replaying stale writes automatically. The user may retry from the confirmed state.

## 13. Capability discovery and advanced mode editing

### 13.1 Capability-driven UI

The app queries AudioModes capabilities and the complete list of valid mode indices. It must not rely on a hard-coded `0..<10` probe in the finished implementation.

For each mode, the editor shows a field only when both conditions are true:

1. The headphone response marks the property as configurable or otherwise supported.
2. The property’s write packet and read-back behavior have been validated on a physical QC Ultra Gen 1.

Unsupported or unverified fields are omitted rather than exposed as unreliable controls.

### 13.2 Candidate advanced properties

The feasibility phase will evaluate:

- Mode name.
- Favorite status.
- ANC/CNC strength.
- Automatic ANC behavior.
- ANC enable/disable.
- Wind blocking.
- Immersive Audio behavior associated with a mode.

The release editor must include at least **ANC/CNC strength and one additional verified advanced property** beyond ordinary mode switching. If that threshold cannot be met safely, the advanced-editor scope must be reviewed before calling the build version 1.

### 13.3 Apply flow

1. User selects a headphone-stored mode.
2. App creates a draft from the latest authoritative mode and revision.
3. User changes supported fields.
4. Apply remains disabled when the draft is unchanged or locally invalid.
5. On Apply, the app checks for a source-revision conflict.
6. The session writes changed fields in a tested order.
7. The session queries the complete mode configuration.
8. The UI displays only the values returned by the headphones.
9. The draft closes on complete success or remains open with a reconciled error state after partial failure.

Cancel discards the draft without sending packets.

## 14. User experience

## 14.1 First-launch onboarding

Onboarding is short and functional:

1. **Welcome**
   - Explains direct local Bluetooth control.
   - States that no Bose account or cloud service is used.
   - States that this is not firmware replacement.

2. **Bluetooth Permission**
   - Triggers the system permission request.
   - Provides a recovery path to System Settings if access is denied.

3. **Select Headphones**
   - Displays discovered candidates.
   - Connects and validates QC Ultra Gen 1 compatibility.
   - Saves the selected device only after validation succeeds.

4. **Choose App Behavior**
   - Menu-bar-first is preselected.
   - Desktop-first is available.
   - The preference remains editable later.

5. **Optional System Integration**
   - Launch at login.
   - Show menu-bar item.
   - Show battery percentage beside the menu-bar icon.
   - Explain how to add the provided controls to Control Center.

Completion opens the appropriate primary interface.

## 14.2 Desktop window

The main window uses `NavigationSplitView` and standard macOS navigation. It has three destinations.

### Overview

- Product name.
- Connection state.
- Battery percentage and remaining time when reported.
- Current audio mode.
- Quick mode selection.
- Immersive Audio selector when supported.
- Standby timer.
- Reconnect action.
- Power Off action with confirmation.
- Last successful update time when cached state may be stale.

### Modes

- Lists modes in the order reported by the headphones.
- Shows the active and favorite indicators where available.
- Opens an inspector/editor for one mode.
- Uses native controls appropriate to each verified property.
- Stages edits until Apply.
- Shows conflict, validation, pending, partial-failure, and confirmed states clearly.

### Settings

- Desktop-first or menu-bar-first.
- Show or hide menu-bar item.
- Menu-bar icon only or icon plus battery percentage.
- Launch at login through `SMAppService`.
- Automatic reconnect.
- Forget selected headphones.
- Restore interface preferences.
- About, version, privacy, license, attribution, and non-affiliation text.
- Hidden developer diagnostics activation for troubleshooting builds.

## 14.3 Desktop-first and menu-bar-first behavior

### Desktop-first

- Application activation policy is regular.
- The app appears in the Dock and app switcher.
- The main window opens on launch.
- The menu-bar item follows its independent visibility setting.

### Menu-bar-first

- The app launches as an accessory-style utility using public AppKit activation-policy APIs.
- It normally remains out of the Dock when no main window is open.
- “Open Full App” changes activation behavior as needed and opens the window.
- Closing the final main window returns the app to accessory behavior when the menu-bar item remains enabled.
- Quit fully terminates the app and Bluetooth session.

The app must never enter a configuration where both the Dock presence and menu-bar item are disabled without an explicit recovery path. Settings prevents that invalid combination.

## 14.4 Menu-bar interface

The compact menu-bar window contains:

- Device name and connection status.
- Battery state.
- Current mode.
- Quiet, Aware, and discovered custom modes.
- Immersive Audio control when supported.
- Reconnect.
- Power Off with confirmation.
- Open Full App.
- Settings.
- Quit.

Advanced mode editing remains in the desktop window.

## 14.5 Visual system

The app relies on macOS 27 system design rather than custom glass effects:

- Native windows, sidebars, toolbars, sheets, menus, forms, pickers, toggles, gauges, and buttons.
- SF Symbols for functional iconography.
- System typography and semantic colors.
- Liquid Glass where macOS applies it naturally to navigation and controls.
- Normal content backgrounds for information and editing surfaces.
- No custom “glass cards,” fake reflections, excessive blur, or permanent decorative animation.

The interface must support:

- Light and dark appearances.
- Increased contrast.
- Reduced transparency.
- Reduced motion.
- Full keyboard navigation.
- VoiceOver labels, values, and action descriptions.

## 15. Control Center and App Intents

### 15.1 Version 1 controls

- **Set Audio Mode** — configurable for one headphone-stored mode.
- **Cycle Audio Mode**.
- **Immersive Audio** toggle when supported.
- **Reconnect Headphones**.

Power Off is excluded from Control Center because it is destructive and a system control may not provide an appropriate confirmation experience.

### 15.2 Cached presentation state

The control extension displays a versioned shared snapshot containing only:

- Whether a device is configured.
- Last-known connection state.
- Product display name.
- Battery percentage.
- Current mode.
- Configurable mode entities.
- Immersive Audio state.
- Snapshot timestamp.

A stale timestamp is represented honestly; the extension does not claim a cached state is live.

### 15.3 Action lifecycle

Intended behavior:

- If the main app is resident, the App Intent executes through the existing `HeadphoneSession`.
- If the app is terminated, macOS launches the app for intent execution, the session performs a bounded connection attempt, and the action either completes with verified read-back or reports failure.
- The extension itself never creates the BLE session.

This lifecycle must be proven by an early feasibility spike on macOS 27. If the system cannot reliably route the action as designed, the fallback remains within the single-app architecture: the control launches/activates the main app and hands off the requested action. A daemon or separate Bluetooth service will not be introduced without a new architecture review.

The same intents may become available to Shortcuts as a consequence of App Intents integration, but custom Shortcuts workflows are not a separate version 1 deliverable.

## 16. Persistence and shared state

### 16.1 Standard preferences

Store with `AppStorage` or a typed preferences wrapper:

- Onboarding completion.
- Selected peripheral UUID.
- Desktop-first/menu-bar-first preference.
- Menu-bar visibility.
- Menu-bar battery visibility.
- Launch-at-login preference mirror.
- Automatic reconnect.
- Diagnostics-enabled flag.

### 16.2 Shared App Group

The App Group stores one small, versioned `Codable` snapshot for the control extension. Writes are atomic. Unknown newer versions are ignored safely by older readers.

The shared snapshot is cleared when the user forgets the headphones.

### 16.3 What is not persisted

- App-only mode presets.
- Queued Bluetooth writes across process termination.
- Raw continuous packet logs by default.
- Bose account information.
- Audio content or now-playing history.

## 17. Error handling and diagnostics

### 17.1 User-facing errors

Normal users see actionable language such as:

- Bluetooth access is required.
- Bluetooth is turned off.
- The selected headphones are unavailable.
- This Bose device is not a supported QC Ultra Gen 1.
- The headphones rejected this setting.
- The connection dropped before the change could be confirmed.
- The mode changed elsewhere; reload before applying edits.

Raw function-block IDs and error bytes do not appear in normal alerts.

### 17.2 Diagnostics

Diagnostics use `OSLog` categories:

- Lifecycle.
- Bluetooth.
- BMAP.
- Session.
- Intents.
- Persistence.

Release logging avoids device serial numbers, full peripheral identifiers, and raw payload dumps unless the user explicitly enables developer diagnostics. Raw diagnostic capture is bounded in size and memory and can be cleared from Settings.

Developer diagnostics may expose packet summaries and protocol error codes, but not arbitrary packet injection in version 1.

## 18. Privacy, security, legal, and App Store readiness

### 18.1 Privacy

Version 1 is local-only:

- No analytics.
- No telemetry.
- No crash-upload service.
- No network requests.
- No Bose account.
- No cloud synchronization.

The privacy manifest and in-app privacy page must state these facts accurately.

### 18.2 Entitlements and platform rules

- App Sandbox enabled for development and release configurations.
- Bluetooth entitlement only where required.
- App Group entitlement for the app and control extension.
- Hardened runtime for signed direct releases.
- Public Apple APIs only.
- No privileged helper.
- No private frameworks.
- No arbitrary file-system access.
- No updater framework in version 1.

### 18.3 Licensing and attribution

The project must preserve applicable MIT license notices from `bozo` and any reused `bozo-bar` source. Public documentation must credit the original reverse-engineering and implementation work appropriately.

The app must state that it is an independent project and is not affiliated with, endorsed by, or sponsored by Bose. Product names are used descriptively.

## 19. Performance and energy targets

The application is optimized for Apple silicon by architecture rather than platform-specific micro-optimizations.

Targets for a release build on a representative Apple-silicon Mac:

- `arm64` binary only.
- No external runtime or background daemon.
- One live CoreBluetooth central/session.
- Idle CPU approximately zero, with a target below 0.5% outside short system callbacks.
- Idle resident memory target below 80 MB after settling.
- No continuous animation while relevant windows are hidden.
- No periodic sub-second timers.
- No battery polling loop while idle.
- State refresh is event-driven or triggered by connection, foregrounding, explicit user action, intent action, or wake recovery.
- Reconnect scanning uses bounded duty and backoff.

Performance is verified with Instruments for CPU, allocations, energy, wakeups, and leaks before a public release.

## 20. Testing strategy

### 20.1 Protocol tests

`HeadphoneCore` tests cover:

- Packet encoding and decoding.
- All operator values used by the app.
- Valid and malformed headers.
- Single and multi-segment BLE framing.
- Reassembly failures, missing segments, duplicates, and out-of-order data.
- Battery parsing.
- Product and firmware parsing.
- Capability parsing.
- Mode-list and mode-configuration parsing.
- Current-mode parsing.
- Standby parsing.
- Immersive Audio parsing.
- BMAP error parsing.
- Unknown bytes and forward-compatible behavior.

Fixtures are derived from documented protocol examples and captures from the user’s physical QC Ultra.

### 20.2 Session tests

A fake transport tests:

- Every valid connection-state transition.
- Invalid transition rejection.
- Initial query ordering.
- Command serialization.
- Write failure before response.
- BMAP error response.
- Timeout.
- Read-back mismatch.
- Disconnect during a command.
- Reconnect backoff.
- Sleep/wake suspension.
- Mode conflict detection.
- Multi-property partial failure and reconciliation.
- Intent-triggered action with and without an existing session.

### 20.3 Integration tests

Integration tests use a scripted fake peripheral/transport to reproduce complete sessions without physical Bluetooth hardware.

### 20.4 UI tests

UI tests cover:

- First-launch onboarding.
- Permission-denied recovery presentation.
- Device selection.
- Desktop-first/menu-bar-first choice.
- Overview controls.
- Mode draft, Apply, Cancel, conflict, and partial failure.
- Settings constraints that prevent an unreachable app.
- Power-off confirmation.
- Disconnected and stale-state presentation.

### 20.5 Physical-device release checklist

Every release candidate is checked with the actual QC Ultra Gen 1 for:

- Fresh onboarding.
- Cold launch.
- Automatic reconnect.
- Device unavailable and later restored.
- Quiet, Aware, and custom-mode switching.
- Immersive Audio changes.
- Every advanced property included in the release.
- Read-back after applying a mode draft.
- Standby timer.
- Power Off.
- Menu-bar behavior.
- Desktop behavior.
- Control Center actions.
- App terminated before a Control Center action.
- Mac sleep and wake.
- Bluetooth off and on.
- Bose app installed or recently active.
- Repeated rapid user actions.

## 21. Early feasibility gates

Implementation planning must begin with two focused technical spikes. Spike code is disposable unless separately reviewed and promoted.

### Gate 1: Advanced mode-writing validation

Using the physical QC Ultra Gen 1:

- Capture current full mode configuration.
- Identify exact write packets for each candidate advanced property.
- Change one property at a time.
- Read the complete mode back.
- Restart/reconnect and confirm persistence behavior.
- Restore the original mode state.
- Record supported ranges, normalization, errors, and sequencing constraints.

A property enters the production editor only after write and read-back are repeatable. Firmware-update functions are explicitly excluded.

### Gate 2: Control Center execution validation

Prove on macOS 27 that:

- A control reads the shared cached state.
- A control action reaches the main application process.
- It uses the existing session when resident.
- It can launch the app when terminated.
- It performs a bounded connection attempt.
- It returns success only after verified read-back.
- Failure and stale-state presentation are understandable.
- The main window does not need to be visible.

The result determines the final intent lifecycle implementation, but not the decision to avoid a separate BLE daemon.

## 22. Build and distribution

### 22.1 Build configurations

- **Debug:** developer signing, verbose diagnostics available.
- **Personal Release:** optimized `arm64`, sandboxed, locally signed for the developer’s machines.
- **Direct Release:** Developer ID signed, hardened runtime, notarized, manually distributed through GitHub Releases.
- **App Store:** reserved configuration using the same source and sandbox model; no App Store submission is part of version 1.

### 22.2 Updates

Version 1 uses manual updates. A GitHub release can provide a notarized `.dmg` or `.zip`, checksums, release notes, and a compatibility statement.

No Sparkle or other updater is included. Adding direct-update infrastructure later requires a separate design because the App Store build must remain free of incompatible update behavior.

### 22.3 Release verification

A release script verifies:

- `arm64` architecture only.
- Expected bundle identifiers.
- Correct entitlements.
- App Sandbox enabled.
- Control extension embedded and signed.
- Privacy manifest present.
- No unexpected dynamic libraries.
- Tests pass.
- Archive passes signing/notarization validation for direct distribution.

## 23. Risks and mitigations

### Reverse-engineered protocol changes

**Risk:** A headphone firmware update changes payloads or behavior.  
**Mitigation:** strict parsers, preserved unknown fields, fixtures by firmware version, capability-driven UI, and read-back verification.

### Advanced settings are not writable as expected

**Risk:** Documentation exposes fields but the device rejects writes.  
**Mitigation:** physical feasibility gate; omit unverified fields; require a minimum advanced-editor threshold before v1 release.

### Control Center process lifecycle differs from assumptions

**Risk:** App Intents cannot reliably execute against the main app session in all states.  
**Mitigation:** early lifecycle spike; bounded launch-and-handoff fallback; no second BLE connection in the extension.

### Bose app contention

**Risk:** Another controller holds or changes the BMAP session/state.  
**Mitigation:** clear busy/disconnected errors, read-back, conflict detection, and no aggressive connection fighting.

### CoreBluetooth identity loss

**Risk:** Stored peripheral identity becomes invalid after forgetting/re-pairing.  
**Mitigation:** return to discovery after retrieval and scan fail; provide explicit Forget Headphones flow.

### App becomes unreachable in menu-bar mode

**Risk:** User hides both Dock and menu-bar entry points.  
**Mitigation:** settings validation prevents the invalid combination and provides an Open Full App action from system intents where appropriate.

## 24. Version 1 acceptance criteria

Version 1 is complete only when:

1. The app builds and runs as an `arm64` macOS 27 application with no Rust runtime dependency.
2. App Sandbox and required entitlements are enabled.
3. Onboarding selects and validates a QC Ultra Gen 1.
4. One `HeadphoneSession` serves every interface.
5. Connection state uses the explicit tested state machine.
6. Automatic reconnect survives normal disconnect, sleep, wake, and Bluetooth cycling.
7. Battery, current mode, mode list, standby timer, and supported Immersive Audio state are loaded from the headphones.
8. Quiet, Aware, and custom-mode switching is verified through read-back.
9. Advanced editing supports ANC/CNC strength plus at least one other physically validated property.
10. Draft conflict and partial-failure behavior work as specified.
11. Desktop-first and menu-bar-first modes are both usable and reversible.
12. The menu-bar interface exposes the approved compact controls.
13. Control Center provides Set Audio Mode, Cycle Audio Mode, Immersive Audio when supported, and Reconnect.
14. Power Off requires confirmation and is absent from Control Center.
15. The control extension does not create a BLE manager.
16. Protocol, session, integration, and critical UI tests pass.
17. Physical-device release checklist passes.
18. Instruments reveals no persistent busy loop, continuous scan, obvious leak, or abnormal idle energy use.
19. Privacy, licensing, attribution, and non-affiliation text are present.
20. A direct-release archive can be signed and notarized without restructuring the application.

## 25. Deferred work

The following may be considered after version 1:

- Additional QC Ultra generations after explicit hardware testing.
- Other Bose BMAP headphones.
- Local preset library.
- Firmware-version compatibility database.
- Richer Shortcuts actions.
- Safe direct-update support for GitHub releases.
- Exportable bounded diagnostic bundles.
- A separate public repository and final product branding.
- Intel support only if a concrete user need justifies reversing the Apple-silicon-only decision.

Any device-family expansion requires its own compatibility design and test matrix; it must not be added as a loose name match.

## 26. Implementation transition

After this written specification is reviewed and approved, the next artifact is a task-level implementation plan. That plan must:

1. Start with the two feasibility gates.
2. Establish the Xcode project and `HeadphoneCore` tests before production UI work.
3. Use test-driven development for protocol and session behavior.
4. Keep each architectural boundary independently testable.
5. Include review checkpoints before promoting spike findings into production code.
6. End with physical-device, performance, signing, and packaging verification.
