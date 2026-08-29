# Ultra Controller Advanced Modes and System Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Validate and ship only safe advanced QC Ultra mode edits, then add WidgetKit Control Center and system-menu-bar controls through the one Bluetooth-owning main app process.

**Architecture:** Gate A produces a firmware-specific verified-field profile and packet fixtures before production mutation code exists. The mode editor generates a minimal ordered mutation plan from a confirmed draft and reconciles the full device response after Apply. Gate B separately proves the WidgetKit → App Intent → main-process lifecycle; the extension renders cached state only and either reaches the existing `HeadphoneSession` or uses the approved open-app fallback.

**Tech Stack:** Swift 6, SwiftUI, WidgetKit Controls, App Intents, XCTest/XCUITest, CoreBluetooth through the existing session only, JSON validation profiles, physical QC Ultra hardware.

**Spec:** `docs/superpowers/specs/2026-08-29-qc-ultra-macos-controller-design.md`

## Global Constraints

- Plans 1–3 must pass before this plan begins.
- Keep QC Ultra Headphones Gen 1 as the only writable hardware profile.
- Never expose an advanced field until Gate A proves deterministic read, write, read-back, unrelated-field preservation, and safe reversal.
- Prefer field-specific writes. A full ModeConfig write is allowed only when the original raw payload is preserved byte-for-byte except for verified offsets.
- Do not write firmware, pairing, reset, or arbitrary raw BMAP commands.
- Advanced Apply is one user operation but is not represented as hardware-atomic.
- Re-read the target mode immediately before Apply and reject stale drafts instead of blind overwrite.
- The controls extension never imports CoreBluetooth, creates `CBCentralManager`, or encodes BMAP.
- Power Off remains unavailable from Control Center and system-pinned controls.
- If Gate B fails for a lifecycle state, use the documented open-app fallback or omit that action in that state; do not add XPC, a helper, or a daemon.
- Validate Gate B again against the final macOS 27 and Xcode 27 SDK before public release.

---

## File Map

| Path | Responsibility |
|---|---|
| `App/Diagnostics/AdvancedModeProbe/*` | Debug-only, bounded one-field-at-a-time physical validation harness. |
| `App/Resources/VerifiedModeFieldProfile.json` | Generated/committed allowlist of fields proven safe for one device/firmware profile. |
| `docs/protocol/qc-ultra-advanced-mode-validation.md` | Human-readable Gate A evidence, reversals, repetitions, and failures. |
| `fixtures/bmap/advanced/*` | Sanitized request/response fixtures admitted by Gate A. |
| `Packages/HeadphoneCore/.../ModeMutation/*` | Profile model, field changes, diffing, and packet construction. |
| `App/Session/ModeDraft.swift` | Draft revision and user edits. |
| `App/Session/ModeApplyResult.swift` | Complete, conflict, partial, and unknown outcomes. |
| `App/Modes/*` | Capability/profile-driven native mode editor. |
| `Packages/ControlSupport/*` | App/extension-safe snapshot entities, intent requests, and fallback contracts. |
| `ControlsExtension/*` | WidgetKit controls and providers; no Bluetooth code. |
| `App/Intents/*` | Main-process intent controller and App Intent implementations. |
| `docs/platform/control-center-lifecycle.md` | Gate B test matrix and selected production lifecycle policy. |

### Task 1: Execute Gate A and create the verified advanced-field profile

**Files:**
- Create: `apps/macos/UltraController/App/Diagnostics/AdvancedModeProbe/AdvancedModeProbeView.swift`
- Create: `apps/macos/UltraController/App/Diagnostics/AdvancedModeProbe/AdvancedModeProbeModel.swift`
- Create: `apps/macos/UltraController/App/Diagnostics/AdvancedModeProbe/AdvancedModeProbeRunner.swift`
- Create: `apps/macos/UltraController/App/Diagnostics/AdvancedModeProbe/AdvancedFieldCandidate.swift`
- Create: `apps/macos/UltraController/App/Resources/VerifiedModeFieldProfile.json`
- Create: `docs/protocol/qc-ultra-advanced-mode-validation.md`
- Create as admitted: `fixtures/bmap/advanced/*.json`
- Modify: `apps/macos/UltraController/App/Settings/SettingsView.swift`
- Test: `apps/macos/UltraController/Tests/Diagnostics/AdvancedModeProbeModelTests.swift`

**Interfaces:**
- Consumes: connected production `HeadphoneSession`, full raw `AudioMode` payloads, and Plan 2 diagnostics.
- Produces: `VerifiedModeFieldProfile.json`, sanitized fixtures, and a pass/fail record for each candidate field.

- [ ] **Step 1: Define the profile schema before probing**

Create an initially empty but valid profile:

```json
{
  "schemaVersion": 1,
  "deviceFamily": "qc-ultra-headphones-gen1",
  "firmware": "UNVALIDATED",
  "validatedAt": null,
  "modeConfigFunction": {
    "functionBlock": 31,
    "function": 6
  },
  "fields": {}
}
```

Each admitted field must use this exact shape:

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

