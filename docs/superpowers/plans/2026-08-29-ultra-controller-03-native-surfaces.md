# Ultra Controller Native Surfaces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the tested session engine into a complete non-terminal macOS experience with onboarding, Overview, Settings, launch behavior, and a compact app-owned menu-bar controller.

**Architecture:** `ApplicationModel` remains the single `@MainActor` presentation model over one `HeadphoneSessionClient`. User preferences and the WidgetKit cache are isolated behind testable stores. SwiftUI uses standard macOS navigation, forms, gauges, pickers, menus, alerts, and system materials; an AppKit activation controller handles Dock/accessory transitions without duplicating state or Bluetooth ownership.

**Tech Stack:** SwiftUI, Observation, AppKit, ServiceManagement, Foundation, XCTest/XCUITest, String Catalogs, App Groups, `HeadphoneSession` from Plan 2.

**Spec:** `docs/superpowers/specs/2026-08-29-qc-ultra-macos-controller-design.md`

## Global Constraints

- Plan 2's full checkpoint must pass before replacing the debug harness.
- Desktop and app-menu-bar surfaces observe the same `ApplicationModel` instance.
- Cached/disconnected values remain visibly stale and never look live.
- Menu-bar-first is preselected during onboarding.
- The app must never allow both Dock access and its app-owned menu-bar item to be disabled.
- Closing a window is not Quit; Quit terminates the session and app.
- Use `SMAppService.mainApp` for launch at login.
- Use standard macOS controls and system materials; do not create custom glass cards or continuous decorative animation.
- Every user-facing string lives in `Localizable.xcstrings`.
- Keep advanced mode editing out of this plan; the Modes destination is read-only until Plan 4.

---

## File Map

| Path | Responsibility |
|---|---|
| `App/Application/AppEnvironment.swift` | Production, preview, and UI-test dependency construction. |
| `App/Application/ApplicationModel.swift` | One observable presentation model and action router. |
| `App/Application/AppPreferences.swift` | Typed persisted user preferences and access-surface invariant. |
| `App/Application/SharedSnapshotStore.swift` | Atomic App Group snapshot cache. |
| `App/Lifecycle/AppActivationController.swift` | Regular/accessory Dock behavior using AppKit. |
| `App/Lifecycle/LaunchAtLoginController.swift` | `SMAppService.mainApp` registration/status. |
| `App/Onboarding/*` | Five-step setup and recovery flow. |
| `App/Overview/*` | Daily control surface. |
| `App/Modes/ModesListView.swift` | Read-only list before Plan 4 editor. |
| `App/Settings/*` | Preferences, device management, About/privacy/license. |
| `App/MenuBar/*` | Compact `MenuBarExtra` controller and label. |
| `App/Resources/Localizable.xcstrings` | All product strings. |
| `UITests/*` | First-run, launch mode, settings, menu bar, stale/error, and accessibility smoke flows. |

### Task 1: Introduce testable application dependencies, preferences, and shared snapshots

**Files:**
- Create: `apps/macos/UltraController/App/Application/HeadphoneSessionClient.swift`
- Create: `apps/macos/UltraController/App/Application/AppEnvironment.swift`
- Create: `apps/macos/UltraController/App/Application/PrimaryExperience.swift`
- Create: `apps/macos/UltraController/App/Application/AppPreferences.swift`
- Create: `apps/macos/UltraController/App/Application/SharedHeadphoneSnapshot.swift`
- Create: `apps/macos/UltraController/App/Application/SharedSnapshotStore.swift`
- Modify: `apps/macos/UltraController/App/Application/ApplicationModel.swift`
- Test: `apps/macos/UltraController/Tests/Application/AppPreferencesTests.swift`
- Test: `apps/macos/UltraController/Tests/Application/SharedSnapshotStoreTests.swift`
- Test: `apps/macos/UltraController/Tests/Fakes/ScriptedSessionClient.swift`

**Interfaces:**
- Consumes: `HeadphoneSession` and `HeadphoneSnapshot`.
- Produces: protocol-backed session injection, typed preferences, and a versioned atomic cache for the future controls extension.

- [ ] **Step 1: Write access-surface invariant tests**

