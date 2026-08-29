# Ultra Controller for macOS — Product and Technical Design

**Status:** Approved design draft for user review  
**Date:** 2026-08-29  
**Target branch:** `design/qc-ultra-macos-app`  
**Working product name:** **Ultra Controller**  
**Repository:** `DenseDevKev/bozo_cc`

## 1. Purpose

Ultra Controller is a lightweight, native macOS utility for controlling **Bose QuietComfort Ultra Headphones, first generation** without requiring the Bose companion application for everyday controls.

The product will provide three coordinated interfaces:

1. A full desktop application for status, configuration, and advanced mode editing.
2. An optional menu-bar controller for fast access.
3. Optional macOS Control Center controls implemented with WidgetKit and App Intents.

The application communicates directly with the headphones over Bluetooth Low Energy using the reverse-engineered Bose Message Access Protocol (BMAP). It does not modify or replace headphone firmware.

The headphones are always the source of truth. The application reads the device’s current state, issues typed commands, then reads state back before presenting a change as confirmed.

## 2. Product decisions

The following decisions are fixed for version 1:

- **Supported hardware:** Bose QuietComfort Ultra Headphones, first generation only.
- **Unsupported hardware:** QC Ultra Earbuds, later Ultra generations, older QuietComfort models, NC 700, speakers, and unknown BMAP devices.
- **Platform:** macOS 27 or newer.
- **Processor:** Apple silicon only (`arm64`).
- **Implementation:** Native Swift, SwiftUI, targeted AppKit integration, CoreBluetooth, WidgetKit, and App Intents.
- **Bluetooth architecture:** One connection owned by the main application process.
- **Distribution:** Personal builds first; GitHub Releases at most for the initial public distribution path.
- **Future distribution:** App Store compatibility is preserved from the beginning.
- **Default onboarding choice:** Menu-bar-first is preselected, but users choose between menu-bar-first and desktop-first.
- **Version 1 scope:** Essential controls plus verified advanced editing of modes stored on the headphones.
- **Preset model:** No app-only presets. The headphone’s stored modes and settings are authoritative.
- **Firmware:** Firmware update, downgrade, patching, and packet experimentation are explicitly excluded.

## 3. Goals

### 3.1 Primary goals

- Make QC Ultra controls accessible to users who do not use terminal applications.
- Feel structurally and behaviorally native to macOS 27.
- Remain small, responsive, and energy-efficient on Apple silicon.
- Provide dependable reconnection and clear connection state.
- Expose only capabilities verified on the supported hardware.
- Make advanced edits safely through staged changes and read-back verification.
- Keep the architecture compatible with future Mac App Store distribution.
- Keep the protocol layer independently testable without headphones or a graphical interface.

### 3.2 Success criteria

A successful version 1 allows a user to:

- Complete setup without using Terminal.
- Reconnect automatically to a previously selected QC Ultra.
- View connection status, battery percentage, and current audio mode.
- Switch among Quiet, Aware, and modes actually stored on the headphones.
- Read and change supported immersive-audio settings.
- Set the standby timer.
- Power off the headphones from the desktop or menu-bar interface.
- Edit verified properties of existing headphone modes and receive clear confirmation.
- Add supported controls to macOS Control Center or the menu bar.
- Close the desktop window while retaining menu-bar operation, when enabled.
- Recover clearly from denied Bluetooth permission, unavailable hardware, rejected commands, sleep/wake, and disconnection.

## 4. Non-goals

Version 1 will not:

- Replace, modify, or flash headphone firmware.
- Reproduce the complete Bose application.
- Require a Bose account, cloud service, telemetry service, or internet connection.
- Support firmware updates.
- Create a cross-platform application.
- Use Electron, a web view, Node.js, a local HTTP server, or a background Rust daemon.
- Maintain app-only audio-mode presets.
- Create, delete, reorder, or duplicate headphone modes unless those operations are later verified and separately designed.
- Guess at unsupported BMAP messages.
- Expose raw packet injection or protocol-development tools in the normal product interface.
- Promise simultaneous control by Ultra Controller and the Bose application.

## 5. User experience

## 5.1 First-launch onboarding