Rejected fields remain present with `status: "rejected"`, a concrete `reason`, and no production write strategy. Unsupported fields use `status: "unsupported"`.

- [ ] **Step 2: Write probe-model tests**

```swift
final class AdvancedModeProbeModelTests: XCTestCase {
    func testRunnerRequiresOriginalConfigurationBeforeWrite() {
        var model = AdvancedModeProbeModel()
        model.select(candidate: .cncLevel)
        XCTAssertFalse(model.canBeginValidation)
        model.captureOriginal(.fixtureCustomMode)
        XCTAssertTrue(model.canBeginValidation)
    }

    func testProbeNeverTargetsBoseBuiltInModeByDefault() {
        let candidate = AudioMode.fixture(index: 0, isUserConfigurable: false)
        XCTAssertFalse(AdvancedModeProbeRunner.isSafeTarget(candidate))
    }

    func testFailedRestorationBlocksFurtherWrites() {
        var model = AdvancedModeProbeModel()
        model.record(.restorationFailed(field: .windBlock))
        XCTAssertTrue(model.isWriteLocked)
    }
}
```

- [ ] **Step 3: Run tests and verify failure**

```bash
make macos-test
```

Expected: FAIL because Gate A probe types are undefined.

- [ ] **Step 4: Implement a bounded candidate set**

```swift
enum AdvancedFieldCandidate: String, CaseIterable, Codable, Sendable {
    case modeName
    case favorite
    case cncLevel
    case autoCNC
    case windBlock
    case spatialAudioMode
    case ancEnabled
}
```

Each candidate declares its expected offset from the documented 48-byte ModeConfig layout only as a hypothesis. The runner must compare physical before/after payloads and may not mark it verified merely because the documented offset changed.

- [ ] **Step 5: Implement the debug-only validation runner**

The runner accepts one user-configurable custom mode and one candidate field. For each candidate it:

1. Reads and stores the complete original mode payload and parsed state.
2. Verifies the target mode is user configurable and not the active safety-critical mode unless the user explicitly switches away.
3. Generates exactly one candidate mutation from the original raw payload.
4. Writes once and reads the full mode back.
5. Computes a byte diff between original, requested, and actual payloads.
6. Rejects the candidate if any unrelated known or opaque byte changes unexpectedly.
7. Restores the original payload/value and reads it back.
8. Locks all further writes if restoration cannot be confirmed.
9. Repeats successful write/read/restore for ten cycles.
10. Reconnects three times and repeats a read check.
11. Power-cycles the headphones twice and records persistence behavior.

The runner exposes no free-form hex input and compiles only under `#if DEBUG`.

- [ ] **Step 6: Add the hidden probe entry point**

When developer diagnostics is enabled, Settings shows `Advanced Mode Validation…`. Require a warning sheet stating that the tool writes one field at a time to a custom mode and will stop on any restoration failure.

- [ ] **Step 7: Run Gate A on the physical headset**

For every candidate field:

- Use one disposable/custom user-configurable mode.
- Record exact firmware and original mode payload.
- Record write operator and payload.
- Record device response and full read-back.
- Complete ten write/read/restore cycles.
- Complete three reconnect cycles.
- Complete two headphone power cycles.
- Confirm the original mode configuration is restored before moving to the next field.

If a field cannot be safely tested, mark it `unvalidated`, which is equivalent to excluded from production.

- [ ] **Step 8: Write the evidence document**

Create `docs/protocol/qc-ultra-advanced-mode-validation.md`:

```markdown
# QC Ultra Advanced Mode Validation

## Environment
- macOS build:
- Xcode build:
- Headphone firmware:
- Test mode index and original name:

## Candidate results
| Field | Capability bit | Strategy | Range/values | 10 cycles | 3 reconnects | 2 power cycles | Restored | Decision |

## Byte-diff evidence
### Field: <name>
- Original payload:
- Requested payload:
- Confirmed payload:
- Changed offsets:
- Unrelated offsets changed:

## Rejected and unsupported fields
## Restoration incidents
## Production profile checksum
## Gate A conclusion
```

Populate every section. Sanitized fixtures are added only for verified reads/writes and explicit rejection/error cases.

- [ ] **Step 9: Finalize the machine-readable profile**

Replace `firmware: "UNVALIDATED"`, set `validatedAt`, and add every candidate with `verified`, `rejected`, `unsupported`, or `unvalidated`. Compute and record:

```bash
shasum -a 256 apps/macos/UltraController/App/Resources/VerifiedModeFieldProfile.json
```

Copy the checksum into the evidence document.

- [ ] **Step 10: Verify and commit Gate A evidence**

```bash
python3 -m json.tool apps/macos/UltraController/App/Resources/VerifiedModeFieldProfile.json >/dev/null
! grep -E 'UNVALIDATED|TBD|TODO|REPLACE_ME' \
  apps/macos/UltraController/App/Resources/VerifiedModeFieldProfile.json \
  docs/protocol/qc-ultra-advanced-mode-validation.md
make macos-test

git add apps/macos/UltraController/App/Diagnostics/AdvancedModeProbe \
  apps/macos/UltraController/App/Resources/VerifiedModeFieldProfile.json \
  apps/macos/UltraController/App/Settings/SettingsView.swift \
  apps/macos/UltraController/Tests/Diagnostics \
  docs/protocol/qc-ultra-advanced-mode-validation.md \
  fixtures/bmap/advanced
git commit -m "test: validate QC Ultra advanced mode writes"
```