```swift
final class AppPreferencesTests: XCTestCase {
    func testMenuBarFirstCannotHideMenuBarItemAndDockTogether() {
        var preferences = AppPreferences.State(
            primaryExperience: .menuBarFirst,
            showsMenuBarItem: true,
            showsDockIcon: false
        )
        preferences.setMenuBarItemVisible(false)
        XCTAssertTrue(preferences.showsDockIcon)
        XCTAssertFalse(preferences.showsMenuBarItem)
    }

    func testDesktopFirstMayHideMenuBarWhenDockRemainsVisible() {
        var preferences = AppPreferences.State(
            primaryExperience: .desktopFirst,
            showsMenuBarItem: true,
            showsDockIcon: true
        )
        preferences.setMenuBarItemVisible(false)
        XCTAssertFalse(preferences.showsMenuBarItem)
        XCTAssertTrue(preferences.showsDockIcon)
    }
}
```

- [ ] **Step 2: Write shared-snapshot tests**

```swift
func testSnapshotBecomesStaleAfterTwoMinutes() {
    let now = Date(timeIntervalSince1970: 1_000)
    let snapshot = SharedHeadphoneSnapshot.sample(updatedAt: now.addingTimeInterval(-121))
    XCTAssertTrue(snapshot.isStale(at: now, maximumAge: 120))
}

func testStoreAtomicallyRoundTripsSnapshot() throws {
    let directory = temporaryDirectory()
    let store = SharedSnapshotStore(directory: directory)
    try store.write(.sample())
    XCTAssertEqual(try store.read(), .sample())
}
```

- [ ] **Step 3: Run and verify failure**

```bash
make macos-test
```

Expected: FAIL because preferences/snapshot types are undefined.

- [ ] **Step 4: Define the session client interface**

```swift
protocol HeadphoneSessionClient: Sendable {
    var snapshots: AsyncStream<HeadphoneSnapshot> { get }
    func start(savedID: HeadphoneID?) async
    func select(_ id: HeadphoneID) async
    func manualReconnect() async
    func refresh() async throws
    func setCurrentMode(_ id: UInt8) async throws
    func setStandby(_ minutes: UInt8) async throws
    func setSpatialAudio(_ mode: SpatialAudioMode) async throws
    func powerOff() async throws
    func forgetDevice() async
    func suspendForSleep() async
    func resumeAfterWake() async
}

extension HeadphoneSession: HeadphoneSessionClient {}
```

`ApplicationModel` depends on `any HeadphoneSessionClient`, not concrete CoreBluetooth types. `ScriptedSessionClient` provides UI-test snapshots and records actions.

- [ ] **Step 5: Implement typed preferences**

```swift
enum PrimaryExperience: String, Codable, CaseIterable, Sendable {
    case menuBarFirst
    case desktopFirst
}
```

`AppPreferences` uses an injected `UserDefaults` suite and persists:

- onboarding completion
- selected peripheral UUID string
- primary experience
- app menu-bar visibility
- battery text visibility
- Dock visibility
- launch at login preference mirror
- automatic reconnect
- developer diagnostics

Enforce the access-surface invariant inside setters, not only in SwiftUI.

- [ ] **Step 6: Implement the shared snapshot schema**

```swift
struct SharedHeadphoneSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let updatedAt: Date
    let connection: SharedConnectionState
    let deviceName: String?
    let batteryPercentage: UInt8?
    let currentModeID: UInt8?
    let currentModeName: String?
    let modes: [SharedAudioMode]
    let spatialAudioMode: UInt8?

    func isStale(at now: Date = .now, maximumAge: TimeInterval = 120) -> Bool {
        now.timeIntervalSince(updatedAt) > maximumAge
    }
}
```

Write JSON to a temporary sibling file, call `FileHandle.synchronize()`, then replace the destination atomically. Unknown schema versions return `.unsupportedSchema` rather than partial data.

- [ ] **Step 7: Update `ApplicationModel`**

On each confirmed session snapshot:

- publish the complete state
- clear matching pending action
- map a small sanitized shared snapshot
- write it through `SharedSnapshotStore`
- preserve the last confirmed values while disconnected and set `isStale = true`

Use five minutes as the app-surface refresh threshold and 120 seconds as the stricter Control Center cache threshold.