Onboarding is short, functional, and native. It contains five steps.

### Step 1: Introduction

Explain that Ultra Controller communicates directly with the QC Ultra over Bluetooth and works locally. Avoid marketing carousels or decorative pages.

### Step 2: Bluetooth permission

Request Bluetooth access only when the user advances to this step.

If permission is denied:

- Explain why access is needed.
- Provide a button that opens the relevant macOS privacy settings.
- Keep the application usable enough to retry permission detection.
- Do not show a generic connection failure.

### Step 3: Select headphones

Scan only for compatible BMAP peripherals and present discovered devices with:

- Product name.
- Connection status when known.
- Signal-strength indication when meaningful.

The app saves the selected CoreBluetooth peripheral identifier. It must not silently select an unrelated Bose device.

### Step 4: Choose default application behavior

Offer:

- **Menu-bar first** — preselected. Launch without opening the main window and keep quick controls available in the menu bar.
- **Desktop first** — open the main window on launch and behave like a conventional Mac application.

The choice remains editable in Settings.

### Step 5: Optional integrations

Offer independent choices for:

- Launch at login.
- Show menu-bar item.
- Display battery percentage in the menu bar.
- Show an explanation of how to add Ultra Controller controls to macOS Control Center.

The application must enforce an accessibility invariant: the user cannot disable both the menu-bar entry and all conventional app access while also hiding the Dock icon.

## 5.2 Desktop application

The main window uses `NavigationSplitView` with three destinations: **Overview**, **Modes**, and **Settings**. Diagnostics remain hidden behind an explicit developer setting and are not a main navigation destination by default.

### Overview

The Overview page is the daily control surface. It shows:

- Product name.
- Connected, reconnecting, sleeping, unavailable, or failed status.
- Battery percentage.
- Estimated remaining time when the headphone reports it.
- Timestamp of the last confirmed state update.
- Current audio mode.
- Quick mode selection for every mode reported by the device.
- Immersive Audio setting when supported.
- Standby timer.
- Reconnect action.
- Power-off action with confirmation.

Disconnected content must not look current. Cached values may remain visible, but they are labeled as last known state and visually subordinate to connection status.

### Modes

The Modes page lists only modes reported by the selected headphones.

Selecting a mode opens an inspector or detail pane. Candidate editable properties are:

- Mode name.
- Favorite state.
- ANC level.
- Automatic or aware behavior represented by verified device fields.
- Wind filtering.
- Immersive Audio behavior.
- Other properties whose read, write, and read-back paths pass the advanced-mode feasibility gate.

Unsupported or unverified properties are hidden. They are not displayed as controls that appear functional but fail at runtime.

The application edits existing modes only. Creating, deleting, reordering, or cloning modes is outside version 1.

### Settings

Settings contains:

- Default behavior: menu-bar-first or desktop-first.
- Show menu-bar item.
- Menu-bar display: icon only or icon plus battery percentage.
- Show application in Dock.
- Launch at login.
- Automatic reconnect.
- Selected headphone and Forget Device action.
- Restore interface preferences.
- Optional developer diagnostics switch.
- Version, license, privacy statement, source repository, and acknowledgements.

## 5.3 Menu-bar interface

The menu-bar controller is deliberately compact. It contains:

- Headphone name and connection state.
- Battery percentage and icon.
- Current audio mode.
- Quiet, Aware, and discovered custom modes.
- Immersive Audio selector when supported.
- Reconnect.
- Power Off with confirmation.
- Open Full App.
- Settings.
- Quit.

Advanced mode editing belongs in the desktop application.

When menu-bar operation is enabled, closing the desktop window does not quit the app. Choosing Quit ends the Bluetooth session and terminates the application.

## 5.4 Control Center and system controls

The Control Center extension provides system-rendered controls using WidgetKit and App Intents. It does not implement an arbitrary custom mini-interface.

Initial controls:

1. **Set Audio Mode** — configurable for a mode stored on the headphones.
2. **Cycle Audio Mode**.
3. **Immersive Audio** toggle, when supported.
4. **Reconnect Headphones**.

Power Off is intentionally excluded from Control Center because it is destructive and system control surfaces may not provide an appropriate confirmation path.