### Task 2: Implement verified mode mutation primitives

**Files:**
- Create: `apps/macos/UltraController/Packages/HeadphoneCore/Sources/HeadphoneCore/ModeMutation/VerifiedModeField.swift`
- Create: `.../ModeMutation/VerifiedModeFieldProfile.swift`
- Create: `.../ModeMutation/ModeFieldChange.swift`
- Create: `.../ModeMutation/AudioModeMutationPlan.swift`
- Create: `.../ModeMutation/AudioModeMutationPlanner.swift`
- Create: `.../ModeMutation/ModeMutationError.swift`
- Modify: `apps/macos/UltraController/Packages/HeadphoneCore/Sources/HeadphoneCore/Protocol/AudioModeMessages.swift`
- Test: `apps/macos/UltraController/Packages/HeadphoneCore/Tests/HeadphoneCoreTests/AudioModeMutationPlannerTests.swift`
- Test: `.../VerifiedModeFieldProfileTests.swift`

**Interfaces:**
- Consumes: confirmed `AudioMode.rawPayload`, desired field changes, and the Gate A profile.
- Produces: `AudioModeMutationPlan` containing ordered typed packets and an expected confirmed mode; rejects unverified fields and changed opaque bytes.

- [ ] **Step 1: Write profile and mutation-planner tests**

Use the actual Gate A results. For each verified field, add a test asserting exact request hex and changed offsets. For each rejected/unvalidated field, add:

```swift
func testUnverifiedFieldCannotProduceMutation() throws {
    let profile = try VerifiedModeFieldProfile.fixtureOnlyCNCVerified()
    XCTAssertThrowsError(
        try AudioModeMutationPlanner(profile: profile).plan(
            from: .fixtureCustomMode,
            changes: [.windBlock(true)]
        )
    ) { error in
        XCTAssertEqual(error as? ModeMutationError, .fieldNotVerified(.windBlock))
    }
}
```

Add an opaque-byte test:

```swift
func testFullPayloadMutationChangesOnlyVerifiedOffset() throws {
    let plan = try planner.plan(from: .fixtureCustomMode, changes: [.cncLevel(7)])
    let before = AudioMode.fixtureCustomMode.rawPayload
    let after = plan.expectedRawPayload
    XCTAssertEqual(zip(before, after).enumerated().compactMap { $0.element.0 == $0.element.1 ? nil : $0.offset }, [42])
}
```

- [ ] **Step 2: Run and verify failure**

```bash
make macos-test-core
```

Expected: FAIL because mutation-profile types are undefined.

- [ ] **Step 3: Implement profile decoding with firmware matching**

```swift
public enum VerifiedModeField: String, Codable, Sendable, CaseIterable {
    case modeName, favorite, cncLevel, autoCNC, windBlock, spatialAudioMode, ancEnabled
}

public struct VerifiedModeFieldProfile: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let deviceFamily: String
    public let firmware: String
    public let fields: [VerifiedModeField: FieldRule]

    public func rule(for field: VerifiedModeField, firmware actual: String) throws -> FieldRule {
        guard actual == firmware else { throw ModeMutationError.unvalidatedFirmware(actual) }
        guard let rule = fields[field], rule.status == .verified else {
            throw ModeMutationError.fieldNotVerified(field)
        }
        return rule
    }
}
```

Do not silently apply a profile to a different firmware. The app may later admit a second exact profile through a separate physical validation commit.

- [ ] **Step 4: Implement changes and planner**

```swift
public enum ModeFieldChange: Sendable, Equatable {
    case modeName(String)
    case favorite(Bool)
    case cncLevel(UInt8)
    case autoCNC(Bool)
    case windBlock(Bool)
    case spatialAudioMode(SpatialAudioMode)
    case ancEnabled(Bool)
}

public struct AudioModeMutationPlan: Sendable, Equatable {
    public let sourceModeID: UInt8
    public let sourceRawPayload: [UInt8]
    public let changes: [ModeFieldChange]
    public let packets: [BMAPPacket]
    public let expectedRawPayload: [UInt8]
}
```

The planner:

- sorts changes by the exact safe order recorded in the profile
- validates ranges/allowed values
- validates UTF-8 byte length and zero padding for names
- preserves all unmodified bytes
- emits field-specific packets when the profile says `fieldSpecific`
- emits one verified full-payload `SetGet` packet only when the profile says `fullModeConfigSetGet`
- rejects duplicate fields, unknown profile schema, mismatched firmware, and payloads with unexpected length

- [ ] **Step 5: Add `AudioModeMessages.setConfiguration` only when Gate A verified it**

The builder accepts the full already-validated payload and does not modify it internally:

```swift
public static func setConfiguration(validatedPayload: [UInt8]) throws -> BMAPPacket {
    guard validatedPayload.count == 48 else {
        throw ModeMutationError.unexpectedPayloadLength(validatedPayload.count)
    }
    return BMAPPacket(
        functionBlock: .audioModes,
        function: 0x06,
        operator: .setGet,
        payload: validatedPayload
    )
}
```

If Gate A discovers a different operator/layout, encode the exact verified contract and update the test fixture; do not keep this hypothetical signature unmodified.

- [ ] **Step 6: Run parity tests and commit**

```bash
make macos-test-core
cargo test --workspace

git add apps/macos/UltraController/Packages/HeadphoneCore fixtures/bmap/advanced
git commit -m "feat: add verified mode mutation planner"
```

### Task 3: Add draft conflict detection and verified multi-field Apply

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
- Consumes: profile-backed `AudioModeMutationPlanner`, confirmed mode, session revision, and connected firmware identity.
- Produces: `makeModeDraft(id:)`, `applyModeDraft(_:)`, conflict handling, complete/partial/unknown results, and refreshed authoritative state.

- [ ] **Step 1: Write stale-draft and partial-apply tests**

```swift
func testApplyRejectsDraftWhenModeChangedExternally() async throws {
    let fixture = try await SessionFixture.connectedWithVerifiedProfile()
    let draft = try await fixture.session.makeModeDraft(id: 2)
    fixture.respondModeConfig(.fixtureCustomMode.withCNC(4))
    await fixture.session.ingestExternalRefreshForTest()

    await XCTAssertThrowsErrorAsync(
        try await fixture.session.applyModeDraft(draft.changing(.cncLevel(7))),
        matching: .conflict
    )
    XCTAssertEqual(fixture.transport.mutatingWriteCount, 0)
}

func testPartialApplyReturnsConfirmedFinalMode() async throws {
    let fixture = try await SessionFixture.connectedWithVerifiedProfile()
    let draft = try await fixture.session.makeModeDraft(id: 2)
    fixture.scriptFirstFieldSuccessSecondFieldError()
    let result = try await fixture.session.applyModeDraft(
        draft.changing(.cncLevel(7)).changing(.favorite(true))
    )
    guard case let .partial(confirmedMode, failedFields) = result else {
        return XCTFail("expected partial result")
    }
    XCTAssertEqual(confirmedMode.cncLevel, 7)
    XCTAssertEqual(failedFields, [.favorite])
}
```

- [ ] **Step 2: Run and verify failure**

```bash
make macos-test
```

Expected: FAIL because draft/apply types are undefined.

- [ ] **Step 3: Define draft and outcomes**

```swift
struct ModeDraft: Equatable, Sendable {
    let modeID: UInt8
    let sourceSessionRevision: UInt64
    let sourceRawPayload: [UInt8]
    let sourceMode: AudioMode
    var changes: [VerifiedModeField: ModeFieldChange]
}

enum ModeApplyResult: Equatable, Sendable {
    case complete(AudioMode)
    case partial(confirmed: AudioMode, failedFields: [VerifiedModeField])
    case unchanged(AudioMode)
}
```

The application model owns the editable copy, but only the session may construct a valid source draft from confirmed state.

- [ ] **Step 4: Implement preflight conflict detection**

Immediately before writing:

1. Query the complete current ModeConfig.
2. Compare mode ID, raw payload, and source revision.
3. If unchanged, continue.
4. If only unrelated global session state changed but mode payload matches, update draft revision and continue.
5. If mode payload changed, throw `ModeApplyError.conflict(ModeConflict)` with the latest confirmed mode and no writes.

Do not provide a blind force-overwrite API. The UI can reload and create a new draft from latest state.

- [ ] **Step 5: Implement ordered Apply and reconciliation**

- Build the plan with the connected firmware's verified profile.
- Serialize the operation through the existing command queue.
- Write packets in profile order.
- Stop after the first failed field/packet.
- Query the full mode configuration regardless of complete or partial write outcome.
- Compare every intended field and unknown-byte preservation.
- Publish the confirmed mode to the session snapshot.
- Return `.complete`, `.partial`, or throw `.outcomeUnknown` when final state cannot be read.
- Do not perform rollback unless Gate A explicitly marked every changed field reversible and a separately tested rollback path is enabled; v1 default is reconciliation, not speculative rollback.

- [ ] **Step 6: Update `ApplicationModel` draft behavior**

Expose:

```swift
func beginEditingMode(_ id: UInt8)
func updateModeDraft(_ change: ModeFieldChange)
func applyModeDraft()
func discardModeDraft()
```

On conflict, preserve the user's proposed field values separately and show latest confirmed values. Provide `Reload` and `Review Changes`; creating a new draft requires an explicit user action.

- [ ] **Step 7: Run tests and commit**

```bash
make macos-test

git add apps/macos/UltraController/App/Session \
  apps/macos/UltraController/App/Application \
  apps/macos/UltraController/Tests/Session \
  apps/macos/UltraController/Tests/Application
git commit -m "feat: add verified advanced mode apply"
```

### Task 4: Build the native advanced mode editor