- [ ] **Step 8: Run and commit**

```bash
make macos-test
git add apps/macos/UltraController/App/Application apps/macos/UltraController/Tests/Application apps/macos/UltraController/Tests/Fakes
git commit -m "feat: add application preferences and shared state"
```

### Task 2: Build the five-step onboarding flow

**Files:**
- Create: `apps/macos/UltraController/App/Onboarding/OnboardingStep.swift`
- Create: `apps/macos/UltraController/App/Onboarding/OnboardingCoordinator.swift`
- Create: `apps/macos/UltraController/App/Onboarding/OnboardingView.swift`
- Create: `apps/macos/UltraController/App/Onboarding/WelcomeStepView.swift`
- Create: `apps/macos/UltraController/App/Onboarding/BluetoothPermissionStepView.swift`
- Create: `apps/macos/UltraController/App/Onboarding/DeviceSelectionStepView.swift`
- Create: `apps/macos/UltraController/App/Onboarding/BehaviorStepView.swift`
- Create: `apps/macos/UltraController/App/Onboarding/IntegrationStepView.swift`
- Create: `apps/macos/UltraController/App/Lifecycle/SystemSettingsLauncher.swift`
- Test: `apps/macos/UltraController/Tests/Onboarding/OnboardingCoordinatorTests.swift`
- Test: `apps/macos/UltraController/UITests/OnboardingUITests.swift`

**Interfaces:**
- Consumes: candidates/phase from `ApplicationModel`, preferences, and launch-at-login controller added in Task 4.
- Produces: resumable onboarding completion only after a supported headset is selected and verified.

- [ ] **Step 1: Write coordinator tests**

```swift
func testDefaultExperienceIsMenuBarFirst() {
    let coordinator = OnboardingCoordinator()
    XCTAssertEqual(coordinator.selectedExperience, .menuBarFirst)
}

func testCannotFinishBeforeSupportedDeviceValidation() {
    var coordinator = OnboardingCoordinator()
    coordinator.step = .integration
    coordinator.hasValidatedDevice = false
    XCTAssertFalse(coordinator.canFinish)
}

func testPermissionDenialStaysOnPermissionStep() {
    var coordinator = OnboardingCoordinator()
    coordinator.step = .bluetoothPermission
    coordinator.handleAvailability(.unauthorized)
    XCTAssertEqual(coordinator.step, .bluetoothPermission)
    XCTAssertTrue(coordinator.showsPermissionRecovery)
}
```

- [ ] **Step 2: Run and verify failure**

```bash
make macos-test
```

Expected: FAIL because onboarding types are undefined.

- [ ] **Step 3: Implement the coordinator state machine**

```swift
enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome
    case bluetoothPermission
    case deviceSelection
    case behavior
    case integration
}
```

The coordinator persists the current unresolved step. It may advance from device selection only after the session reports supported identity and `writesEnabled == true`. Unsupported candidates remain selectable only long enough to display the rejection result.

- [ ] **Step 4: Implement permission recovery with public APIs**

Do not depend on an undocumented preference-pane URL. `SystemSettingsLauncher` opens `/System/Applications/System Settings.app` through `NSWorkspace.openApplication(at:configuration:)`, and the view instructs the user to navigate to Privacy & Security → Bluetooth. Provide `Retry` to re-read `CBManager.authorization` through the transport/session.

- [ ] **Step 5: Implement device selection**

Rows show name, signal strength label, and whether the BMAP service was advertised. Connecting displays a progress indicator. Save the peripheral identifier only after supported-device validation succeeds.

- [ ] **Step 6: Implement behavior and integration choices**

Behavior cards use native radio/picker semantics:

- Menu Bar First — selected by default.
- Desktop First.

Integration offers launch at login, menu-bar battery text, and a short Control Center instruction. Show controls as unavailable until Plan 4 adds the extension.

- [ ] **Step 7: Add onboarding UI-test launch configuration**

`AppEnvironment.make()` checks launch argument `--ui-testing-onboarding` and injects `ScriptedSessionClient` plus an isolated `UserDefaults(suiteName:)`. The UI test must complete all five steps and assert `overview.root` appears.

- [ ] **Step 8: Run and commit**