The extension reads a small, versioned, last-known state snapshot from the shared app-group container. It never creates or owns a Bluetooth connection.

Control execution follows this order:

1. Invoke an App Intent allowed to execute in the main app process.
2. Use the existing `HeadphoneSession` when the app process is alive.
3. If macOS launches the main process for the intent, initialize a headless session, reconnect, execute the action, update shared state, and terminate only according to normal application lifecycle rules.
4. If final macOS behavior does not make this reliable or App Store-compatible, the control opens Ultra Controller to the relevant action and clearly indicates that connection is required.
5. The extension never falls back to opening a second Bluetooth session itself.

This behavior is governed by the Control Center feasibility gate in Section 18.

## 6. Visual and interaction design

Ultra Controller follows Apple’s native macOS design system rather than imitating glass through custom effects.

Principles:

- Use standard SwiftUI navigation, toolbar, form, inspector, picker, toggle, slider, gauge, menu, sheet, alert, and button components.
- Use SF Symbols for functional iconography.
- Use semantic system colors and typography.
- Let macOS apply Liquid Glass to the functional layer, including navigation and controls.
- Keep content surfaces visually calm; do not put every section into a translucent card.
- Avoid custom blur stacks, fake highlights, continuous shimmer, decorative gradients, and unnecessary animation.
- Support light mode, dark mode, active and inactive windows, increased contrast, reduced transparency, and reduced motion.
- Preserve conventional keyboard behavior and menu commands.

The intended reference is a first-party accessory settings panel, not a mobile interface enlarged for desktop use.

## 7. Technical architecture

## 7.1 High-level structure

```text
Desktop Window ─┐
MenuBarExtra ───┼── ApplicationModel ── HeadphoneSession actor
Settings ───────┘                              │
                                               ▼
                                      HeadphoneCore package
                                      ├── BMAP codec
                                      ├── BLE framing
                                      ├── typed commands
                                      ├── response parsers
                                      └── state models
                                               │
                                               ▼
                                        CoreBluetooth
                                               │
                                               ▼
                                   Bose QC Ultra Headphones

WidgetKit Control Extension
├── reads SharedStateSnapshot
└── invokes App Intents ───────────────► Main app process
```

## 7.2 Build targets

The Xcode project contains:

1. **UltraControllerApp** — the main sandboxed macOS application.
2. **UltraControllerControls** — WidgetKit control extension.
3. **HeadphoneCore** — internal Swift package with no UI dependencies.
4. **UltraControllerTests** — unit and session tests.
5. **UltraControllerUITests** — onboarding and primary-flow tests.

Working bundle identifiers:

- `dev.densedevkev.ultracontroller`
- `dev.densedevkev.ultracontroller.controls`

Working app-group identifier:

- `group.dev.densedevkev.ultracontroller`

The working product name and identifiers are fixed for implementation. A later branding change is a separate release task and does not alter architecture.

## 7.3 HeadphoneCore

`HeadphoneCore` is independent of SwiftUI, AppKit, WidgetKit, UserDefaults, and application lifecycle.

Responsibilities:

- Encode and decode BMAP packets.
- Segment and reassemble BLE payloads.
- Represent operators, function blocks, function identifiers, errors, and capability flags with typed Swift values.
- Construct typed queries and commands.
- Parse supported responses into domain models.
- Preserve unknown bytes for diagnostics without treating them as understood fields.
- Validate packet lengths and reject malformed payloads safely.
- Provide fixtures and deterministic tests.

`HeadphoneCore` does not scan, connect, persist preferences, or mutate UI state.

## 7.4 Bluetooth transport

A narrow transport protocol isolates CoreBluetooth from session logic:

```swift
protocol HeadphoneTransport: Sendable {
    var events: AsyncStream<TransportEvent> { get }
    func scan() async throws -> [DiscoveredHeadphone]
    func connect(to id: HeadphoneID) async throws
    func disconnect() async
    func send(_ bytes: [UInt8]) async throws
}
```

The production implementation uses CoreBluetooth. Tests use a deterministic fake transport.

