# Ultra Controller Advanced Modes and System Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Validate and ship only safe advanced QC Ultra mode edits, then add WidgetKit Control Center and system-menu-bar controls through the one Bluetooth-owning main app process.

**Architecture:** Gate A creates an exact firmware profile and fixtures before production mutation code exists. Mode Apply uses a confirmed draft, verified field rules, ordered writes, and complete read-back reconciliation. Gate B then proves WidgetKit → App Intent → main-process behavior. Shared snapshot types move into a Foundation-only `ControlSupport` package used by app and extension; the extension never owns Bluetooth.

**Tech Stack:** Swift 6, SwiftUI, WidgetKit Controls, App Intents, XCTest/XCUITest, JSON validation profiles, physical QC Ultra hardware.

**Spec:** `docs/superpowers/specs/2026-08-29-qc-ultra-macos-controller-design.md`

## Global Constraints

- Plans 1–3 must pass first.
- QC Ultra Headphones Gen 1 is the only writable hardware family.
- Never expose an advanced field until Gate A proves deterministic read/write/read-back, unrelated-byte preservation, and safe restoration.
- Prefer field-specific writes. Full ModeConfig writes are allowed only when exact physical validation proves the operator/layout and all untouched bytes remain identical.
- No firmware, pairing, reset, raw command console, XPC helper, daemon, or second BLE owner.
- Re-read the mode immediately before Apply; stale drafts never blind-overwrite.
- Power Off remains absent from system controls.
- Gate B has exactly three production conclusions: `directMainProcess`, `openAppAlways`, or `controlsExcluded`.
- Revalidate Gate B against final macOS 27/Xcode 27 before public release.

---

## File Map

| Path | Responsibility |
|---|---|
| `App/Diagnostics/AdvancedModeProbe/*` | Debug-only one-field physical validation. |
| `App/Resources/VerifiedModeFieldProfile.json` | Exact device/firmware allowlist produced by Gate A. |
| `docs/protocol/qc-ultra-advanced-mode-validation.md` | Gate A repetitions, diffs, restoration, and decisions. |
| `fixtures/bmap/advanced/*` | Sanitized verified advanced fixtures. |
| `Packages/HeadphoneCore/.../ModeMutation/*` | Pure field/profile/diff/packet planning. |
| `App/Session/ModeDraft.swift` | Source revision/raw payload and proposed changes. |
| `App/Session/ModeApplyResult.swift` | Complete, conflict, partial, and unknown results. |
| `App/Modes/*` | Verified profile-driven editor. |
| `Packages/ControlSupport/*` | Shared snapshot store/schema, control entities, requests, and lifecycle policy. |
| `ControlsExtension/*` | WidgetKit providers/controls only. |
| `App/Intents/*` | Main-app intent dependency and actions. |
| `docs/platform/control-center-lifecycle.md` | Gate B matrix and selected policy. |

### Task 1: Execute Gate A and produce the exact verified-field profile

**Files:**
- Create: `apps/macos/UltraController/App/Diagnostics/AdvancedModeProbe/AdvancedFieldCandidate.swift`
- Create: `.../AdvancedModeProbeModel.swift`
- Create: `.../AdvancedModeProbeRunner.swift`
- Create: `.../AdvancedModeProbeView.swift`
- Create: `apps/macos/UltraController/App/Resources/VerifiedModeFieldProfile.json`
- Create: `docs/protocol/qc-ultra-advanced-mode-validation.md`
- Create only for admitted/rejection cases: `fixtures/bmap/advanced/*.json`
- Modify: `apps/macos/UltraController/App/Settings/SettingsView.swift`
- Test: `apps/macos/UltraController/Tests/Diagnostics/AdvancedModeProbeModelTests.swift`

**Interfaces:**
- Consumes: connected production session and complete raw `AudioMode` payloads.
- Produces: one exact firmware profile and pass/reject/unsupported decision per field.

- [ ] **Step 1: Create a valid not-yet-run profile schema**