```bash
make macos-test
xcodebuild -project apps/macos/UltraController/UltraController.xcodeproj \
  -scheme UltraController \
  -destination 'platform=macOS,arch=arm64' \
  test

git add apps/macos/UltraController/App/Onboarding apps/macos/UltraController/App/Lifecycle/SystemSettingsLauncher.swift apps/macos/UltraController/Tests/Onboarding apps/macos/UltraController/UITests
git commit -m "feat: add native QC Ultra onboarding"
```

### Task 3: Replace the debug harness with the native desktop shell and Overview

**Files:**
- Create: `apps/macos/UltraController/App/Application/AppDestination.swift`
- Create: `apps/macos/UltraController/App/Application/RootView.swift`
- Replace: `apps/macos/UltraController/App/Overview/PlaceholderOverviewView.swift` with `OverviewView.swift`
- Create: `apps/macos/UltraController/App/Overview/DeviceHeaderView.swift`
- Create: `apps/macos/UltraController/App/Overview/BatteryView.swift`
- Create: `apps/macos/UltraController/App/Overview/ModeSelectionView.swift`
- Create: `apps/macos/UltraController/App/Overview/SpatialAudioPicker.swift`
- Create: `apps/macos/UltraController/App/Overview/StandbyPicker.swift`
- Create: `apps/macos/UltraController/App/Overview/ConnectionRecoveryView.swift`
- Create: `apps/macos/UltraController/App/Modes/ModesListView.swift`
- Delete: `apps/macos/UltraController/App/Diagnostics/ConnectivityHarnessView.swift` after equivalent diagnostics remain available behind DEBUG.
- Test: `apps/macos/UltraController/Tests/Overview/OverviewPresentationTests.swift`
- UI Test: `apps/macos/UltraController/UITests/OverviewUITests.swift`

**Interfaces:**
- Consumes: `ApplicationModel` and preferences.
- Produces: `NavigationSplitView` with Overview, Modes, Settings; complete essential desktop controls.

- [ ] **Step 1: Write presentation tests**

Test that disconnected snapshots retain last-known values but mark them stale, unsupported features produce no control, and a pending mode action does not replace the confirmed selected mode.

```swift
func testPendingModeLeavesConfirmedSelectionActive() {
    let state = OverviewPresentation(
        snapshot: .connected(currentModeID: 1),
        pendingAction: .setMode(2)
    )
    XCTAssertEqual(state.confirmedModeID, 1)
    XCTAssertEqual(state.pendingModeID, 2)
}
```

- [ ] **Step 2: Run and verify failure**

```bash
make macos-test
```

Expected: FAIL because Overview presentation types/views are absent.

- [ ] **Step 3: Build the desktop shell**

```swift
struct RootView: View {
    @Bindable var model: ApplicationModel

    var body: some View {
        NavigationSplitView {
            List(AppDestination.allCases, selection: $model.destination) { destination in
                Label(destination.title, systemImage: destination.systemImage)
                    .tag(destination)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            switch model.destination {
            case .overview: OverviewView(model: model)
            case .modes: ModesListView(model: model)
            case .settings: SettingsView(model: model)
            }
        }
        .accessibilityIdentifier("root.navigation")
    }
}
```

- [ ] **Step 4: Implement Overview using standard controls**

- Device header: product name, connection label, last-confirmed time.
- Battery: native `Gauge` plus textual percentage/remaining time.
- Modes: native segmented picker when mode count fits; otherwise a `Menu`/list of buttons.
- Spatial audio: `Picker` for Off/Still/Motion only when supported.
- Standby: `Picker` with `0, 5, 10, 20, 30, 60, 120` minutes.
- Reconnect: visible when not connected.
- Power Off: destructive button with `confirmationDialog`.

Do not wrap every section in custom translucent cards. Use `Form`, `Section`, `LabeledContent`, system spacing, and toolbar placement.

- [ ] **Step 5: Implement stale and failure states**

- Cached values get `Last updated …` and reduced prominence.
- Permission failure offers System Settings and Retry.
- Bluetooth-off offers Retry after enabling Bluetooth.
- Out-of-range offers Reconnect.
- Unsupported device offers Forget Device.
- Pending controls use `ProgressView` and remain keyboard-readable.