**Files:**
- Replace: `apps/macos/UltraController/App/Modes/ModesListView.swift`
- Create: `apps/macos/UltraController/App/Modes/ModeEditorView.swift`
- Create: `apps/macos/UltraController/App/Modes/ModeFieldEditor.swift`
- Create: `apps/macos/UltraController/App/Modes/ModeEditPresentation.swift`
- Create: `apps/macos/UltraController/App/Modes/ModeApplyResultView.swift`
- Create: `apps/macos/UltraController/App/Modes/ModeConflictView.swift`
- Modify: `apps/macos/UltraController/App/Resources/Localizable.xcstrings`
- Test: `apps/macos/UltraController/Tests/Modes/ModeEditPresentationTests.swift`
- UI Test: `apps/macos/UltraController/UITests/ModeEditorUITests.swift`

**Interfaces:**
- Consumes: `ApplicationModel.modeDraft`, verified profile rules, and apply results.
- Produces: capability/profile-driven editor with Apply/Cancel, conflict, partial-result, and accessibility behavior.

- [ ] **Step 1: Write presentation tests from the actual profile**

```swift
func testEditorShowsOnlyVerifiedWritableFields() throws {
    let presentation = ModeEditPresentation(
        mode: .fixtureCustomMode,
        profile: .fixtureOnlyCNCAndFavoriteVerified,
        firmware: "1.6.7"
    )
    XCTAssertEqual(presentation.fields.map(\.field), [.favorite, .cncLevel])
}

func testApplyDisabledForUnchangedDraft() {
    XCTAssertFalse(ModeEditPresentation.unchanged.canApply)
}

func testApplyDisabledDuringPendingOperation() {
    XCTAssertFalse(ModeEditPresentation.changedPending.canApply)
}
```

Use the actual verified field list after Gate A instead of the fixture names when implementing production expectations.

- [ ] **Step 2: Run and verify failure**

```bash
make macos-test
```

Expected: FAIL because edit presentation/views are undefined.

- [ ] **Step 3: Implement field-specific native controls**

- Name: `TextField` with verified UTF-8 byte-length counter and validation.
- Favorite/Auto-CNC/Wind/ANC: `Toggle` only when verified.
- CNC: `Slider` plus `Stepper` or `Picker` using verified integer bounds.
- Spatial/Immersive behavior: `Picker` using verified allowed values.
- Read-only fields: `LabeledContent`, not disabled interactive controls.

Unsupported, rejected, unvalidated-firmware, and absent profile fields are omitted.

- [ ] **Step 4: Implement staged navigation and unsaved-change handling**

Selecting a mode creates a draft. Leaving with changes presents `Apply`, `Discard`, and `Cancel`. `Apply` remains disabled until the draft differs from the source, validates locally, the session is connected, and no command is pending.

- [ ] **Step 5: Implement conflict and partial-result UI**

Conflict sheet shows:

- latest confirmed value for each changed field
- proposed value
- `Reload from Headphones`
- `Review Changes`
- `Cancel`

Partial result shows confirmed applied values and names the failed/unconfirmed fields. Never show a generic success checkmark after partial application.

- [ ] **Step 6: Add accessibility behavior**

- Announce Apply start/completion/failure.
- Expose slider values as integer ANC/CNC levels.
- Keep focus in the error/conflict sheet after a failed Apply.
- Do not communicate favorite/active/pending states only by icon color.

- [ ] **Step 7: Run tests, perform physical editor smoke test, and commit**

```bash
make macos-test
xcodebuild -project apps/macos/UltraController/UltraController.xcodeproj \
  -scheme UltraController -destination 'platform=macOS,arch=arm64' test

git add apps/macos/UltraController/App/Modes \
  apps/macos/UltraController/App/Resources/Localizable.xcstrings \
  apps/macos/UltraController/Tests/Modes \
  apps/macos/UltraController/UITests
git commit -m "feat: add verified advanced mode editor"
```

The physical smoke test changes every admitted field once, confirms read-back in the app and after reconnect, then restores the original mode.

### Task 5: Execute Gate B with the smallest possible control extension

**Files:**
- Modify: `apps/macos/UltraController/project.yml`
- Create: `apps/macos/UltraController/Config/Controls.entitlements`
- Create: `apps/macos/UltraController/Packages/ControlSupport/Package.swift`
- Create: `apps/macos/UltraController/Packages/ControlSupport/Sources/ControlSupport/ControlActionRequest.swift`
- Create: `.../SharedHeadphoneSnapshot.swift` or move the existing shared schema into this package
- Create: `.../ControlLifecyclePolicy.swift`
- Create: `apps/macos/UltraController/App/Intents/HeadphoneIntentController.swift`
- Create: `apps/macos/UltraController/App/Intents/ReconnectHeadphonesIntent.swift`
- Create: `apps/macos/UltraController/ControlsExtension/UltraControllerControlsBundle.swift`
- Create: `apps/macos/UltraController/ControlsExtension/ReconnectControl.swift`
- Create: `docs/platform/control-center-lifecycle.md`
- Test: `apps/macos/UltraController/Packages/ControlSupport/Tests/ControlSupportTests/ControlLifecyclePolicyTests.swift`
- Test: `apps/macos/UltraController/Tests/Intents/ReconnectHeadphonesIntentTests.swift`