```json
{
  "schemaVersion": 1,
  "deviceFamily": "qc-ultra-headphones-gen1",
  "validationState": "notRun",
  "firmware": null,
  "validatedAt": null,
  "modeConfigFunction": { "functionBlock": 31, "function": 6 },
  "safeWriteOrder": [],
  "fields": {}
}
```

A verified field uses:

```json
"cncLevel": {
  "status": "verified",
  "writeStrategy": "fullModeConfigSetGet",
  "functionBlock": 31,
  "function": 6,
  "operator": 2,
  "payloadOffset": 42,
  "minimum": 0,
  "maximum": 10,
  "allowedValues": null,
  "reversible": true,
  "repeatWriteReadCycles": 10,
  "reconnectCycles": 3,
  "powerCycles": 2,
  "fixturePrefix": "qc-ultra-gen1-cnc-level"
}
```

Rejected/unsupported/unvalidated fields remain in `fields` with a concrete status/reason and no production strategy.

- [ ] **Step 2: Write probe safety tests**

```swift
func testRunnerRequiresOriginalConfiguration() {
    var model = AdvancedModeProbeModel()
    model.select(candidate: .cncLevel)
    XCTAssertFalse(model.canBeginValidation)
    model.captureOriginal(.fixtureCustomMode)
    XCTAssertTrue(model.canBeginValidation)
}

func testBuiltInModeIsNotDefaultTarget() {
    XCTAssertFalse(AdvancedModeProbeRunner.isSafeTarget(.fixture(index: 0, isUserConfigurable: false)))
}

func testRestorationFailureLocksWrites() {
    var model = AdvancedModeProbeModel()
    model.record(.restorationFailed(field: .windBlock))
    XCTAssertTrue(model.isWriteLocked)
}
```

Run `make macos-test`; expected failure until types exist.

- [ ] **Step 3: Implement bounded candidate set and runner**

```swift
enum AdvancedFieldCandidate: String, CaseIterable, Codable, Sendable {
    case modeName, favorite, cncLevel, autoCNC, windBlock, spatialAudioMode, ancEnabled
}
```

For one disposable user-configurable mode and one field, runner:

1. reads/stores full original payload
2. verifies safe target and switches away if active
3. mutates only the hypothesized field
4. writes once, reads complete mode, computes byte diff
5. rejects unexpected known/opaque changes
6. restores original and confirms
7. locks on restoration failure
8. completes ten write/read/restore cycles
9. completes three reconnect read checks
10. completes two power-cycle persistence/restoration checks

No free-form hex UI; `#if DEBUG` only.

- [ ] **Step 4: Expose hidden validation UI**

When diagnostics is enabled, Settings offers `Advanced Mode Validation…` with explicit warning. Display original/requested/confirmed payload diff, cycle counts, restoration state, and Stop. Require the user to select a custom mode.

- [ ] **Step 5: Execute every candidate physically**

Record firmware, capability bit, exact operator/payload/range, response, read-back, changed offsets, restoration, ten cycles, three reconnects, two power cycles. Untestable means `unvalidated`, therefore excluded.

- [ ] **Step 6: Write evidence with one subsection per candidate**

`docs/protocol/qc-ultra-advanced-mode-validation.md` headings:

```markdown
# QC Ultra Advanced Mode Validation
## Environment
## Candidate result table
## Mode name evidence
## Favorite evidence
## CNC level evidence
## Auto-CNC evidence
## Wind block evidence
## Spatial/Immersive behavior evidence
## ANC enabled evidence
## Restoration incidents
## Rejected, unsupported, and unvalidated fields
## Production profile checksum
## Gate A conclusion
```

Each evidence subsection records original/requested/confirmed payload, changed offsets, unrelated offsets, repetitions, and restoration.

- [ ] **Step 7: Finalize/verify profile and commit**

Set `validationState: "complete"`, exact firmware/time/order/rules, then:

```bash
python3 -m json.tool apps/macos/UltraController/App/Resources/VerifiedModeFieldProfile.json >/dev/null
shasum -a 256 apps/macos/UltraController/App/Resources/VerifiedModeFieldProfile.json
! grep -E '"validationState": "notRun"|TBD|TODO|REPLACE_ME' \
  apps/macos/UltraController/App/Resources/VerifiedModeFieldProfile.json \
  docs/protocol/qc-ultra-advanced-mode-validation.md
make macos-test

git add apps/macos/UltraController/App/Diagnostics/AdvancedModeProbe \
  apps/macos/UltraController/App/Resources/VerifiedModeFieldProfile.json \
  apps/macos/UltraController/App/Settings/SettingsView.swift \
  apps/macos/UltraController/Tests/Diagnostics \
  docs/protocol/qc-ultra-advanced-mode-validation.md fixtures/bmap/advanced
git commit -m "test: validate QC Ultra advanced mode writes"
```

### Task 2: Implement pure verified mutation planning

**Files:**
- Create: `apps/macos/UltraController/Packages/HeadphoneCore/Sources/HeadphoneCore/ModeMutation/VerifiedModeField.swift`
- Create: `.../VerifiedModeFieldProfile.swift`
- Create: `.../ModeFieldChange.swift`
- Create: `.../AudioModeMutationPlan.swift`
- Create: `.../AudioModeMutationPlanner.swift`
- Create: `.../ModeMutationError.swift`
- Modify: `.../Protocol/AudioModeMessages.swift`
- Test: `.../Tests/HeadphoneCoreTests/VerifiedModeFieldProfileTests.swift`
- Test: `.../AudioModeMutationPlannerTests.swift`

**Interfaces:**
- Consumes: confirmed raw mode, desired changes, exact firmware profile.
- Produces: ordered packets/expected payload; rejects unverified field/firmware or opaque-byte damage.

- [ ] **Step 1: Write tests from actual Gate A rules**

Assert exact request hex and changed offsets for every verified field. Assert rejected/unvalidated fields throw `.fieldNotVerified`. Assert full-payload mutation changes only profile-listed offsets.

```swift
func testUnverifiedFieldCannotProduceMutation() throws {
    let planner = AudioModeMutationPlanner(profile: .fixtureOnlyCNCVerified)
    XCTAssertThrowsError(try planner.plan(from: .fixtureCustomMode, changes: [.windBlock(true)])) {
        XCTAssertEqual($0 as? ModeMutationError, .fieldNotVerified(.windBlock))
    }
}
```

- [ ] **Step 2: Implement profile and change types**

```swift
public enum VerifiedModeField: String, Codable, Sendable, CaseIterable {
    case modeName, favorite, cncLevel, autoCNC, windBlock, spatialAudioMode, ancEnabled
}

public enum ModeFieldChange: Sendable, Equatable {
    case modeName(String), favorite(Bool), cncLevel(UInt8), autoCNC(Bool)
    case windBlock(Bool), spatialAudioMode(SpatialAudioMode), ancEnabled(Bool)
}

public struct AudioModeMutationPlan: Sendable, Equatable {
    public let sourceModeID: UInt8
    public let sourceRawPayload: [UInt8]
    public let changes: [ModeFieldChange]
    public let packets: [BMAPPacket]
    public let expectedRawPayload: [UInt8]
}
```

Profile loading requires schema/device family/exact firmware/complete validation. Planner validates values/names, uses `safeWriteOrder`, preserves all other bytes, and emits only physically verified strategies.

- [ ] **Step 3: Implement exact write builder only from Gate A**

When Gate A verified full ModeConfig SetGet:

```swift
public static func setConfiguration(validatedPayload: [UInt8], expectedLength: Int) throws -> BMAPPacket {
    guard validatedPayload.count == expectedLength else {
        throw ModeMutationError.unexpectedPayloadLength(validatedPayload.count)
    }
    return BMAPPacket(functionBlock: .audioModes, function: 0x06,
                      operator: .setGet, payload: validatedPayload)
}
```

If physical evidence says another operator/function/layout, encode that exact result instead and assert fixture bytes.

- [ ] **Step 4: Run parity tests and commit**

```bash
make macos-test-core
cargo test --workspace
git add apps/macos/UltraController/Packages/HeadphoneCore fixtures/bmap/advanced
git commit -m "feat: add verified mode mutation planner"
```

