# Ultra Controller Native Surfaces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the tested session engine into a complete non-terminal macOS experience with onboarding, Overview, Settings, launch behavior, and a compact app-owned menu-bar controller.

**Architecture:** `ApplicationModel` remains the single `@MainActor` presentation model over one `HeadphoneSessionClient`. Preferences and the WidgetKit cache are isolated behind testable stores. SwiftUI uses standard navigation, forms, gauges, pickers, menus, alerts, and system materials; an AppKit activation controller handles Dock/accessory transitions without duplicating Bluetooth or state.

**Tech Stack:** SwiftUI, Observation, AppKit, ServiceManagement, Foundation, XCTest/XCUITest, String Catalogs, App Groups, Plan 2's `HeadphoneSession`.

**Spec:** `docs/superpowers/specs/2026-08-29-qc-ultra-macos-controller-design.md`

## Global Constraints

- Plan 2's full checkpoint must pass before replacing the debug harness.
- Desktop and app-menu-bar surfaces observe the same `ApplicationModel` instance.
- Cached/disconnected values remain visibly stale and never look live.
- Menu-bar-first is preselected during onboarding.
- Never allow both regular Dock access and the app-owned menu-bar item to be disabled.
- Closing a window is not Quit; Quit terminates the session and app.
- Use `SMAppService.mainApp` for launch at login.
- Use standard macOS controls/system materials; no custom glass-card system or decorative idle animation.
- Store every user-facing string in `Localizable.xcstrings` through `LocalizedStringResource` constants.
- Keep advanced editing out of this plan; Modes remains read-only until Plan 4.

---

## File Map

| Path | Responsibility |
|---|---|
| `App/Application/HeadphoneSessionClient.swift` | Testable presentation-layer protocol around Plan 2's session APIs. |
| `App/Application/AppEnvironment.swift` | One production/preview/UI-test dependency graph. |
| `App/Application/ApplicationModel.swift` | Shared observable presentation state and user-action router. |
| `App/Application/AppPreferences.swift` | Typed persistence and access-surface invariant. |
| `App/Application/SharedSnapshotStore.swift` | Atomic App Group cache for Plan 4 controls. |
| `App/Lifecycle/AppActivationController.swift` | Regular/accessory activation policy. |
| `App/Lifecycle/LaunchAtLoginController.swift` | `SMAppService.mainApp` wrapper. |
| `App/Onboarding/*` | Resumable five-step setup/recovery flow. |
| `App/Overview/*` | Essential daily controller. |
| `App/Modes/ModesListView.swift` | Read-only mode list before Plan 4. |
| `App/Settings/*` | Preferences, device management, privacy/About. |
| `App/MenuBar/*` | Compact `MenuBarExtra` and label. |
| `App/Resources/Localizable.xcstrings` | English v1 String Catalog. |
| `UITests/*` | First-run, launch-mode, Settings, menu bar, stale/error, and accessibility smoke flows. |

### Task 1: Refactor the presentation boundary and add typed persistence/shared snapshots

**Files:**
- Create: `apps/macos/UltraController/App/Application/HeadphoneSessionClient.swift`
- Create: `apps/macos/UltraController/App/Application/AppEnvironment.swift`
- Create: `apps/macos/UltraController/App/Application/PrimaryExperience.swift`
- Create: `apps/macos/UltraController/App/Application/AppPreferences.swift`
- Create: `apps/macos/UltraController/App/Application/SharedHeadphoneSnapshot.swift`
- Create: `apps/macos/UltraController/App/Application/SharedSnapshotStore.swift`
- Modify: `apps/macos/UltraController/App/Application/ApplicationModel.swift`
- Create: `apps/macos/UltraController/Tests/Fakes/ScriptedSessionClient.swift`
- Test: `apps/macos/UltraController/Tests/Application/AppPreferencesTests.swift`
- Test: `apps/macos/UltraController/Tests/Application/SharedSnapshotStoreTests.swift`
- Test: `apps/macos/UltraController/Tests/Application/ApplicationModelClientTests.swift`