- [ ] **Step 6: Add read-only Modes destination**

Before Plan 4, `ModesListView` lists reported modes, current/favorite indicators, and verified read-only fields. Selecting a row shows `Advanced editing will be available after protocol validation` only in development builds; release copy simply omits edit controls.

- [ ] **Step 7: Run tests and commit**

```bash
make macos-test
xcodebuild -project apps/macos/UltraController/UltraController.xcodeproj \
  -scheme UltraController -destination 'platform=macOS,arch=arm64' test

git add apps/macos/UltraController/App/Application apps/macos/UltraController/App/Overview apps/macos/UltraController/App/Modes apps/macos/UltraController/Tests/Overview apps/macos/UltraController/UITests
git commit -m "feat: add native desktop controller"
```

### Task 4: Implement Settings, launch at login, and Dock/accessory lifecycle

**Files:**
- Create: `apps/macos/UltraController/App/Lifecycle/AppActivationController.swift`
- Create: `apps/macos/UltraController/App/Lifecycle/LaunchAtLoginController.swift`
- Create: `apps/macos/UltraController/App/Settings/SettingsView.swift`
- Create: `apps/macos/UltraController/App/Settings/GeneralSettingsView.swift`
- Create: `apps/macos/UltraController/App/Settings/DeviceSettingsView.swift`
- Create: `apps/macos/UltraController/App/Settings/AboutView.swift`
- Modify: `apps/macos/UltraController/App/Application/UltraControllerApp.swift`
- Test: `apps/macos/UltraController/Tests/Lifecycle/AppActivationPolicyTests.swift`
- Test: `apps/macos/UltraController/Tests/Lifecycle/LaunchAtLoginControllerTests.swift`
- UI Test: `apps/macos/UltraController/UITests/SettingsUITests.swift`

**Interfaces:**
- Consumes: `AppPreferences`, `ApplicationModel`, `SMAppService.mainApp`.
- Produces: reversible menu-bar-first/desktop-first behavior, public launch-at-login control, device forgetting, and About/privacy content.

- [ ] **Step 1: Write pure activation-policy tests**

```swift
func testMenuBarFirstWithoutWindowUsesAccessoryPolicy() {
    XCTAssertEqual(
        AppActivationDecision(experience: .menuBarFirst, windowVisible: false, showsDockIcon: false).policy,
        .accessory
    )
}

func testOpeningFullAppUsesRegularPolicy() {
    XCTAssertEqual(
        AppActivationDecision(experience: .menuBarFirst, windowVisible: true, showsDockIcon: false).policy,
        .regular
    )
}
```

- [ ] **Step 2: Implement AppKit activation transitions**

`AppActivationController` is `@MainActor` and calls only documented APIs:

```swift
func apply(_ decision: AppActivationDecision) {
    NSApplication.shared.setActivationPolicy(decision.policy.nsPolicy)
    if decision.windowVisible {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
```

When the final desktop window closes in menu-bar-first mode, return to `.accessory`. `Open Full App` switches to `.regular`, opens/focuses the main window, then activates the app.

- [ ] **Step 3: Implement launch-at-login wrapper**

Define an injectable service protocol around `SMAppService.mainApp`:

```swift
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}
```

On enable, call `register()`. On disable, call `unregister()`. Map `.requiresApproval` to a button that calls `SMAppService.openSystemSettingsLoginItems()`.

- [ ] **Step 4: Implement Settings sections**

General:

- Primary experience.
- Show app menu-bar item.
- Show battery text.
- Show Dock icon.
- Launch at login.
- Automatic reconnect.

Device:

- Selected product and connection state.
- Firmware if available.
- Forget Headphones with confirmation.

About:

- Version/build.
- Local-only privacy statement.
- MIT license and upstream acknowledgements.
- Independent/non-affiliated Bose statement.

- [ ] **Step 5: Test the access-path invariant in UI**

Attempt to hide the menu-bar item while Dock is hidden. Assert the UI either keeps the menu item enabled or enables Dock and shows an explanatory message. It must never persist an unreachable combination.

- [ ] **Step 6: Run and commit**