### Task 3: Implement source-revision conflict detection and multi-field Apply

**Files:**
- Create: `apps/macos/UltraController/App/Session/ModeDraft.swift`
- Create: `apps/macos/UltraController/App/Session/ModeApplyResult.swift`
- Create: `apps/macos/UltraController/App/Session/ModeApplyError.swift`
- Create: `apps/macos/UltraController/App/Session/ModeConflict.swift`
- Modify: `apps/macos/UltraController/App/Session/HeadphoneSession.swift`
- Modify: `apps/macos/UltraController/App/Application/HeadphoneSessionClient.swift`
- Modify: `apps/macos/UltraController/App/Application/ApplicationModel.swift`
- Test: `apps/macos/UltraController/Tests/Session/ModeApplySessionTests.swift`
- Test: `apps/macos/UltraController/Tests/Application/ModeDraftApplicationTests.swift`

**Interfaces:**
- Produces: `makeModeDraft(id:)`, `applyModeDraft(_:)`, complete/partial/conflict/unknown results, refreshed authoritative state.

- [ ] **Step 1: Write stale/partial tests**

A stale mode payload produces `.conflict` with zero mutating writes. Script a first-field success/second-field error and assert `.partial(confirmed:failedFields:)` contains actual read-back.

- [ ] **Step 2: Define draft/outcome**

```swift
struct ModeDraft: Equatable, Sendable {
    let modeID: UInt8
    let sourceSessionRevision: UInt64
    let sourceRawPayload: [UInt8]
    let sourceMode: AudioMode
    var changes: [VerifiedModeField: ModeFieldChange]

    func changing(_ change: ModeFieldChange) -> ModeDraft
}

enum ModeApplyResult: Equatable, Sendable {
    case unchanged(AudioMode)
    case complete(AudioMode)
    case partial(confirmed: AudioMode, failedFields: [VerifiedModeField])
}
```

Implement `changing(_:)` by replacing the field's previous change and returning a copy.

- [ ] **Step 3: Implement preflight and Apply**

Immediately GET full ModeConfig. If source raw payload differs, throw conflict before writes. Otherwise build exact-firmware plan, serialize through command queue, stop after first failure, always GET full final configuration, publish it, and return complete/partial. If final GET fails, throw `.outcomeUnknown` and mark stale. No v1 rollback unless a later separately tested path is explicitly enabled.

- [ ] **Step 4: Update ApplicationModel**

Add begin/update/apply/discard. Preserve proposed values on conflict separately from confirmed latest state; expose Reload and Review Changes, never Force Overwrite.

- [ ] **Step 5: Run/commit**

```bash
make macos-test
git add apps/macos/UltraController/App/Session apps/macos/UltraController/App/Application apps/macos/UltraController/Tests/Session apps/macos/UltraController/Tests/Application
git commit -m "feat: add verified advanced mode apply"
```

### Task 4: Build the native profile-driven mode editor

**Files:**
- Replace: `apps/macos/UltraController/App/Modes/ModesListView.swift`
- Create: `apps/macos/UltraController/App/Modes/ModeEditorView.swift`
- Create: `.../ModeFieldEditor.swift`
- Create: `.../ModeEditPresentation.swift`
- Create: `.../ModeApplyResultView.swift`
- Create: `.../ModeConflictView.swift`
- Modify: `apps/macos/UltraController/App/Resources/Localizable.xcstrings`
- Test: `apps/macos/UltraController/Tests/Modes/ModeEditPresentationTests.swift`
- UI Test: `apps/macos/UltraController/UITests/ModeEditorUITests.swift`

**Interfaces:**
- Consumes: application draft/profile/apply result.
- Produces: native controls only for verified fields.

- [ ] **Step 1: Write profile visibility/Apply-state tests**

Use actual Gate A profile. Assert only verified writable fields appear; unchanged, invalid, disconnected, or pending draft cannot Apply.

- [ ] **Step 2: Implement controls**