**Interfaces:**
- Consumes: Plan 2 `HeadphoneSession`/`HeadphoneSnapshot`.
- Produces: `HeadphoneSessionClient`, typed preferences, one environment, and versioned atomic shared cache.

- [ ] **Step 1: Write access-surface invariant tests**

```swift
final class AppPreferencesTests: XCTestCase {
    func testHidingLastMenuSurfaceEnablesDock() {
        var state = AppPreferences.State(
            primaryExperience: .menuBarFirst,
            showsMenuBarItem: true,
            showsDockIcon: false
        )
        state.setMenuBarItemVisible(false)
        XCTAssertFalse(state.showsMenuBarItem)
        XCTAssertTrue(state.showsDockIcon)
    }

    func testDesktopFirstMayHideMenuBarWhileDockRemains() {
        var state = AppPreferences.State(
            primaryExperience: .desktopFirst,
            showsMenuBarItem: true,
            showsDockIcon: true
        )
        state.setMenuBarItemVisible(false)
        XCTAssertFalse(state.showsMenuBarItem)
        XCTAssertTrue(state.showsDockIcon)
    }
}
```

- [ ] **Step 2: Write shared-snapshot tests**

```swift
func testSnapshotExpiresForSystemControlsAfterTwoMinutes() {
    let now = Date(timeIntervalSince1970: 1_000)
    let snapshot = SharedHeadphoneSnapshot.sample(updatedAt: now.addingTimeInterval(-121))
    XCTAssertTrue(snapshot.isStale(at: now, maximumAge: 120))
}

func testStoreAtomicallyRoundTripsSnapshot() throws {
    let store = SharedSnapshotStore(directory: temporaryDirectory())
    try store.write(.sample())
    XCTAssertEqual(try store.read(), .sample())
}
```

- [ ] **Step 3: Run and verify failure**

```bash
make macos-test
```

Expected: FAIL because client/preferences/snapshot types are undefined.

- [ ] **Step 4: Define the session client and conform the actor**

```swift
protocol HeadphoneSessionClient: Sendable {
    var snapshots: AsyncStream<HeadphoneSnapshot> { get }
    func currentSnapshot() async -> HeadphoneSnapshot
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

`ScriptedSessionClient` is an actor with a buffered snapshot stream, recorded calls, and methods `emit(_:)`, `resetCalls()`, and `failNextAction(_:)`.

- [ ] **Step 5: Implement typed preferences**

```swift
enum PrimaryExperience: String, Codable, CaseIterable, Sendable {
    case menuBarFirst
    case desktopFirst
}
```

`AppPreferences` receives an injected `UserDefaults` and persists onboarding completion, selected UUID string, primary experience, menu-bar visibility, battery text, Dock visibility, launch-at-login mirror, automatic reconnect, and diagnostics. All mutators enforce at least one persistent access surface.

- [ ] **Step 6: Implement the shared schema/store**

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

`SharedSnapshotStore` receives a directory URL. Production obtains it with `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)`. Encode to JSON and call `data.write(to: destination, options: .atomic)`. Unknown schema returns `.unsupportedSchema`; forgetting the device removes the file.

- [ ] **Step 7: Build one environment and refactor `ApplicationModel`**

```swift
@MainActor
@Observable
final class AppEnvironment {
    let preferences: AppPreferences
    let snapshotStore: SharedSnapshotStore
    let applicationModel: ApplicationModel
    let activationController: AppActivationController
    let launchAtLoginController: LaunchAtLoginController