**Interfaces:**
- Consumes: shared snapshot, one app `HeadphoneSessionClient`, final/current macOS 27 SDK behavior.
- Produces: measured lifecycle policy `.directMainProcess`, `.openAppWhenNotResident`, or `.openAppAlways` and one non-destructive Reconnect control.

- [ ] **Step 1: Write lifecycle-policy tests**

```swift
func testDirectPolicyUsesMainProcessWhenResident() {
    let policy = ControlLifecyclePolicy.directMainProcess
    XCTAssertEqual(policy.route(appState: .residentConnected), .executeInMainProcess)
}

func testFallbackPolicyOpensAppWhenTerminated() {
    let policy = ControlLifecyclePolicy.openAppWhenNotResident
    XCTAssertEqual(policy.route(appState: .terminated), .openApp(request: .reconnect))
}
```

- [ ] **Step 2: Add the package and extension target**

`ControlSupport` contains only Foundation/AppIntents-safe shared values and no CoreBluetooth dependency. Add to `project.yml`:

```yaml
packages:
  HeadphoneCore:
    path: Packages/HeadphoneCore
  ControlSupport:
    path: Packages/ControlSupport

targets:
  UltraControllerControls:
    type: app-extension
    platform: macOS
    sources:
      - ControlsExtension
    entitlements:
      path: Config/Controls.entitlements
    dependencies:
      - package: ControlSupport
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: dev.densedevkev.ultracontroller.controls
        INFOPLIST_KEY_NSExtension_NSExtensionPointIdentifier: com.apple.widgetkit-extension
```

Embed the extension in `UltraController`. `Controls.entitlements` contains App Sandbox and the App Group only—no Bluetooth entitlement.

- [ ] **Step 3: Implement the main-process controller dependency**

```swift
@MainActor
final class HeadphoneIntentController {
    private let session: any HeadphoneSessionClient

    init(session: any HeadphoneSessionClient) {
        self.session = session
    }

    func reconnect() async throws {
        await session.manualReconnect()
    }
}
```

Register the single app instance during environment construction:

```swift
AppDependencyManager.shared.add(dependency: environment.intentController)
```

- [ ] **Step 4: Implement the smallest App Intent**

Against the final SDK's exact public signature, use main-process targeting:

```swift
struct ReconnectHeadphonesIntent: AppIntent {
    static let title: LocalizedStringResource = "Reconnect Headphones"
    static let openAppWhenRun = false
    static var allowedExecutionTargets: IntentExecutionTargets { [.main] }

    @Dependency private var controller: HeadphoneIntentController

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await controller.reconnect()
        return .result(dialog: "Reconnect started.")
    }
}
```

If the final SDK renames the execution-target declaration, update this exact code to the final public API and record the difference in the Gate B document. Do not use private APIs to preserve the beta spelling.

- [ ] **Step 5: Implement one static Reconnect control**

```swift
struct ReconnectControl: ControlWidget {
    static let kind = "dev.densedevkev.ultracontroller.reconnect"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: Provider()) { value in
            ControlWidgetButton(action: ReconnectHeadphonesIntent()) {
                Label(value.title, systemImage: "arrow.clockwise")
            }
        }
        .displayName("Reconnect Headphones")
        .description("Reconnect the selected QC Ultra headphones.")
    }
}
```

The provider reads only `SharedSnapshotStore`; it never imports CoreBluetooth or `HeadphoneCore` transport code.

- [ ] **Step 6: Run automated extension and intent tests**

```bash
make macos-generate
make macos-test
xcodebuild -project apps/macos/UltraController/UltraController.xcodeproj \
  -scheme UltraController \
  -destination 'platform=macOS,arch=arm64' \
  build
```

Expected: app and embedded extension build and sign with matching App Group identities.

- [ ] **Step 7: Execute the Gate B lifecycle matrix**

Install the development build, add Reconnect to Control Center and—where supported—the system menu bar, then test:

| State | Required observation |
|---|---|
| Main window visible, connected | Intent runs through existing session; no second connection. |
| Main window closed, app resident | Intent runs without opening a normal window unless the system requires it. |
| App menu-bar-only/accessory | Intent reaches the same session. |
| App terminated | Record whether macOS launches the main process and whether bounded BLE work completes. |
| Headphones available but disconnected | One bounded reconnect starts; result is finite. |
| Headphones unavailable | Clear failure/open-app recovery; no scan loop. |
| After sleep/wake | No duplicate process/session; control state refreshes. |
| Stale shared snapshot | Provider visibly treats state as stale. |

Use Console/diagnostic session IDs to prove one `HeadphoneSession` and one central manager.

- [ ] **Step 8: Write the Gate B evidence and select the policy**

Create `docs/platform/control-center-lifecycle.md`:

```markdown
# Control Center Lifecycle Validation

## Environment
- macOS build:
- Xcode build:
- SDK version:

## Test matrix
| App state | Headphone state | Process launched | Existing session reused | Action result | UI shown | Duplicate BLE owner |

## API behavior observed
## Selected production policy
## Unsupported lifecycle states
## Open-app fallback behavior
## Gate B conclusion
```

Select exactly one policy:

- `directMainProcess`: all required lifecycle states work reliably.
- `openAppWhenNotResident`: resident execution works; terminated state opens the app with the queued action.
- `openAppAlways`: direct headless execution is unreliable; controls open the app for every action.

If no finite/recoverable policy works within sandbox constraints, remove the extension from v1 and record Gate B as failed.

- [ ] **Step 9: Commit Gate B**

```bash
! grep -E 'TBD|TODO|REPLACE_ME' docs/platform/control-center-lifecycle.md
make macos-test

git add apps/macos/UltraController/project.yml \
  apps/macos/UltraController/Config/Controls.entitlements \
  apps/macos/UltraController/Packages/ControlSupport \
  apps/macos/UltraController/App/Intents \
  apps/macos/UltraController/ControlsExtension \
  apps/macos/UltraController/Tests/Intents \
  docs/platform/control-center-lifecycle.md
git commit -m "test: validate Control Center main-process lifecycle"
```

### Task 6: Implement production audio-mode, cycle, immersive, and reconnect controls

**Files:**
- Create: `apps/macos/UltraController/Packages/ControlSupport/Sources/ControlSupport/AudioModeEntity.swift`
- Create: `.../AudioModeEntityQuery.swift`
- Create: `.../ControlOutcome.swift`
- Create: `apps/macos/UltraController/App/Intents/SetAudioModeIntent.swift`
- Create: `apps/macos/UltraController/App/Intents/CycleAudioModeIntent.swift`
- Create: `apps/macos/UltraController/App/Intents/SetImmersiveAudioIntent.swift`
- Modify: `apps/macos/UltraController/App/Intents/ReconnectHeadphonesIntent.swift`
- Modify: `apps/macos/UltraController/App/Intents/HeadphoneIntentController.swift`
- Create: `apps/macos/UltraController/ControlsExtension/AudioModeControl.swift`
- Create: `apps/macos/UltraController/ControlsExtension/CycleAudioModeControl.swift`
- Create: `apps/macos/UltraController/ControlsExtension/ImmersiveAudioControl.swift`
- Modify: `apps/macos/UltraController/ControlsExtension/UltraControllerControlsBundle.swift`
- Modify: `apps/macos/UltraController/App/Resources/Localizable.xcstrings`
- Test: `apps/macos/UltraController/Packages/ControlSupport/Tests/ControlSupportTests/AudioModeEntityQueryTests.swift`
- Test: `apps/macos/UltraController/Tests/Intents/SystemControlIntentTests.swift`
- UI/manual: `apps/macos/UltraController/UITests/SystemControlsUITests.swift`

**Interfaces:**
- Consumes: Gate B policy, shared snapshot, and main app `HeadphoneSessionClient`.
- Produces: configurable Set Audio Mode, deterministic Cycle Audio Mode, Immersive Audio toggle, and Reconnect controls.

- [ ] **Step 1: Write entity and cycle-order tests**

```swift
func testModeEntityUsesStableDeviceIndex() {
    let entity = AudioModeEntity(id: 3, name: "Music")
    XCTAssertEqual(entity.id, 3)
}

func testCycleUsesHeadphoneReportedOrder() {
    let modes = [AudioModeEntity(id: 0, name: "Quiet"), AudioModeEntity(id: 4, name: "Aware"), AudioModeEntity(id: 2, name: "Music")]
    XCTAssertEqual(CycleAudioModeIntent.nextMode(after: 4, in: modes)?.id, 2)
    XCTAssertEqual(CycleAudioModeIntent.nextMode(after: 2, in: modes)?.id, 0)
}
```

- [ ] **Step 2: Implement dynamic mode entities from the shared snapshot**

`AudioModeEntityQuery` reads fresh or stale cached modes from the App Group. It returns stable device mode indexes as IDs. If a configured ID no longer exists, the intent returns a localized stale-configuration result and opens the app according to Gate B policy; it never guesses by mode name.

- [ ] **Step 3: Extend the intent controller with verified actions**

```swift
@MainActor
func setMode(_ id: UInt8) async throws { try await session.setCurrentMode(id) }

@MainActor
func cycleMode() async throws {
    let snapshot = latestConfirmedSnapshot
    guard let current = snapshot.currentModeID,
          let next = nextReportedMode(after: current, in: snapshot.modes) else {
        throw IntentControllerError.noModes
    }
    try await session.setCurrentMode(next.id)
}

@MainActor
func setImmersive(enabled: Bool) async throws {
    let target: SpatialAudioMode = enabled ? lastConfirmedNonOffSpatialMode ?? .still : .off
    try await session.setSpatialAudio(target)
}
```

The app persists the last confirmed non-off spatial mode only to define toggle-on behavior; the headphones remain authoritative.

- [ ] **Step 4: Implement App Intents with Gate B routing**