Name uses verified UTF-8 byte limit; booleans use Toggle; CNC uses integer Slider/Stepper or Picker; spatial uses allowed-value Picker; read-only values use `LabeledContent`. Rejected/unvalidated/mismatched-firmware fields are absent.

- [ ] **Step 3: Implement unsaved/conflict/partial UX**

Leaving changed draft offers Apply/Discard/Cancel. Conflict compares latest/proposed and offers Reload/Review/Cancel. Partial result names failed fields and shows confirmed final values. Announce apply start/result and maintain keyboard focus.

- [ ] **Step 4: Run tests, physical smoke test, commit**

Change each admitted field once, confirm, reconnect, restore original.

```bash
make macos-test
xcodebuild -project apps/macos/UltraController/UltraController.xcodeproj \
  -scheme UltraController -destination 'platform=macOS,arch=arm64' test
git add apps/macos/UltraController/App/Modes apps/macos/UltraController/App/Resources/Localizable.xcstrings apps/macos/UltraController/Tests/Modes apps/macos/UltraController/UITests
git commit -m "feat: add verified advanced mode editor"
```

### Task 5: Move shared control support into one package and execute Gate B

**Files:**
- Modify: `apps/macos/UltraController/project.yml`
- Create: `apps/macos/UltraController/Config/Controls.entitlements`
- Create: `apps/macos/UltraController/Packages/ControlSupport/Package.swift`
- Move: `apps/macos/UltraController/App/Application/SharedHeadphoneSnapshot.swift` → `apps/macos/UltraController/Packages/ControlSupport/Sources/ControlSupport/SharedHeadphoneSnapshot.swift`
- Move: `apps/macos/UltraController/App/Application/SharedSnapshotStore.swift` → `apps/macos/UltraController/Packages/ControlSupport/Sources/ControlSupport/SharedSnapshotStore.swift`
- Create: `.../ControlActionRequest.swift`
- Create: `.../ControlActionRequestStore.swift`
- Create: `.../ControlLifecyclePolicy.swift`
- Modify imports: `App/Application/ApplicationModel.swift`, `App/Application/AppEnvironment.swift`
- Create: `apps/macos/UltraController/App/Intents/HeadphoneIntentController.swift`
- Create: `apps/macos/UltraController/App/Intents/ReconnectHeadphonesIntent.swift`
- Create: `apps/macos/UltraController/App/Intents/ReconnectOpenAppIntent.swift`
- Create: `apps/macos/UltraController/ControlsExtension/UltraControllerControlsBundle.swift`
- Create: `apps/macos/UltraController/ControlsExtension/ReconnectControl.swift`
- Create: `docs/platform/control-center-lifecycle.md`
- Test: `apps/macos/UltraController/Packages/ControlSupport/Tests/ControlSupportTests/ControlLifecyclePolicyTests.swift`
- Test: `apps/macos/UltraController/Tests/Intents/ReconnectHeadphonesIntentTests.swift`

**Interfaces:**
- Consumes: one shared App Group and main-app session client.
- Produces: exactly one shared schema/store and measured policy `directMainProcess`, `openAppAlways`, or `controlsExcluded`.

- [ ] **Step 1: Create ControlSupport package and physically move shared files**

Foundation-only package; no CoreBluetooth. Add ControlSupport dependency to app and extension in `project.yml`, remove old app files in same commit, update imports, and prove one declaration:

```bash
test "$(grep -R 'struct SharedHeadphoneSnapshot' apps/macos/UltraController --include='*.swift' | wc -l | tr -d ' ')" = "1"
```

- [ ] **Step 2: Add extension target/entitlements**

Extension bundle ID `dev.densedevkev.ultracontroller.controls`; entitlements: sandbox + App Group only. Embed in app. Set `APPLICATION_EXTENSION_API_ONLY = YES` for extension target.

- [ ] **Step 3: Implement main-app dependency and minimal direct intent**

```swift
@MainActor
final class HeadphoneIntentController {
    private let session: any HeadphoneSessionClient
    init(session: any HeadphoneSessionClient) { self.session = session }
    func reconnect() async { await session.manualReconnect() }
}
```