    static func make(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppEnvironment
}
```

Initially `activationController`/`launchAtLoginController` may be simple injected adapters created in Task 4; define their protocols now and production implementations later. `ApplicationModel` depends on `any HeadphoneSessionClient`, writes shared state only from confirmed snapshots, preserves last values as stale after disconnect, and triggers a refresh when a visible surface opens with state older than five minutes.

- [ ] **Step 8: Run tests and commit**

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
- UI Test: `apps/macos/UltraController/UITests/OnboardingUITests.swift`

**Interfaces:**
- Consumes: candidates/phase from `ApplicationModel`, preferences, and launch-at-login protocol.
- Produces: resumable setup that completes only after a supported device is verified.

- [ ] **Step 1: Write coordinator tests**

```swift
func testDefaultExperienceIsMenuBarFirst() {
    XCTAssertEqual(OnboardingCoordinator().selectedExperience, .menuBarFirst)
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

- [ ] **Step 3: Implement the coordinator**

```swift
enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome, bluetoothPermission, deviceSelection, behavior, integration
}
```

Persist the unresolved step. Advance from selection only after a snapshot reports supported identity and `writesEnabled == true`. Unsupported candidates display rejection without being saved.

- [ ] **Step 4: Implement permission recovery with public APIs**

`SystemSettingsLauncher` opens `/System/Applications/System Settings.app` using `NSWorkspace.openApplication(at:configuration:)`; copy tells the user to choose Privacy & Security → Bluetooth. A Retry button re-reads authorization through the session/transport state.

- [ ] **Step 5: Implement device selection and behavior choices**

Rows show name, signal-strength label, and advertised-service indicator. Connecting shows progress; persist selected ID only after validation. Behavior uses native selection controls, with Menu Bar First preselected.

- [ ] **Step 6: Implement integration step**

Offer launch at login, menu-bar battery text, and Control Center instructions. Until Plan 4 embeds controls, label Control Center setup `Available after system-control validation` only in development builds; release builds omit that row.

- [ ] **Step 7: Add deterministic UI-test environment**

`AppEnvironment.make(arguments:)` recognizes `--ui-testing-onboarding`, uses isolated `UserDefaults`, a temporary shared store, and `ScriptedSessionClient`. UI test completes all five steps and asserts `overview.root` appears.

- [ ] **Step 8: Run and commit**

```bash
make macos-test
xcodebuild -project apps/macos/UltraController/UltraController.xcodeproj \
  -scheme UltraController -destination 'platform=macOS,arch=arm64' test

git add apps/macos/UltraController/App/Onboarding apps/macos/UltraController/App/Lifecycle/SystemSettingsLauncher.swift apps/macos/UltraController/Tests/Onboarding apps/macos/UltraController/UITests
git commit -m "feat: add native QC Ultra onboarding"
```

### Task 3: Replace the debug harness with the desktop shell, Overview, read-only Modes, and a compilable Settings placeholder

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
- Create: `apps/macos/UltraController/App/Settings/SettingsPlaceholderView.swift`
- Modify: `apps/macos/UltraController/App/Application/UltraControllerApp.swift`
- Test: `apps/macos/UltraController/Tests/Overview/OverviewPresentationTests.swift`
- UI Test: `apps/macos/UltraController/UITests/OverviewUITests.swift`

**Interfaces:**
- Consumes: environment/application model/preferences.
- Produces: buildable `NavigationSplitView` with essential desktop controls; Settings placeholder is explicitly replaced in Task 4.

- [ ] **Step 1: Write Overview presentation tests**

```swift
func testPendingModeLeavesConfirmedSelectionActive() {
    let presentation = OverviewPresentation(
        snapshot: .connected(currentModeID: 1),
        pendingAction: .setMode(2)
    )
    XCTAssertEqual(presentation.confirmedModeID, 1)
    XCTAssertEqual(presentation.pendingModeID, 2)
}

func testDisconnectedBatteryIsMarkedLastKnown() {
    let presentation = OverviewPresentation(snapshot: .disconnected(lastBatteryPercentage: 85))
    XCTAssertTrue(presentation.batteryIsStale)
    XCTAssertEqual(presentation.batteryPercentage, 85)
}
```

- [ ] **Step 2: Run and verify failure**

```bash
make macos-test
```

- [ ] **Step 3: Build the shell with placeholder Settings**

```swift
struct RootView: View {
    @Bindable var model: ApplicationModel

    var body: some View {
        NavigationSplitView {
            List(AppDestination.allCases, selection: $model.destination) { destination in
                Label(destination.title, systemImage: destination.systemImage).tag(destination)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            switch model.destination {
            case .overview: OverviewView(model: model)
            case .modes: ModesListView(model: model)
            case .settings: SettingsPlaceholderView()
            }
        }
        .accessibilityIdentifier("root.navigation")
    }
}
```

`SettingsPlaceholderView` is a standard `ContentUnavailableView` with identifier `settings.placeholder`; it exists solely so this task ends buildable.

- [ ] **Step 4: Implement Overview with native controls**

Use `Form`, `Section`, `LabeledContent`, `Gauge`, `Picker`, `Menu`, standard buttons, and toolbar placement. Include device/phase/time, battery/remaining, current modes, spatial picker when supported, standby values `0,5,10,20,30,60,120`, Reconnect when needed, and destructive Power Off with confirmation. Do not create custom translucent cards.

- [ ] **Step 5: Implement stale/recovery states**

Cached values show `Last updated …` with subordinate styling. Permission denial offers System Settings and Retry; Bluetooth-off offers Retry; out-of-range offers Reconnect; unsupported device offers Forget. Pending controls show a progress indicator and retain confirmed selection.

- [ ] **Step 6: Add read-only Modes**

List modes in device order with active/favorite indicators and verified read-only fields. No edit affordance ships in release until Plan 4.

- [ ] **Step 7: Run tests/build and commit**

```bash
make macos-test
make macos-build
git add apps/macos/UltraController/App/Application apps/macos/UltraController/App/Overview apps/macos/UltraController/App/Modes apps/macos/UltraController/App/Settings/SettingsPlaceholderView.swift apps/macos/UltraController/Tests/Overview apps/macos/UltraController/UITests
git commit -m "feat: add native desktop controller"
```

### Task 4: Replace Settings placeholder and implement launch/Dock lifecycle

**Files:**
- Create: `apps/macos/UltraController/App/Lifecycle/AppActivationDecision.swift`
- Create: `apps/macos/UltraController/App/Lifecycle/AppActivationController.swift`
- Create: `apps/macos/UltraController/App/Lifecycle/LaunchAtLoginController.swift`
- Delete: `apps/macos/UltraController/App/Settings/SettingsPlaceholderView.swift`
- Create: `apps/macos/UltraController/App/Settings/SettingsView.swift`
- Create: `apps/macos/UltraController/App/Settings/GeneralSettingsView.swift`
- Create: `apps/macos/UltraController/App/Settings/DeviceSettingsView.swift`
- Create: `apps/macos/UltraController/App/Settings/AboutView.swift`
- Modify: `apps/macos/UltraController/App/Application/RootView.swift`
- Modify: `apps/macos/UltraController/App/Application/UltraControllerApp.swift`
- Test: `apps/macos/UltraController/Tests/Lifecycle/AppActivationPolicyTests.swift`
- Test: `apps/macos/UltraController/Tests/Lifecycle/LaunchAtLoginControllerTests.swift`
- UI Test: `apps/macos/UltraController/UITests/SettingsUITests.swift`

**Interfaces:**
- Consumes: preferences/application model/`SMAppService.mainApp`.
- Produces: reversible menu-bar-first/desktop-first lifecycle, launch at login, forgetting, and About/privacy UI.

- [ ] **Step 1: Write activation-policy tests**

```swift
func testMenuBarFirstWithoutWindowUsesAccessory() {
    XCTAssertEqual(
        AppActivationDecision(experience: .menuBarFirst, windowVisible: false, showsDockIcon: false).policy,
        .accessory
    )
}

func testOpeningFullAppUsesRegular() {
    XCTAssertEqual(
        AppActivationDecision(experience: .menuBarFirst, windowVisible: true, showsDockIcon: false).policy,
        .regular
    )
}
```

- [ ] **Step 2: Implement documented AppKit transitions**

`AppActivationController` is `@MainActor`, calls `NSApplication.shared.setActivationPolicy`, and activates only when opening a visible window. Closing the final window in menu-bar-first mode returns to accessory; Open Full App switches to regular first.

- [ ] **Step 3: Implement launch-at-login wrapper**

```swift
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}
```

Production wraps `SMAppService.mainApp`. `.requiresApproval` presents `Open Login Items Settings` and calls `SMAppService.openSystemSettingsLoginItems()`.

- [ ] **Step 4: Implement Settings and replace placeholder reference**

General: primary experience, app menu bar, battery text, Dock, launch at login, auto reconnect. Device: selected device/firmware/Forget confirmation. About: version/build, local-only privacy, MIT/upstream attribution, non-affiliation. Change `RootView` settings branch to `SettingsView(model: model)` in this same task.

- [ ] **Step 5: Test access invariant in UI**

Attempt to hide app menu bar while Dock is hidden; assert one surface remains and explanation appears.

- [ ] **Step 6: Run/commit**

```bash
make macos-test
make macos-build
git add apps/macos/UltraController/App/Lifecycle apps/macos/UltraController/App/Settings apps/macos/UltraController/App/Application apps/macos/UltraController/Tests/Lifecycle apps/macos/UltraController/UITests
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
- Consumes: the same environment/application model used by desktop.
- Produces: optional `MenuBarExtra` with essential quick controls and explicit Quit.

- [ ] **Step 1: Write label/presentation tests**

```swift
func testLabelIncludesBatteryOnlyWhenConnectedAndEnabled() {
    XCTAssertEqual(MenuBarPresentation(snapshot: .connected(batteryPercentage: 85), showsBattery: true).labelText, "85%")
    XCTAssertNil(MenuBarPresentation(snapshot: .connected(batteryPercentage: 85), showsBattery: false).labelText)
    XCTAssertNil(MenuBarPresentation(snapshot: .disconnected(lastBatteryPercentage: 85), showsBattery: true).labelText)
}
```

- [ ] **Step 2: Run and verify failure**

```bash
make macos-test
```

- [ ] **Step 3: Implement dynamic label and `MenuBarExtra`**

Use a headphone SF Symbol; battery text only while connected. Build `.menuBarExtraStyle(.window)` content for device/phase, battery, modes, spatial, Reconnect, Power Off confirmation, Open Full App, Settings, and Quit. No advanced editing.

- [ ] **Step 4: Implement explicit Quit**

Call a bounded model/session shutdown API, then `NSApplication.shared.terminate(nil)`. Window closure never invokes Quit.

- [ ] **Step 5: Run physical menu-bar smoke test and commit**

Verify menu-bar-only launch, quick controls, Open Full App, window close, Settings, and Quit; desktop/menu bar must update from the same physical notification.

```bash
make macos-test
make macos-build
git add apps/macos/UltraController/App/MenuBar apps/macos/UltraController/App/Application/UltraControllerApp.swift apps/macos/UltraController/Tests/MenuBar apps/macos/UltraController/UITests
git commit -m "feat: add native menu-bar controller"
```

### Task 6: Complete localization, commands, and accessibility

**Files:**
- Create: `apps/macos/UltraController/App/Resources/Localizable.xcstrings`
- Create: `apps/macos/UltraController/App/Resources/L10n.swift`
- Create: `apps/macos/UltraController/App/Application/UltraControllerActionSet.swift`
- Create: `apps/macos/UltraController/App/Application/FocusedValues+UltraController.swift`
- Create: `apps/macos/UltraController/App/Application/UltraControllerCommands.swift`
- Create: `apps/macos/UltraController/Scripts/check-localized-strings.sh`
- Modify: every user-facing view from Tasks 2–5.
- UI Test: `apps/macos/UltraController/UITests/AccessibilitySmokeUITests.swift`

**Interfaces:**
- Consumes: current UI.
- Produces: String Catalog-backed English copy, keyboard commands, stable accessibility IDs/labels, and appearance coverage.

- [ ] **Step 1: Define String Catalog keys and constants**

Create keys for onboarding, connection/errors, mode/spatial/standby, pending/results, Settings/About, Power Off, menu commands, and stale state. `L10n.swift` exposes `LocalizedStringResource` constants:

```swift
enum L10n {
    static let reconnect = LocalizedStringResource("action.reconnect", defaultValue: "Reconnect")
    static let powerOff = LocalizedStringResource("action.powerOff", defaultValue: "Power Off")
    static let overviewTitle = LocalizedStringResource("navigation.overview", defaultValue: "Overview")
}
```

Views use these constants or keyed localized interpolation; no normal UI displays raw BMAP vocabulary.

- [ ] **Step 2: Define focused actions before commands**

```swift
struct UltraControllerActionSet {
    let reconnect: () -> Void
    let openOverview: () -> Void
    let openModes: () -> Void
}

private struct UltraControllerActionsKey: FocusedValueKey {
    typealias Value = UltraControllerActionSet
}

extension FocusedValues {
    var ultraControllerActions: UltraControllerActionSet? {
        get { self[UltraControllerActionsKey.self] }
        set { self[UltraControllerActionsKey.self] = newValue }
    }
}
```

- [ ] **Step 3: Add keyboard commands**

```swift
struct UltraControllerCommands: Commands {
    @FocusedValue(\.ultraControllerActions) private var actions

    var body: some Commands {
        CommandMenu("Headphones") {
            Button(L10n.reconnect) { actions?.reconnect() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Divider()
            Button(L10n.overviewTitle) { actions?.openOverview() }
                .keyboardShortcut("1", modifiers: .command)
            Button(LocalizedStringResource("navigation.modes", defaultValue: "Modes")) {
                actions?.openModes()
            }
            .keyboardShortcut("2", modifiers: .command)
        }
    }
}
```

- [ ] **Step 4: Add localization audit**

`check-localized-strings.sh` fails on capitalized literal user copy in `Text`, `Button`, `Label`, `navigationTitle`, `alert`, and `confirmationDialog`, while allowing accessibility IDs, SF Symbol names, format strings, and test fixtures. Run before conversion and confirm failure; run after conversion and confirm pass.

- [ ] **Step 5: Add accessibility semantics**

Battery announces percent/remaining; connection and stale/pending are not color-only; mode controls announce confirmed vs pending; errors focus/announce recovery; Power Off confirmation is keyboard reachable; icons have labels when system may omit text.

- [ ] **Step 6: Add appearance/accessibility test matrix**

Automated test launch configurations cover light/dark plus app-injected preview flags for contrast/transparency/motion view behavior. Complete one manual pass using actual macOS Increased Contrast, Reduce Transparency, Reduce Motion, VoiceOver, and keyboard-only operation; record it in Plan 5 release evidence.

- [ ] **Step 7: Run and commit**

```bash
chmod +x apps/macos/UltraController/Scripts/check-localized-strings.sh
apps/macos/UltraController/Scripts/check-localized-strings.sh
make macos-test
make macos-build
git add apps/macos/UltraController/App apps/macos/UltraController/UITests apps/macos/UltraController/Scripts
git commit -m "feat: complete native accessibility and localization"
```

### Task 7: Run the Plan 3 checkpoint

**Files:**
- Verify all Plan 3 product surfaces/tests.

**Interfaces:**
- Produces for Plan 4: complete essential desktop/menu-bar product, stable preferences/shared snapshot, and injectable UI-test environment.

- [ ] **Step 1: Run all tests and Release build**

```bash
cargo test --workspace
make macos-test-core
make macos-test
xcodebuild -project apps/macos/UltraController/UltraController.xcodeproj \
  -scheme UltraController -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
```

- [ ] **Step 2: Run product-level physical smoke test**

Verify fresh onboarding, both launch modes, battery/mode/standby/spatial display, confirmed mutations, Power Off confirmation/disconnect, menu-bar-only use, window reopen, Settings, launch-at-login status, sleep/wake, and out-of-range recovery.

- [ ] **Step 3: Verify one Bluetooth owner**

```bash
MATCHES="$(grep -R "CBCentralManager(" apps/macos/UltraController/App --include='*.swift' || true)"
test "$(printf '%s\n' "$MATCHES" | sed '/^$/d' | wc -l | tr -d ' ')" = "1"
printf '%s\n' "$MATCHES" | grep -q 'CoreBluetoothTransport.swift'
```

- [ ] **Step 4: Verify localization/accessibility gates**

```bash
apps/macos/UltraController/Scripts/check-localized-strings.sh
make macos-test | tee /tmp/ultra-controller-tests.log
! grep -q '0 tests executed' /tmp/ultra-controller-tests.log
```

Plan 3 is complete when essential operation requires no Terminal and every visible surface derives from one confirmed session snapshot.