- `SetAudioModeIntent` accepts `AudioModeEntity`.
- `CycleAudioModeIntent` has no parameter.
- `SetImmersiveAudioIntent` accepts `Bool` or follows the control's toggle state.
- `ReconnectHeadphonesIntent` remains non-destructive.

For `.openAppWhenNotResident` or `.openAppAlways`, encode a small `ControlActionRequest` in the App Group, use the public open-app/deep-link path, and have the main app consume it exactly once after session startup. Expire queued requests after 30 seconds and never replay them after a later launch.

- [ ] **Step 5: Implement the controls**

- Set Audio Mode uses `AppIntentControlConfiguration` with an `AudioModeEntity` configuration parameter.
- Cycle Mode uses `StaticControlConfiguration` and `ControlWidgetButton`.
- Immersive uses `ControlWidgetToggle`, reads cached state, and invokes `SetImmersiveAudioIntent`.
- Reconnect remains a button.

Providers display disconnected/stale state honestly and do not promise success before intent completion.

- [ ] **Step 6: Reload control state after confirmed changes**

After `ApplicationModel` writes a fresh shared snapshot, request local control reload using the final public WidgetKit API. For the current SDK this is expected to be:

```swift
ControlCenter.shared.reloadControls(ofKind: AudioModeControl.kind)
ControlCenter.shared.reloadControls(ofKind: CycleAudioModeControl.kind)
ControlCenter.shared.reloadControls(ofKind: ImmersiveAudioControl.kind)
ControlCenter.shared.reloadControls(ofKind: ReconnectControl.kind)
```

Compile against the final SDK and update this exact call if Apple changed the public spelling; record the API used in `control-center-lifecycle.md`.

- [ ] **Step 7: Add intent tests for every state**

Cover:

- connected success after session read-back
- disconnected but available bounded reconnect
- unavailable finite failure
- stale configured mode ID
- missing selected device
- Gate B open-app request creation/expiry/one-time consumption
- immersive toggle restores the last confirmed non-off value
- cycle preserves the reported mode order
- no Power Off intent exists

- [ ] **Step 8: Perform physical system-control tests and commit**

Test each control from Control Center and, where the OS allows, pinned to the system menu bar in every Gate B-supported lifecycle state. Confirm actions update desktop and app menu bar from the same session snapshot.

```bash
make macos-test
xcodebuild -project apps/macos/UltraController/UltraController.xcodeproj \
  -scheme UltraController -destination 'platform=macOS,arch=arm64' test

git add apps/macos/UltraController/Packages/ControlSupport \
  apps/macos/UltraController/App/Intents \
  apps/macos/UltraController/ControlsExtension \
  apps/macos/UltraController/App/Resources/Localizable.xcstrings \
  apps/macos/UltraController/Tests/Intents \
  apps/macos/UltraController/UITests \
  docs/platform/control-center-lifecycle.md
git commit -m "feat: add verified macOS system controls"
```

### Task 7: Run the Plan 4 checkpoint

**Files:**
- Verify Gate A profile/evidence, advanced editor, Gate B evidence/policy, and production controls.

**Interfaces:**
- Produces for Plan 5: complete feature set with evidence-backed advanced fields and lifecycle-backed system controls.

- [ ] **Step 1: Validate the advanced-field profile and evidence**

```bash
python3 -m json.tool apps/macos/UltraController/App/Resources/VerifiedModeFieldProfile.json >/dev/null
! grep -E 'UNVALIDATED|TBD|TODO|REPLACE_ME' \
  apps/macos/UltraController/App/Resources/VerifiedModeFieldProfile.json \
  docs/protocol/qc-ultra-advanced-mode-validation.md \
  docs/platform/control-center-lifecycle.md
```

Expected: exit 0. Every production-visible advanced field is `verified` for the exact tested firmware.

- [ ] **Step 2: Run the full automated suite twice**

```bash
cargo test --workspace
make macos-test-core
make macos-test
make macos-test
```

Expected: all pass twice.

- [ ] **Step 3: Verify the extension has no Bluetooth dependency**

```bash
! grep -R -E 'import CoreBluetooth|CBCentralManager|CBPeripheral|HeadphoneTransport' \
  apps/macos/UltraController/ControlsExtension \
  apps/macos/UltraController/Packages/ControlSupport
```

Expected: exit 0.

- [ ] **Step 4: Verify no destructive system intent exists**

```bash
! grep -R -E 'PowerOffIntent|powerOff\(' \
  apps/macos/UltraController/ControlsExtension \
  apps/macos/UltraController/App/Intents
```

Expected: exit 0.

- [ ] **Step 5: Run physical acceptance checks**

- Every visible advanced field applies and reads back.
- The mode is restored after the test.
- Partial/failure UI shows actual confirmed state.
- Set, Cycle, Immersive, and Reconnect controls work in every supported Gate B lifecycle state.
- Unsupported lifecycle states use the documented fallback.
- Desktop, app menu bar, Control Center, and system-pinned controls converge on one state.
- Diagnostics show one central manager/session.

Plan 4 is complete only when both evidence documents are committed and production behavior exactly matches their conclusions.