Register once with `AppDependencyManager.shared.add(dependency:)`.

Against final SDK:

```swift
struct ReconnectHeadphonesIntent: AppIntent {
    static let title: LocalizedStringResource = "Reconnect Headphones"
    static let openAppWhenRun = false
    static var allowedExecutionTargets: IntentExecutionTargets { [.main] }
    @Dependency private var controller: HeadphoneIntentController

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await controller.reconnect()
        return .result(dialog: "Reconnect started.")
    }
}
```

If final public spelling differs, use exact final API and document it.

- [ ] **Step 4: Implement explicit open-app fallback intent**

`ReconnectOpenAppIntent` has `openAppWhenRun = true`, writes a `ControlActionRequest(kind:.reconnect, createdAt:.now, expiresAt:+30s, id:UUID())` into App Group before returning. Main app consumes each ID once at launch/activation, deletes expired/consumed requests, starts bounded reconnect, and navigates Overview. No dynamic process-residency guess.

- [ ] **Step 5: Implement one Reconnect control and build tests**

Use `StaticControlConfiguration`/`ControlWidgetButton`, provider reads shared snapshot only. Build/sign embedded extension. Test direct intent with injected controller and fallback request expiry/one-time consumption.

- [ ] **Step 6: Execute Gate B matrix**

Test visible, windowless, app-menu-bar-only, terminated, disconnected, unavailable, post-sleep, and stale snapshot. Diagnostics prove one central/session. Record process launch, window behavior, action result, reload, and duplicate owner.

- [ ] **Step 7: Select one policy and write evidence**

`docs/platform/control-center-lifecycle.md` headings:

```markdown
# Control Center Lifecycle Validation
## Environment
## Test matrix
## Final public APIs used
## directMainProcess observations
## openAppAlways observations
## Selected production policy
## Unsupported lifecycle states
## Gate B conclusion
```

- `directMainProcess`: required states reliable.
- `openAppAlways`: direct is unreliable in any required state; every control uses open-app request flow.
- `controlsExcluded`: neither finite policy is reliable; remove extension from v1.

No hybrid “when resident” policy based on stale cache/process guessing.

- [ ] **Step 8: Commit Gate B**

```bash
! grep -E 'TBD|TODO|REPLACE_ME' docs/platform/control-center-lifecycle.md
make macos-test
git add apps/macos/UltraController/project.yml apps/macos/UltraController/Config/Controls.entitlements apps/macos/UltraController/Packages/ControlSupport apps/macos/UltraController/App/Application apps/macos/UltraController/App/Intents apps/macos/UltraController/ControlsExtension apps/macos/UltraController/Tests/Intents docs/platform/control-center-lifecycle.md
git commit -m "test: validate Control Center main-process lifecycle"
```

### Task 6: Implement production Set/Cycle/Immersive/Reconnect controls

**Files:**
- Create: `Packages/ControlSupport/Sources/ControlSupport/AudioModeEntity.swift`
- Create: `.../AudioModeEntityQuery.swift`
- Create: `.../ControlOutcome.swift`
- Create: `App/Intents/SetAudioModeIntent.swift`
- Create: `App/Intents/CycleAudioModeIntent.swift`
- Create: `App/Intents/SetImmersiveAudioIntent.swift`
- Modify: `App/Intents/HeadphoneIntentController.swift`
- Create: `ControlsExtension/AudioModeControl.swift`
- Create: `ControlsExtension/CycleAudioModeControl.swift`
- Create: `ControlsExtension/ImmersiveAudioControl.swift`
- Modify: `ControlsExtension/UltraControllerControlsBundle.swift`
- Modify: `App/Resources/Localizable.xcstrings`
- Test: `Packages/ControlSupport/Tests/ControlSupportTests/AudioModeEntityQueryTests.swift`
- Test: `Tests/Intents/SystemControlIntentTests.swift`

**Interfaces:**
- Consumes: selected Gate B policy/shared snapshot/main session.
- Produces: Set Mode, Cycle, Immersive toggle, Reconnect; no Power Off.