```bash
make macos-test
xcodebuild -project apps/macos/UltraController/UltraController.xcodeproj \
  -scheme UltraController -destination 'platform=macOS,arch=arm64' test

git add apps/macos/UltraController/App/Lifecycle apps/macos/UltraController/App/Settings apps/macos/UltraController/App/Application/UltraControllerApp.swift apps/macos/UltraController/Tests/Lifecycle apps/macos/UltraController/UITests
git commit -m "feat: add settings and native app lifecycle"
```

### Task 5: Add the app-owned menu-bar controller

**Files:**
- Create: `apps/macos/UltraController/App/MenuBar/MenuBarLabel.swift`
- Create: `apps/macos/UltraController/App/MenuBar/MenuBarControllerView.swift`
- Create: `apps/macos/UltraController/App/MenuBar/MenuBarPresentation.swift`
- Modify: `apps/macos/UltraController/App/Application/UltraControllerApp.swift`
- Test: `apps/macos/UltraController/Tests/MenuBar/MenuBarPresentationTests.swift`
- UI Test: `apps/macos/UltraController/UITests/MenuBarUITests.swift`

**Interfaces:**
- Consumes: the same `ApplicationModel` instance used by the desktop window.
- Produces: optional `MenuBarExtra` with battery/current mode/quick actions and Open Full App/Settings/Quit.

- [ ] **Step 1: Write menu-bar presentation tests**

```swift
func testLabelIncludesBatteryOnlyWhenEnabled() {
    let snapshot = HeadphoneSnapshot.connected(batteryPercentage: 85)
    XCTAssertEqual(MenuBarPresentation(snapshot: snapshot, showsBattery: true).labelText, "85%")
    XCTAssertNil(MenuBarPresentation(snapshot: snapshot, showsBattery: false).labelText)
}

func testDisconnectedLabelDoesNotShowBatteryAsLive() {
    let snapshot = HeadphoneSnapshot.disconnected(lastBatteryPercentage: 85)
    XCTAssertNil(MenuBarPresentation(snapshot: snapshot, showsBattery: true).labelText)
}
```

- [ ] **Step 2: Run and verify failure**

```bash
make macos-test
```

Expected: FAIL because menu-bar presentation types are undefined.

- [ ] **Step 3: Implement the dynamic label**

Use an SF Symbol headphone icon. Add battery text only when connected and preference is enabled. Use a small status indicator in accessibility text, not a custom animated icon.

- [ ] **Step 4: Implement `MenuBarExtra`**

At app-scene level:

```swift
MenuBarExtra(isInserted: $environment.preferences.showsMenuBarItem) {
    MenuBarControllerView(model: environment.applicationModel)
} label: {
    MenuBarLabel(presentation: environment.applicationModel.menuBarPresentation)
}
.menuBarExtraStyle(.window)
```

The view contains device/connection, battery, modes, spatial audio, Reconnect, Power Off confirmation, Open Full App, Settings, and Quit. Advanced editing remains desktop-only.

- [ ] **Step 5: Implement Quit explicitly**

Quit launches a bounded task to stop the session/transport and then calls `NSApplication.shared.terminate(nil)`. Do not use window closure as Quit.

- [ ] **Step 6: Run UI tests and physical smoke test**

Verify menu-bar-only launch, quick mode changes, window open/close, Settings navigation, and Quit. Confirm desktop and menu bar update from the same physical mode notification.

- [ ] **Step 7: Commit**

```bash
git add apps/macos/UltraController/App/MenuBar apps/macos/UltraController/App/Application/UltraControllerApp.swift apps/macos/UltraController/Tests/MenuBar apps/macos/UltraController/UITests
git commit -m "feat: add native menu-bar controller"
```

### Task 6: Localize strings and complete accessibility behavior

**Files:**
- Create: `apps/macos/UltraController/App/Resources/Localizable.xcstrings`
- Create: `apps/macos/UltraController/App/Application/UltraControllerCommands.swift`
- Modify: every user-facing view from Tasks 2–5.
- Create: `apps/macos/UltraController/UITests/AccessibilitySmokeUITests.swift`

**Interfaces:**
- Consumes: all current UI.
- Produces: English String Catalog, keyboard commands, stable accessibility IDs/labels, and appearance coverage.

- [ ] **Step 1: Add a string-literal audit that fails on unlocalized product copy**