The v1 transport supports BMAP over BLE only. Classic Bluetooth and RFCOMM are not included.

The implementation discovers the BMAP service and verified secure or unsecure characteristics. It does not rely only on broad device-name matching.

## 7.5 HeadphoneSession

`HeadphoneSession` is a long-lived Swift actor and the sole owner of connection and command state.

Responsibilities:

- Track the selected peripheral.
- Drive the connection state machine.
- Serialize commands.
- Match responses to pending operations when the protocol permits.
- Apply timeouts.
- Query initial device state.
- Discover capabilities and modes.
- Reconcile optimistic UI requests with confirmed device state.
- Manage reconnect backoff.
- Suspend and resume around Mac sleep and wake.
- Publish immutable state snapshots to the application model.
- Write a sanitized shared snapshot for Control Center.

No view or App Intent communicates directly with CoreBluetooth.

## 7.6 ApplicationModel

The main application exposes a `@MainActor` observable model that:

- Subscribes to `HeadphoneSession` snapshots.
- Converts domain state into presentation state.
- Owns staged mode-edit drafts.
- Presents user-readable errors.
- Routes UI actions into typed session commands.
- Coordinates onboarding and preferences.

The desktop window and menu bar observe the same model and therefore cannot disagree about device state.

## 8. Device scope and capability model

Support is explicitly capability-driven after hardware identification.

Connection eligibility requires:

- A selected device with a compatible BMAP BLE service.
- Product information consistent with the supported QC Ultra first-generation model, using verified identifiers discovered during implementation.

After connection, the app queries:

- Product information.
- Battery state.
- Current audio mode.
- Available modes.
- Audio-mode capabilities.
- Standby timer.
- Immersive Audio state.
- Any mode configuration needed for verified editing.

Controls are generated from reported capabilities and successfully parsed mode configuration. The UI must not assume all modes share the same editable fields.

If product identification is inconclusive, the app may show the device for diagnostics but does not enable write operations until compatibility is established.

## 9. Connection state machine

The authoritative state machine is:

```text
unconfigured
permissionRequired
bluetoothUnavailable
scanning
connecting
loadingState
connected
reconnecting
sleeping
unavailable
failed
```

### State rules

- `unconfigured`: no selected headphone.
- `permissionRequired`: Bluetooth authorization is missing or denied.
- `bluetoothUnavailable`: Bluetooth hardware or service is unavailable.
- `scanning`: searching for eligible peripherals.
- `connecting`: CoreBluetooth connection is in progress.
- `loadingState`: connected at transport level but initial BMAP state is incomplete.
- `connected`: required initial state has loaded and commands are permitted.
- `reconnecting`: a selected device disconnected and automatic recovery is active.
- `sleeping`: Mac sleep or session suspension has paused connection work.
- `unavailable`: selected headphones are not currently reachable and retry is paused or exhausted.
- `failed`: a nonrecoverable or user-actionable failure occurred.

Views never infer connection status from the presence of cached battery or mode data.

## 10. Reconnection and lifecycle

Automatic reconnect uses bounded exponential backoff:

```text
1 second → 2 seconds → 5 seconds → 10 seconds → 30 seconds maximum
```

Rules:

- Reset backoff after a confirmed connection.
- Do not maintain continuous unrestricted scans.
- Stop reconnect work when Bluetooth is off, permission is denied, the Mac sleeps, the user forgets the device, or automatic reconnect is disabled.
- Resume from a clean state after wake.
- A manual Reconnect action resets the backoff and tries immediately.
- Repeated failures become `unavailable`, while retaining a manual retry action.
- The connection manager must prevent overlapping scans and duplicate connection attempts.

The application responds to relevant macOS workspace sleep, wake, and termination notifications through public APIs.

## 11. Commands and confirmation semantics

## 11.1 Command queue

All writes pass through one serialized command queue. A command contains:

- Typed intent.
- Encoded packet or packet sequence.
- Timeout.
- Expected response or follow-up query.
- Cancellation behavior.
- User-readable failure mapping.

A request is not considered successful merely because bytes entered the CoreBluetooth write queue.

## 11.2 Confirmation

For state-changing commands:

1. Mark the control as pending.
2. Send the command.
3. Wait for a protocol response when available.
4. Query the affected state after a short protocol-appropriate delay when necessary.
5. Compare confirmed state with the requested state.
6. Publish success only when read-back agrees.
7. On mismatch, show the headphone-reported value and explain that the change was not accepted.

Disconnecting cancels pending commands whose result can no longer be established.

## 11.3 Mode editing transaction

Mode editing is staged in the application model.

- Opening a mode creates a draft from the latest confirmed headphone state.
- Editing controls changes only the draft.
- Apply computes a field-level change set.
- Writes occur in a documented deterministic order.
- After writes finish, the app queries the complete mode configuration.
- The confirmed headphone response replaces the draft.

BMAP may not provide atomic multi-field transactions. Therefore:

- The UI presents Apply as one user operation, not as a guarantee of protocol-level atomicity.
- If one field fails after others succeed, the app reads the complete mode back and reports a partial application.
- The app does not perform speculative rollback unless a rollback path is specifically verified.
- Leaving with unapplied changes prompts to Apply, Discard, or Cancel.

## 12. State ownership and persistence

The headphones are authoritative for operational state and stored modes.

The app persists only:

- Selected CoreBluetooth identifier.
- Onboarding completion.
- Menu-bar-first or desktop-first preference.
- Menu-bar visibility and battery display preference.
- Dock visibility preference.
- Launch-at-login preference.
- Automatic reconnect preference.
- Developer diagnostics preference.
- Versioned last-known device snapshot for system controls and disconnected display.

Preferences use shared `UserDefaults` in the app group where the extension needs access. Structured shared state is stored as a small versioned JSON file written atomically in the app-group container.

The shared snapshot may include:

- Device display name.
- Last confirmed connection state.
- Battery percentage.
- Current mode identifier and display name.
- Available mode identifiers and names.
- Immersive Audio state.
- Timestamp.

It contains no account, location, audio content, or personally sensitive information.

The app does not persist draft edits across launches in version 1.

## 13. Error handling

Normal users receive concise, actionable messages. Examples:

- Bluetooth access is required.
- Bluetooth is turned off.
- Headphones are out of range.
- Another application may be using the control connection.
- The headphones rejected this setting.
- The connection ended before the change could be confirmed.
- This mode does not support that property.
- Open Ultra Controller to complete this Control Center action.

BMAP error codes, packet bytes, characteristic identifiers, and parser details are available only in developer diagnostics.

Errors are categorized as:

- Recoverable automatically.
- Recoverable through a user action.
- Unsupported capability.
- Protocol or parser defect.
- Internal application defect.

The app never displays a success checkmark after an unconfirmed command.

## 14. Privacy and security

Version 1 is local-only.

- No analytics SDK.
- No advertisements.
- No account system.
- No cloud synchronization.
- No remote API.
- No automatic upload of logs.
- No network entitlement unless a future, separately designed feature requires one.
- No privileged helper.
- No shell execution.
- No firmware write path.

The main app and extension use App Sandbox. Entitlements are limited to:

- Application sandbox.
- Bluetooth access for the main app.
- App group shared by the app and control extension.
- Launch-at-login capability through `SMAppService` in the main app.

The extension does not receive Bluetooth entitlement unless final Apple requirements unexpectedly demand it; it must not use that entitlement to open a connection.

Diagnostics redact stable peripheral identifiers from exported human-readable logs unless the user explicitly chooses to include them.

## 15. Performance and Apple silicon optimization

The architecture avoids unnecessary abstraction and background processes.

Requirements:

- `arm64` only.
- No Rosetta slice.
- One application process plus the system-launched control extension.
- One CoreBluetooth central manager.
- One active headphone connection.
- Async event streams rather than polling loops.
- No timer-driven animation while hidden.
- No battery polling while idle.
- Query battery on connection, wake, explicit refresh, and when a visible surface opens with stale data.
- Suspend scan and retry work appropriately.
- Load diagnostic history only when diagnostics are opened.
- Use unified logging rather than a continuously written custom log file.

Release performance targets, measured on an Apple-silicon Mac:

- Median idle CPU below 0.2% after connection settles and all UI is hidden.
- No continuously firing application timer in the idle state.
- Steady-state resident memory below 80 MB with the desktop window open.
- Menu-bar-only steady-state memory below the desktop-window measurement.
- Instruments energy classification remains Low during idle connected operation.
- No retained `CBPeripheral`, task, continuation, or observer cycles after disconnect and reconnect testing.

Targets may be tightened after the first instrumented prototype but not relaxed without documenting the reason.

## 16. Accessibility and localization readiness

Version 1 ships in English but is localization-ready.

Requirements:

- All user-facing strings use localization resources.
- Full keyboard navigation.
- Logical focus order.
- VoiceOver names and values for battery, connection, selected mode, pending actions, and mode controls.
- Do not communicate state by color alone.
- Respect reduced motion and reduced transparency.
- Maintain legibility with increased contrast.
- Use standard controls where possible instead of recreating accessibility behavior.
- Confirm destructive actions with a keyboard-accessible alert.

## 17. Testing strategy

## 17.1 Protocol tests

`HeadphoneCore` tests cover:

- BMAP header encoding and decoding.
- Operators and error responses.
- Single and multi-segment BLE framing.
- Out-of-order, duplicate, incomplete, oversized, and malformed segments.
- Multiple packets in one reassembled payload.
- Battery parsing.
- Product information parsing.
- Current-mode parsing.
- Mode-list and capability parsing.
- Mode-configuration parsing.
- Standby parsing.
- Immersive Audio parsing.
- Unknown values and forward-compatible behavior.

Fixtures include known packets from the Rust implementation and captures from the supported physical QC Ultra.

## 17.2 Session tests

A fake transport tests:

- Every connection-state transition.
- Initial state loading.
- Command serialization.
- Response timeout.
- Write failure.
- Disconnect during a command.
- Reconnect backoff and reset.
- Manual reconnect.
- Sleep and wake.
- Command cancellation.
- Rejected settings.
- Read-back mismatch.
- Partial multi-field Apply.
- Stale-state labeling.
- Forget Device cleanup.

Tests use a controllable clock rather than real delays.

## 17.3 App Intent and control tests

Use App Intents testing support to validate:

- Set Audio Mode configuration.
- Cycle Audio Mode ordering.
- Immersive Audio toggle.
- Reconnect.
- Connected execution.
- Disconnected execution.
- App process alive with no window.
- App process not running.
- Stale shared snapshot.
- Missing selected device.
- Clear failure results.

## 17.4 UI tests

UI tests cover:

- First launch.
- Bluetooth permission explanation.
- Device selection.
- Menu-bar-first and desktop-first choice.
- Overview controls.
- Mode draft editing.
- Apply, Discard, and partial-failure presentation.
- Settings access.
- Forget Device.
- Menu-bar behavior.
- Accessibility identifiers for critical controls.

## 17.5 Physical-device release checklist

Every release candidate is tested with the supported QC Ultra for:

- Fresh app installation.
- Existing system pairing.
- Permission grant and denial recovery.
- Device discovery and selection.
- Cold launch.
- Automatic reconnect.
- Manual reconnect.
- Quiet, Aware, and custom mode switching.
- Immersive Audio changes.
- Every advanced mode field admitted to v1.
- Standby timer.
- Power off.
- Headphones leaving and returning to range.
- Mac sleep and wake.
- Closing and reopening the window.
- Menu-bar-only operation.
- Control Center actions.
- Bose application installed, recently used, and closed.
- Repeated disconnect/reconnect cycles.

## 18. Feasibility gates

Implementation begins with two narrow technical spikes. Their code may be retained only after the design assumptions are proven and tests are added.

## 18.1 Gate A: advanced mode writes

### Question

Which candidate mode fields can the first-generation QC Ultra safely read, write, and read back through BMAP?

### Candidate fields

- Name.
- Favorite state.
- ANC level.
- Automatic/aware field.
- Wind filtering.
- Immersive Audio behavior.

### Pass criteria

A field enters version 1 only when:

- Its read packet and response layout are deterministic.
- Its write packet is verified on the physical device.
- Invalid values are bounded or rejected safely.
- The field reads back with the requested value.
- Rejection and timeout behavior are understood.
- A fixture and unit test exist.
- Editing does not corrupt unrelated mode fields.

### Failure outcome

A failed field is removed from the normal UI. It may remain documented in diagnostics as unverified, but it is not presented as a version 1 feature.

No firmware-update or undocumented destructive operation is used during this spike.

## 18.2 Gate B: Control Center execution and lifecycle

### Question

Can a macOS Control Center action reliably reach the one Bluetooth-owning main application process when the app is:

- Running with a visible window.
- Running without a visible window.
- Present only in the menu bar.
- Not currently running.

### Pass criteria

- The extension never owns the BLE connection.
- The system invokes the intended App Intent target.
- Connected actions complete with clear success or failure.
- A nonrunning app follows a predictable launch/reconnect/action path.
- The flow works within sandbox and intended future App Store constraints.
- State refreshes in Control Center after action completion.
- Failure does not leave duplicate sessions or a zombie process.

### Failure outcome

Retain Control Center controls only for states that work reliably. When direct execution is unavailable, controls open the main app to complete the action or report that the app must be opened. Do not introduce an XPC service, daemon, privileged helper, or BLE connection inside the extension solely to preserve the feature.

## 19. Diagnostics

Diagnostics are optional and hidden by default.

When enabled, they provide:

- Connection-state transition log.
- Transport events.
- Sanitized BMAP request and response metadata.
- Parsed error codes.
- Current capabilities.
- Mode configuration as interpreted by the app.
- Exportable support bundle generated only by explicit user action.

Normal diagnostics do not expose raw packet injection or arbitrary command execution.

Unified logging categories:

- `Application`
- `Bluetooth`
- `BMAP`
- `Session`
- `AppIntents`
- `Persistence`

## 20. Repository layout

The existing Rust workspace remains intact as protocol reference and terminal implementation.

The native project is added under:

```text
apps/macos/UltraController/
├── UltraController.xcodeproj
├── App/
│   ├── UltraControllerApp.swift
│   ├── ApplicationModel.swift
│   ├── Onboarding/
│   ├── Overview/
│   ├── Modes/
│   ├── Settings/
│   ├── MenuBar/
│   └── Resources/
├── ControlsExtension/
├── Packages/
│   └── HeadphoneCore/
│       ├── Package.swift
│       ├── Sources/
│       │   ├── BMAP/
│       │   ├── Protocol/
│       │   ├── Models/
│       │   └── Transport/
│       └── Tests/
├── Tests/
├── UITests/
└── Config/
    ├── App.entitlements
    ├── Controls.entitlements
    ├── PrivacyInfo.xcprivacy
    └── ExportOptions/
```

The Rust code is not linked into the shipped application. Protocol fixtures and behavior may be ported with attribution and parity tests.

## 21. Licensing, naming, and attribution

The repository’s MIT license is preserved. Source ported or derived from `NerdySouth/bozo` and `NerdySouth/bozo-bar` retains appropriate copyright and attribution.

The About screen and README state that:

- Ultra Controller is an independent open-source project.
- It is not affiliated with or endorsed by Bose.
- Bose, QuietComfort, and related marks belong to their respective owner.

The application does not use Bose logos, copied application artwork, or misleading first-party branding.

## 22. Distribution and App Store readiness

Initial distribution paths:

1. Local unsigned development builds.
2. Locally signed builds for personal use.
3. Signed and notarized GitHub Release, when desired.

Version 1 does not include a third-party automatic updater. GitHub releases are installed manually.

App Store readiness requirements retained from the beginning:

- App Sandbox enabled.
- Public Apple frameworks only.
- Minimal entitlements.
- No external executable or helper daemon.
- Complete privacy manifest.
- App-group separation between main app and extension.
- Store-compatible launch-at-login API.
- No downloaded executable code.
- No dependency on private Bluetooth frameworks.

A future App Store submission may require metadata, screenshots, review notes explaining Bluetooth behavior, support/privacy URLs, and additional testing, but it should not require an architectural rewrite.

## 23. Delivery stages

The implementation plan will decompose work into these design-level stages:

1. Establish the native project, signing model, sandbox, app group, and test harness.
2. Port and validate BMAP core with parity fixtures.
3. Complete advanced-mode feasibility Gate A.
4. Build the fake transport and `HeadphoneSession` state machine.
5. Implement real CoreBluetooth discovery and connection.
6. Build onboarding and the desktop Overview.
7. Implement verified staged mode editing.
8. Add menu-bar behavior and lifecycle preferences.
9. Complete Control Center feasibility Gate B and add reliable controls.
10. Finish accessibility, diagnostics, performance profiling, notarized packaging, and release validation.

The implementation plan must preserve test-driven development and verification checkpoints rather than treating this list as executable detail.

## 24. Release acceptance criteria

Version 1 is releasable when:

- All admitted v1 controls work on the supported QC Ultra and read back correctly.
- No unverified advanced field is visible.
- The connection state machine passes deterministic tests.
- Reconnect works through repeated physical-device cycles.
- Sleep/wake recovers without relaunch.
- Desktop and menu-bar state remain consistent.
- Control Center behavior matches the outcome of Gate B.
- Bluetooth permission denial has a working recovery path.
- The app contains no firmware-write path.
- App Sandbox and minimal entitlements are active.
- Accessibility checks pass for critical flows.
- Performance targets are measured with Instruments.
- The release candidate passes the physical-device checklist.
- A signed build passes notarization when GitHub distribution is enabled.
- README, license attribution, privacy statement, and unsupported-device scope are accurate.

## 25. Risks and mitigations

### Reverse-engineered protocol instability

**Risk:** A headphone firmware update changes BMAP behavior.  
**Mitigation:** Capability discovery, strict parsing, read-back confirmation, fixtures by firmware version, and no guessed writes.

### Incomplete advanced mode support

**Risk:** Candidate fields are readable but not safely writable.  
**Mitigation:** Gate A removes failed fields from v1 rather than simulating support.

### Control Center lifecycle limitations

**Risk:** Main-process execution from a system control is unreliable when the app is terminated.  
**Mitigation:** Gate B and a defined open-app fallback; never add a second BLE owner.

### Competition with the Bose application

**Risk:** Two applications attempt BMAP control simultaneously.  
**Mitigation:** Detect transport failures, explain the likely conflict, retry safely, and avoid claiming simultaneous support.

### Background energy use

**Risk:** Reconnect scanning or refresh loops create unnecessary wakeups.  
**Mitigation:** Bounded backoff, lifecycle suspension, event-triggered refresh, and Instruments release gates.

### Unsupported-device writes

**Risk:** A similar Bose device advertises BMAP but uses different semantics.  
**Mitigation:** First-generation QC Ultra identification plus capability validation before enabling writes.

## 26. Authoritative references

- Existing Rust protocol implementation and documentation in this repository.
- `NerdySouth/bozo-bar` as a reference for a native Swift/CoreBluetooth prototype.
- Apple WidgetKit Controls documentation: <https://developer.apple.com/documentation/widgetkit/controls-collection>
- Apple App Intents documentation: <https://developer.apple.com/documentation/appintents/app-intents>
- Apple intent execution-target documentation: <https://developer.apple.com/documentation/appintents/intentexecutiontargets>
- Apple Human Interface Guidelines — Materials: <https://developer.apple.com/design/human-interface-guidelines/materials>

Apple’s intent execution-target API is documented as beta for the macOS 27 development cycle. Gate B must verify behavior against the final macOS 27 and Xcode 27 releases before public distribution.

## 27. Design approval record

The following choices were approved during brainstorming:

- QC Ultra first generation only.
- User chooses desktop-first or menu-bar-first during onboarding.
- Personal/GitHub distribution first, while preserving App Store compatibility.
- Essential controls plus advanced mode editing.
- Headphones are the sole mode source of truth.
- Pure native Swift architecture.
- macOS 27+ and Apple silicon only.
- Staged mode edits with Apply and confirmed read-back.
- Power Off excluded from Control Center.
- Explicit reliability state machine and release testing strategy.
- Advanced-mode and Control Center feasibility gates before feature commitment.