- [ ] **Step 1: Write stable-ID/order/toggle tests**

Mode entities use device index IDs, cycle uses reported order/wrap, stale configured ID errors instead of name matching, and immersive On restores last confirmed non-off mode.

- [ ] **Step 2: Implement entities and controller actions**

`AudioModeEntityQuery` reads App Group modes. Controller obtains current snapshot from session, sets mode, cycles reported order, toggles spatial using last confirmed non-off value, and reconnects. Success returns only after existing session confirmation.

- [ ] **Step 3: Implement intents according to one selected policy**

For `directMainProcess`, use main-target intents. For `openAppAlways`, each intent writes an expiring request and opens app; app consumes once. For `controlsExcluded`, do not implement/ship this task and record scope removal. Never silently mix policies.

- [ ] **Step 4: Implement WidgetKit controls**

Set Mode uses `AppIntentControlConfiguration` with entity parameter. Cycle/Reconnect use buttons. Immersive uses toggle. Providers show cached/stale/disconnected state honestly and import only ControlSupport/WidgetKit/AppIntents.

- [ ] **Step 5: Reload controls after confirmed shared snapshot**

Use final public WidgetKit reload API; expected current spelling:

```swift
ControlCenter.shared.reloadControls(ofKind: AudioModeControl.kind)
ControlCenter.shared.reloadControls(ofKind: CycleAudioModeControl.kind)
ControlCenter.shared.reloadControls(ofKind: ImmersiveAudioControl.kind)
ControlCenter.shared.reloadControls(ofKind: ReconnectControl.kind)
```

Record exact final API in Gate B evidence.

- [ ] **Step 6: Run automated/physical tests and commit**

Cover connected, unavailable, stale ID, missing selection, request expiry/consumption, cycle order, immersive restoration, and absence of Power Off. Test Control Center/system-pinned controls in every supported state.

```bash
make macos-test
xcodebuild -project apps/macos/UltraController/UltraController.xcodeproj \
  -scheme UltraController -destination 'platform=macOS,arch=arm64' test
git add apps/macos/UltraController/Packages/ControlSupport apps/macos/UltraController/App/Intents apps/macos/UltraController/ControlsExtension apps/macos/UltraController/App/Resources/Localizable.xcstrings apps/macos/UltraController/Tests/Intents docs/platform/control-center-lifecycle.md
git commit -m "feat: add verified macOS system controls"
```

### Task 7: Run the Plan 4 checkpoint

**Files:**
- Verify profile/evidence/editor/lifecycle policy/system controls.

**Interfaces:**
- Produces for Plan 5: complete evidence-backed feature set.

- [ ] **Step 1: Validate evidence/profile**

```bash
python3 -m json.tool apps/macos/UltraController/App/Resources/VerifiedModeFieldProfile.json >/dev/null
! grep -E '"validationState": "notRun"|TBD|TODO|REPLACE_ME' \
  apps/macos/UltraController/App/Resources/VerifiedModeFieldProfile.json \
  docs/protocol/qc-ultra-advanced-mode-validation.md \
  docs/platform/control-center-lifecycle.md
```

- [ ] **Step 2: Run full suite twice**

```bash
cargo test --workspace
make macos-test-core
make macos-test
make macos-test
```

- [ ] **Step 3: Verify extension isolation and no destructive intent**

```bash
! grep -R -E 'import CoreBluetooth|CBCentralManager|CBPeripheral|HeadphoneTransport' \
  apps/macos/UltraController/ControlsExtension \
  apps/macos/UltraController/Packages/ControlSupport
! grep -R -E 'PowerOffIntent|powerOff\(' \
  apps/macos/UltraController/ControlsExtension \
  apps/macos/UltraController/App/Intents
```

- [ ] **Step 4: Run physical acceptance**

Every visible advanced field confirms/restores. Partial UI shows actual state. Every shipped system control matches Gate B policy. Desktop/app menu bar/system controls converge on one state; diagnostics show one central/session.

Plan 4 completes only when production behavior exactly matches both committed gate conclusions.