Create `Scripts/check-localized-strings.sh` that scans SwiftUI view files for `Text("` and `Button("` literals not wrapped in `String(localized:)` or generated String Catalog keys. Allow SF Symbol names and accessibility IDs through a small explicit regex allowlist.

Run it before conversion and expect failure.

- [ ] **Step 2: Create String Catalog keys**

Include keys for:

- onboarding steps and recovery copy
- connection states/errors
- mode/spatial/standby controls
- pending/success/failure messages
- Settings and About
- Power Off confirmation
- menu-bar commands
- stale/last-updated state

Use concise English values; do not include raw BMAP terminology in normal UI.

- [ ] **Step 3: Add keyboard commands**

```swift
struct UltraControllerCommands: Commands {
    @FocusedValue(\.ultraControllerActions) private var actions

    var body: some Commands {
        CommandMenu("Headphones") {
            Button("Reconnect") { actions?.reconnect() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Divider()
            Button("Open Overview") { actions?.openOverview() }
                .keyboardShortcut("1", modifiers: .command)
            Button("Open Modes") { actions?.openModes() }
                .keyboardShortcut("2", modifiers: .command)
        }
    }
}
```

- [ ] **Step 4: Add accessibility semantics**

- Battery: `accessibilityValue("85 percent, approximately 5 hours remaining")`.
- Connection: never color-only.
- Mode controls: announce confirmed versus pending selection.
- Destructive buttons: explicit label and keyboard-accessible confirmation.
- Errors: focus/announce the recovery message.
- Mode/menu rows: meaningful labels when SF Symbols are hidden.

- [ ] **Step 5: Add appearance and accessibility UI-test matrix**

Launch test configurations for light, dark, increased contrast, reduced transparency, and reduced motion. Assert primary controls remain hittable and labeled. Use macOS accessibility environment launch settings where supported; otherwise add deterministic app launch arguments that mirror the environment for view-level smoke coverage and complete one manual system-setting pass.

- [ ] **Step 6: Run audits/tests and commit**

```bash
apps/macos/UltraController/Scripts/check-localized-strings.sh
make macos-test
xcodebuild -project apps/macos/UltraController/UltraController.xcodeproj \
  -scheme UltraController -destination 'platform=macOS,arch=arm64' test

git add apps/macos/UltraController/App apps/macos/UltraController/UITests apps/macos/UltraController/Scripts
git commit -m "feat: complete native accessibility and localization"
```

### Task 7: Run the Plan 3 checkpoint

**Files:**
- Verify all Plan 3 product surfaces and tests.

**Interfaces:**
- Produces for Plan 4: complete essential desktop/menu-bar product, stable preferences/shared snapshot, and injectable UI-test environment.

- [ ] **Step 1: Run all tests and release build**

```bash
cargo test --workspace
make macos-test-core
make macos-test
xcodebuild -project apps/macos/UltraController/UltraController.xcodeproj \
  -scheme UltraController \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Expected: all pass.

- [ ] **Step 2: Run product-level physical smoke test**

Verify:

1. Fresh onboarding without Terminal.
2. Menu-bar-first default.
3. Desktop-first switch and relaunch.
4. Battery/current mode/standby/spatial display.
5. Mode, standby, and spatial mutations with confirmed UI.
6. Power Off confirmation and expected disconnect.
7. Menu-bar-only control with no window.
8. Window close/reopen and Settings.
9. Launch-at-login registration/status.
10. Sleep/wake and out-of-range recovery.

- [ ] **Step 3: Verify only one Bluetooth owner**

```bash
COUNT=$(grep -R "CBCentralManager(" apps/macos/UltraController/App --include='*.swift' | wc -l | tr -d ' ')
test "$COUNT" = "1"
```

Expected: one production construction site.

- [ ] **Step 4: Verify localization audit and access invariant**

```bash
apps/macos/UltraController/Scripts/check-localized-strings.sh
make macos-test | tee /tmp/ultra-controller-tests.log
! grep -q "0 tests executed" /tmp/ultra-controller-tests.log
```

Plan 3 is complete when the essential app is usable entirely through native desktop/menu-bar surfaces and no UI can diverge from the session's confirmed state.
