# Ultra Controller Session and Connectivity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the temporary protocol probe with one production CoreBluetooth transport and a fully tested `HeadphoneSession` actor that synchronizes state, serializes commands, reconnects safely, and verifies essential controls on the physical QC Ultra.

**Architecture:** `CoreBluetoothTransport` is a `@MainActor` delegate adapter that owns Apple Bluetooth objects and emits bounded value-type events. `HeadphoneSession` is a separate actor that owns the connection state machine, BMAP request serialization, command confirmation, reconnection, and authoritative snapshots. Tests use a deterministic fake transport and clock; no SwiftUI view or App Intent accesses CoreBluetooth directly.

**Tech Stack:** Swift 6 strict concurrency, CoreBluetooth, Foundation async sequences, XCTest, `NSWorkspace` sleep/wake notifications, `os.Logger`, `HeadphoneCore` from Plan 1.

**Spec:** `docs/superpowers/specs/2026-08-29-qc-ultra-macos-controller-design.md`

## Global Constraints

- Plan 1 must pass, including committed physical baseline-probe evidence.
- Maintain exactly one `CBCentralManager` and one selected peripheral connection.
- Do not use CoreBluetooth objects outside `CoreBluetoothTransport`.
- Serialize BMAP operations because the protocol has no general request identifier.
- Never automatically retry an ambiguous mutation; read the affected property instead.
- Use the reconnect sequence `1s, 2s, 5s, 10s, 30s`, then remain at 30 seconds without a tight scan loop.
- Power Off succeeds only on accepted write plus expected link loss inside the configured window.
- A disconnect cancels commands tied to the old connection generation.
- Keep the main app local-only and sandboxed.

---

## File Map

| Path | Responsibility |
|---|---|
| `Packages/HeadphoneCore/Sources/HeadphoneCore/Transport/*` | Transport-neutral IDs, candidates, events, errors, and protocol. |
| `App/Bluetooth/CoreBluetoothTransport.swift` | Apple delegate adapter and BLE write/read lifecycle. |
| `App/Bluetooth/DiscoveryPolicy.swift` | Pure candidate/retrieval/scan-stage policy. |
| `App/Session/HeadphoneSession.swift` | Authoritative connection, request, command, and snapshot actor. |
| `App/Session/ConnectionPhase.swift` | Explicit public state machine. |
| `App/Session/CommandExecutor.swift` | Single-flight operation execution and confirmation. |
| `App/Session/ReconnectPolicy.swift` | Bounded deterministic backoff. |
| `App/Session/SessionClock.swift` | Production/test time abstraction. |
| `App/Lifecycle/SleepWakeMonitor.swift` | Converts public macOS lifecycle notifications into session calls. |
| `Tests/Fakes/FakeHeadphoneTransport.swift` | Scriptable transport for deterministic tests. |
| `Tests/Session/*Tests.swift` | State, command, timeout, reconnect, and cancellation coverage. |
| `App/Diagnostics/ConnectivityHarnessView.swift` | Debug-only physical integration surface used before product UI. |

### Task 1: Define transport-neutral IDs, events, and protocol

**Files:**
- Create: `apps/macos/UltraController/Packages/HeadphoneCore/Sources/HeadphoneCore/Transport/HeadphoneID.swift`
- Create: `.../Transport/DiscoveredHeadphone.swift`
- Create: `.../Transport/TransportAvailability.swift`
- Create: `.../Transport/TransportChannel.swift`
- Create: `.../Transport/TransportEvent.swift`
- Create: `.../Transport/HeadphoneTransport.swift`
- Create: `.../Transport/HeadphoneTransportError.swift`
- Test: `.../Tests/HeadphoneCoreTests/TransportValueTests.swift`

**Interfaces:**
- Consumes: Foundation values only.
- Produces: `HeadphoneID`, `DiscoveredHeadphone`, `TransportEvent`, and `@MainActor HeadphoneTransport` used by both real and fake transports.

- [ ] **Step 1: Write failing value-semantics tests**

```swift
import XCTest
@testable import HeadphoneCore

final class TransportValueTests: XCTestCase {
    func testCandidateIdentityUsesPeripheralUUID() {
        let id = HeadphoneID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let first = DiscoveredHeadphone(id: id, name: "QC Ultra", rssi: -40, advertisesBMAP: true)
        let second = DiscoveredHeadphone(id: id, name: "Renamed", rssi: -60, advertisesBMAP: false)
        XCTAssertEqual(first.id, second.id)
    }

    func testTransportEventCarriesNoCoreBluetoothObject() throws {
        let event = TransportEvent.availabilityChanged(.poweredOn)
        _ = try JSONEncoder().encode(event)
    }
}
```

- [ ] **Step 2: Run and verify failure**

```bash
make macos-test-core
```

Expected: FAIL because transport value types are undefined.

- [ ] **Step 3: Implement transport values**

```swift
public struct HeadphoneID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct DiscoveredHeadphone: Identifiable, Hashable, Codable, Sendable {
    public let id: HeadphoneID
    public let name: String?
    public let rssi: Int
    public let advertisesBMAP: Bool
}

public enum TransportAvailability: String, Codable, Sendable {
    case unknown, resetting, unsupported, unauthorized, poweredOff, poweredOn
}

public enum TransportChannel: String, Codable, Sendable {
    case secure, unsecure
}

public enum TransportEvent: Codable, Sendable, Equatable {
    case availabilityChanged(TransportAvailability)
    case discovered(DiscoveredHeadphone)
    case connected(HeadphoneID)
    case channelReady(HeadphoneID, TransportChannel)
    case notification(HeadphoneID, [UInt8])
    case disconnected(HeadphoneID, String?)
    case failed(HeadphoneTransportError)
}
```

- [ ] **Step 4: Define the actor-safe transport contract**

```swift
@MainActor
public protocol HeadphoneTransport: AnyObject {
    var events: AsyncStream<TransportEvent> { get }

    func retrievePeripheral(id: HeadphoneID) async
    func retrieveConnectedBMAPPeripherals() async
    func startScanning(filterToBMAPService: Bool) async throws
    func stopScanning() async
    func connect(to id: HeadphoneID) async throws
    func disconnect() async
    func write(segment: [UInt8]) async throws
}
```

`write(segment:)` returns only after CoreBluetooth has accepted the segment according to its supported write mode; application-level success still belongs to `HeadphoneSession`.

- [ ] **Step 5: Run tests and commit**

```bash
make macos-test-core
git add apps/macos/UltraController/Packages/HeadphoneCore
git commit -m "feat: define headphone transport boundary"
```

### Task 2: Implement the production CoreBluetooth adapter

**Files:**
- Create: `apps/macos/UltraController/App/Bluetooth/BluetoothUUIDs.swift`
- Create: `apps/macos/UltraController/App/Bluetooth/DiscoveryPolicy.swift`
- Create: `apps/macos/UltraController/App/Bluetooth/CoreBluetoothStateMapper.swift`
- Create: `apps/macos/UltraController/App/Bluetooth/CoreBluetoothTransport.swift`
- Create: `apps/macos/UltraController/App/Bluetooth/CoreBluetoothTransport+CentralDelegate.swift`
- Create: `apps/macos/UltraController/App/Bluetooth/CoreBluetoothTransport+PeripheralDelegate.swift`
- Test: `apps/macos/UltraController/Tests/Bluetooth/DiscoveryPolicyTests.swift`
- Test: `apps/macos/UltraController/Tests/Bluetooth/CoreBluetoothStateMapperTests.swift`

**Interfaces:**
- Consumes: `HeadphoneTransport` and Plan 1's validated discovery/channel policy.
- Produces: `@MainActor final class CoreBluetoothTransport` with one central, one selected peripheral, one BMAP characteristic, and one event stream.

- [ ] **Step 1: Write discovery-policy tests**

```swift
final class DiscoveryPolicyTests: XCTestCase {
    func testSavedIdentifierIsTriedBeforeScanning() {
        let policy = DiscoveryPolicy(savedID: HeadphoneID(rawValue: UUID()))
        XCTAssertEqual(policy.nextAction(after: .started), .retrieveSaved)
    }

    func testFilteredScanFallsBackToBoundedUnfilteredScan() {
        var policy = DiscoveryPolicy(savedID: nil)
        XCTAssertEqual(policy.nextAction(after: .started), .retrieveConnected)
        XCTAssertEqual(policy.nextAction(after: .retrievalEmpty), .scanFiltered(seconds: 5))
        XCTAssertEqual(policy.nextAction(after: .scanEmpty), .scanUnfiltered(seconds: 5))
        XCTAssertEqual(policy.nextAction(after: .scanEmpty), .stopUnavailable)
    }
}
```

- [ ] **Step 2: Run and verify failure**

```bash
make macos-test
```

Expected: FAIL because discovery policy and mapper are undefined.

- [ ] **Step 3: Implement constants and pure state mapping**

```swift
enum BluetoothUUIDs {
    static let bmapService = CBUUID(string: "FEBE")
    static let secure = CBUUID(string: "C65B8F2F-AEE2-4C89-B758-BC4892D6F2D8")
    static let unsecure = CBUUID(string: "D417C028-9818-4354-99D1-2AC09D074591")
}
```

Map every `CBManagerState` to `TransportAvailability`; `.unauthorized` must not be merged with `.poweredOff`.

- [ ] **Step 4: Create the event stream and one-central invariant**

`CoreBluetoothTransport` owns:

```swift
@MainActor
final class CoreBluetoothTransport: NSObject, HeadphoneTransport {
    private let central: CBCentralManager
    private var peripherals: [HeadphoneID: CBPeripheral] = [:]
    private var selectedPeripheral: CBPeripheral?
    private var selectedCharacteristic: CBCharacteristic?
    private var selectedChannel: TransportChannel?
    private let stream: AsyncStream<TransportEvent>
    private let continuation: AsyncStream<TransportEvent>.Continuation

    nonisolated var events: AsyncStream<TransportEvent> { stream }
}
```

Initialize `stream` and `continuation` with `AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(256))`. Construct `CBCentralManager(delegate: nil, queue: .main)` once, then assign the delegate after stored properties initialize. Do not enable CoreBluetooth state restoration in v1; normal launch/reconnect policy remains explicit and testable.

- [ ] **Step 5: Implement retrieval and bounded scanning**

- `retrievePeripheral(id:)` calls `retrievePeripherals(withIdentifiers:)`.
- `retrieveConnectedBMAPPeripherals()` calls `retrieveConnectedPeripherals(withServices:)`.
- Filtered scanning uses `[BluetoothUUIDs.bmapService]`.
- Unfiltered fallback may emit name-matched candidates, but they remain unverified until BMAP identity checks pass.
- Store every emitted `CBPeripheral` in `peripherals` so it remains retained.
- `stopScanning()` always calls `central.stopScan()` and cancels the scan timeout task.

- [ ] **Step 6: Implement service/characteristic discovery**

On connect:

1. Set the peripheral delegate.
2. Discover only the BMAP service.
3. Discover secure and unsecure characteristic UUIDs.
4. Select secure when it supports `.notify` and either `.write` or `.writeWithoutResponse`.
5. Otherwise select unsecure with the same property requirement.
6. Subscribe to notifications.
7. Emit `.channelReady` only after `didUpdateNotificationStateFor` confirms notifications are enabled.

- [ ] **Step 7: Implement serialized segment writes**

Choose `.withResponse` when the characteristic supports it. Otherwise:

- Wait until `peripheral.canSendWriteWithoutResponse`.
- Write one segment.
- If more segments remain, yield to the run loop before the next write.
- Resume waiting from `peripheralIsReady(toSendWriteWithoutResponse:)`.

Map CoreBluetooth errors to `HeadphoneTransportError` without exposing `CBError` outside the adapter.

- [ ] **Step 8: Convert notifications into copied bytes**

`didUpdateValueFor` copies `Data` immediately:

```swift
let bytes = characteristic.value.map { [UInt8]($0) } ?? []
continuation.yield(.notification(id, bytes))
```

Do not parse BMAP in the delegate callback.

- [ ] **Step 9: Run tests and build**

```bash
make macos-test
make macos-build
```

Expected: all pure policy/mapper tests pass and the app compiles with strict concurrency.

- [ ] **Step 10: Commit the adapter**

```bash
git add apps/macos/UltraController/App/Bluetooth apps/macos/UltraController/Tests/Bluetooth
git commit -m "feat: add CoreBluetooth transport adapter"
```

### Task 3: Add deterministic clocks, reconnect policy, and fake transport

**Files:**
- Create: `apps/macos/UltraController/App/Session/SessionClock.swift`
- Create: `apps/macos/UltraController/App/Session/ReconnectPolicy.swift`
- Create: `apps/macos/UltraController/Tests/Fakes/TestSessionClock.swift`
- Create: `apps/macos/UltraController/Tests/Fakes/FakeHeadphoneTransport.swift`
- Test: `apps/macos/UltraController/Tests/Session/ReconnectPolicyTests.swift`
- Test: `apps/macos/UltraController/Tests/Fakes/FakeHeadphoneTransportTests.swift`

**Interfaces:**
- Consumes: `HeadphoneTransport`.
- Produces: `SessionClock`, `ContinuousSessionClock`, `ReconnectPolicy`, `TestSessionClock`, and scriptable `FakeHeadphoneTransport`.

- [ ] **Step 1: Write reconnect-policy tests**

```swift
final class ReconnectPolicyTests: XCTestCase {
    func testBackoffSequenceCapsAtThirtySeconds() {
        var policy = ReconnectPolicy()
        XCTAssertEqual((0..<7).map { _ in policy.nextDelay() }, [1, 2, 5, 10, 30, 30, 30].map(Duration.seconds))
    }

    func testResetReturnsToOneSecond() {
        var policy = ReconnectPolicy()
        _ = policy.nextDelay(); _ = policy.nextDelay()
        policy.reset()
        XCTAssertEqual(policy.nextDelay(), .seconds(1))
    }
}
```

- [ ] **Step 2: Run and verify failure**

```bash
make macos-test
```

Expected: FAIL because policy/clock/fake types are undefined.

- [ ] **Step 3: Implement the clock interface**

```swift
protocol SessionClock: Sendable {
    func sleep(for duration: Duration) async throws
}

struct ContinuousSessionClock: SessionClock {
    func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }
}
```

`TestSessionClock` records requested sleeps and resumes them only when the test calls `advanceNextSleep()`; never use real wall-clock waits in session tests.

- [ ] **Step 4: Implement the fake transport**

`FakeHeadphoneTransport` is `@MainActor`, conforms to `HeadphoneTransport`, records every method call, stores written segments, and exposes test-only methods:

```swift
func emit(_ event: TransportEvent)
func queueWriteFailure(_ error: HeadphoneTransportError)
func clearRecordedCalls()
```

- [ ] **Step 5: Run and commit**

```bash
make macos-test
git add apps/macos/UltraController/App/Session apps/macos/UltraController/Tests/Fakes apps/macos/UltraController/Tests/Session/ReconnectPolicyTests.swift
git commit -m "test: add deterministic transport and reconnect fakes"
```

### Task 4: Implement the authoritative session state machine and initial synchronization

**Files:**
- Create: `apps/macos/UltraController/App/Session/ConnectionPhase.swift`
- Create: `apps/macos/UltraController/App/Session/HeadphoneSnapshot.swift`
- Create: `apps/macos/UltraController/App/Session/HeadphoneSessionError.swift`
- Create: `apps/macos/UltraController/App/Session/SupportedDeviceProfile.swift`
- Create: `apps/macos/UltraController/App/Session/HeadphoneSession.swift`
- Create: `apps/macos/UltraController/App/Resources/QCUltraGen1Profile.json`
- Test: `apps/macos/UltraController/Tests/Session/HeadphoneSessionStateTests.swift`
- Test: `apps/macos/UltraController/Tests/Session/InitialSynchronizationTests.swift`

**Interfaces:**
- Consumes: one `HeadphoneTransport`, `SessionClock`, `HeadphoneCore` parsers, and the verified Gen 1 profile from Plan 1 evidence.
- Produces: `HeadphoneSession.snapshots`, `start(savedID:)`, `select(_:)`, `manualReconnect()`, `forgetDevice()`, `suspendForSleep()`, and `resumeAfterWake()`.

- [ ] **Step 1: Write state-transition tests**

```swift
func testUnsupportedDeviceNeverReachesConnected() async throws {
    let fixture = SessionFixture()
    await fixture.session.start(savedID: nil)
    fixture.transport.emit(.availabilityChanged(.poweredOn))
    fixture.transport.emit(.discovered(.qcUltraCandidate))
    await fixture.session.select(.qcUltraCandidate.id)
    fixture.transport.emit(.connected(.qcUltraCandidate.id))
    fixture.transport.emit(.channelReady(.qcUltraCandidate.id, .secure))
    fixture.respondWithProductName("Bose Other Product")
    let snapshot = await fixture.latestSnapshot()
    XCTAssertEqual(snapshot.phase, .failed(.unsupportedDevice))
    XCTAssertFalse(snapshot.writesEnabled)
}
```

Also test legal transitions from unconfigured through connected and rejection of late events from an old connection generation.

- [ ] **Step 2: Run and verify failure**

```bash
make macos-test
```

Expected: FAIL because session state types are undefined.

- [ ] **Step 3: Define explicit state and snapshots**

```swift
enum ConnectionPhase: Equatable, Sendable {
    case unconfigured
    case permissionRequired
    case bluetoothUnavailable
    case scanning
    case connecting(name: String?)
    case loadingState
    case connected
    case reconnecting(attempt: Int)
    case sleeping
    case unavailable
    case failed(HeadphoneSessionError)
}

struct HeadphoneSnapshot: Equatable, Sendable {
    var revision: UInt64
    var phase: ConnectionPhase
    var selectedID: HeadphoneID?
    var productName: String?
    var battery: [BatteryComponent]
    var capabilities: AudioModeCapabilities?
    var modes: [AudioMode]
    var currentModeID: UInt8?
    var standbyMinutes: UInt8?
    var spatialAudioMode: SpatialAudioMode?
    var confirmedAt: Date?
    var isStale: Bool
    var writesEnabled: Bool
}
```

Every state publication increments `revision` and emits a complete immutable snapshot.

- [ ] **Step 4: Implement supported-device validation**

Create `QCUltraGen1Profile.json` from the sanitized Plan 1 evidence with:

```json
{
  "schemaVersion": 1,
  "acceptedProductNames": ["Bose QuietComfort Ultra Headphones"],
  "requiredFunctionBlocks": [0, 1, 2, 5, 7, 31],
  "requiresAudioModesCapabilities": true
}
```

Use the exact product string observed by the probe; include additional strings only when physically verified. A name match alone is insufficient: capabilities and essential reads must also parse before `writesEnabled` becomes true.

- [ ] **Step 5: Implement the session event loop**

The actor starts exactly one task consuming `transport.events`. It tracks a monotonically increasing `connectionGeneration`; every pending request records the generation and ignores late notifications after disconnect/reconnect.

- [ ] **Step 6: Implement initial query order**

After `.channelReady`, execute one query at a time:

1. Product name/identity.
2. AudioModes capabilities.
3. All mode indices.
4. Current mode.
5. Battery.
6. Each valid mode configuration.
7. Standby.
8. Spatial audio.

Enter `.connected` only after supported identity, capabilities, valid mode list, current mode, and battery are confirmed. Standby/spatial may remain nil if the device returns a typed unsupported response.

- [ ] **Step 7: Run state and synchronization tests**

```bash
make macos-test
```

Expected: unsupported devices fail closed; supported scripted sessions reach connected with a complete snapshot.

- [ ] **Step 8: Commit the state machine**

```bash
git add apps/macos/UltraController/App/Session apps/macos/UltraController/App/Resources apps/macos/UltraController/Tests/Session
git commit -m "feat: add authoritative headphone session"
```

### Task 5: Implement single-flight requests and essential command confirmation

**Files:**
- Create: `apps/macos/UltraController/App/Session/BMAPRequestKey.swift`
- Create: `apps/macos/UltraController/App/Session/PendingRequest.swift`
- Create: `apps/macos/UltraController/App/Session/HeadphoneCommand.swift`
- Create: `apps/macos/UltraController/App/Session/CommandExecutor.swift`
- Modify: `apps/macos/UltraController/App/Session/HeadphoneSession.swift`
- Test: `apps/macos/UltraController/Tests/Session/CommandExecutorTests.swift`
- Test: `apps/macos/UltraController/Tests/Session/EssentialCommandTests.swift`

**Interfaces:**
- Consumes: connected `HeadphoneSession` and BMAP builders/parsers.
- Produces: `setCurrentMode`, `setStandby`, `setSpatialAudio`, `powerOff`, and `refresh` APIs with verified results.

- [ ] **Step 1: Write command tests**

```swift
func testSetModeDoesNotSucceedUntilReadBackMatches() async throws {
    let fixture = try await SessionFixture.connected()
    let task = Task { try await fixture.session.setCurrentMode(2) }
    await fixture.waitForWrite(functionBlock: .audioModes, function: 0x03)
    XCTAssertFalse(task.isCancelled)
    fixture.respondCurrentMode(1)
    await XCTAssertThrowsErrorAsync(try await task.value, matching: .verificationMismatch)
}

func testPowerOffRequiresExpectedDisconnect() async throws {
    let fixture = try await SessionFixture.connected()
    let task = Task { try await fixture.session.powerOff() }
    await fixture.waitForWrite(functionBlock: .control, function: 0x04)
    fixture.transport.emit(.disconnected(.qcUltraCandidate.id, nil))
    try await task.value
    XCTAssertEqual(await fixture.latestSnapshot().phase, .unavailable)
}
```

- [ ] **Step 2: Run and verify failure**

```bash
make macos-test
```

Expected: FAIL because command APIs are undefined.

- [ ] **Step 3: Define request correlation and command API**

```swift
struct BMAPRequestKey: Hashable, Sendable {
    let functionBlock: BMAPFunctionBlock
    let function: UInt8
}

enum HeadphoneCommand: Sendable, Equatable {
    case setCurrentMode(UInt8)
    case setStandby(UInt8)
    case setSpatialAudio(SpatialAudioMode)
    case powerOff
    case refresh
}
```

Only one `PendingRequest` or mutating command may own response attribution at once. Unsolicited recognized status notifications still update the snapshot after they are parsed.

- [ ] **Step 4: Implement the ordinary mutation transaction**

For mode, standby, and spatial audio:

1. Validate connected generation, identity, and capability.
2. Encode and segment the write.
3. Write every segment.
4. Wait for immediate BMAP error/result when the function emits one.
5. Issue the matching GET.
6. Parse and compare the returned value.
7. Update/publish snapshot only from confirmed data.
8. Throw `.verificationMismatch` with requested and actual values on mismatch.

- [ ] **Step 5: Implement ambiguous-timeout handling**

A timed-out mutation is never replayed. Issue its read-back query once:

- If read-back equals requested, return success.
- If read-back differs, throw `.verificationMismatch`.
- If read-back also times out, throw `.outcomeUnknown` and mark snapshot stale.

- [ ] **Step 6: Implement Power Off completion**

After writing `PowerMessages.powerOff()`:

- Treat a BMAP error as failure.
- Wait up to five seconds for disconnect of the current generation.
- On expected disconnect, cancel automatic reconnect until explicit user reconnect or next process launch.
- If no disconnect occurs, return `.outcomeUnknown`; do not show success.

- [ ] **Step 7: Coalesce repeated actions**

- Drop a queued duplicate refresh.
- Replace a queued, not-yet-started mode selection with the latest selection.
- Do not cancel an already-written mutation.
- Disable conflicting UI through published pending-command state rather than accepting unlimited writes.

- [ ] **Step 8: Run command tests and commit**

```bash
make macos-test
git add apps/macos/UltraController/App/Session apps/macos/UltraController/Tests/Session
git commit -m "feat: verify essential headphone commands"
```

### Task 6: Add reconnect, stale-state, sleep/wake, and forget-device behavior

**Files:**
- Create: `apps/macos/UltraController/App/Lifecycle/SleepWakeMonitor.swift`
- Modify: `apps/macos/UltraController/App/Session/HeadphoneSession.swift`
- Test: `apps/macos/UltraController/Tests/Session/ReconnectSessionTests.swift`
- Test: `apps/macos/UltraController/Tests/Session/SleepWakeSessionTests.swift`
- Test: `apps/macos/UltraController/Tests/Session/ForgetDeviceTests.swift`

**Interfaces:**
- Consumes: session, clock, transport.
- Produces: bounded automatic reconnect; `suspendForSleep`, `resumeAfterWake`, `manualReconnect`, and `forgetDevice` behavior.

- [ ] **Step 1: Write reconnect and sleep tests**

Test exact delays, one scan at a time, reset after stable connection, pause while sleeping, and immediate manual reconnect. Test that `forgetDevice` clears selected ID, pending tasks, cached state, and reconnect intent.

- [ ] **Step 2: Run and verify failure**

```bash
make macos-test
```

Expected: new reconnect/sleep tests fail.

- [ ] **Step 3: Implement bounded reconnect**

On unexpected disconnect:

1. Mark confirmed values stale immediately.
2. Cancel old-generation requests.
3. Publish `.reconnecting(attempt: n)`.
4. Sleep via `SessionClock` using `ReconnectPolicy`.
5. Try saved-ID retrieval before scanning.
6. Prevent concurrent attempts with one `reconnectTask`.
7. Cap repeated delay at 30 seconds.

- [ ] **Step 4: Implement public sleep/wake monitoring**

`SleepWakeMonitor` observes:

```swift
NSWorkspace.willSleepNotification
NSWorkspace.didWakeNotification
```

It invokes `session.suspendForSleep()` and `session.resumeAfterWake()` in tasks. On sleep, stop scanning and cancel timers without forgetting the selected device. On wake, start a fresh reconnect and full state synchronization.

- [ ] **Step 5: Implement forget-device cleanup**

`forgetDevice()` must:

- Stop scanning.
- Disconnect current peripheral.
- Cancel reconnect and command tasks.
- Increment connection generation.
- Clear selected ID and snapshot device values.
- Publish `.unconfigured`.
- Emit a callback used later to clear persisted preferences/shared snapshot.

- [ ] **Step 6: Run tests and commit**

```bash
make macos-test
git add apps/macos/UltraController/App/Lifecycle apps/macos/UltraController/App/Session apps/macos/UltraController/Tests/Session
git commit -m "feat: add reliable reconnect and lifecycle recovery"
```

### Task 7: Add a debug connectivity harness and verify the real session

**Files:**
- Create: `apps/macos/UltraController/App/Application/ApplicationModel.swift`
- Create: `apps/macos/UltraController/App/Diagnostics/ConnectivityHarnessView.swift`
- Modify: `apps/macos/UltraController/App/Application/UltraControllerApp.swift`
- Delete after Plan 3 replaces it: `apps/macos/UltraController/App/Overview/PlaceholderOverviewView.swift`
- Test: `apps/macos/UltraController/Tests/Application/ApplicationModelTests.swift`
- Update: `docs/protocol/qc-ultra-baseline-probe.md`

**Interfaces:**
- Consumes: production session and transport.
- Produces: one `@MainActor ApplicationModel` and physical evidence that production code—not the temporary probe—performs all essential operations.

- [ ] **Step 1: Write application-model tests**

```swift
@MainActor
func testApplicationModelNeverOptimisticallyChangesConfirmedMode() async throws {
    let session = SessionSpy(snapshot: .connected(currentModeID: 1))
    let model = ApplicationModel(session: session)
    model.selectMode(2)
    XCTAssertEqual(model.snapshot.currentModeID, 1)
    XCTAssertEqual(model.pendingAction, .setMode(2))
}
```

- [ ] **Step 2: Implement `ApplicationModel`**

Expose read-only `snapshot`, `pendingAction`, `lastError`, candidates, and user actions. All actions launch one tracked `Task`; errors map to concise presentation values but preserve typed diagnostic details.

- [ ] **Step 3: Build the debug harness**

The harness displays:

- Connection phase and candidate list.
- Connect, reconnect, refresh, and forget-device actions.
- Battery, modes, current mode, standby, and spatial audio.
- Essential mutation buttons.
- Pending action and exact confirmation result.
- Sanitized event log.

Wrap it in `#if DEBUG`; Plan 3 replaces it with product surfaces.

- [ ] **Step 4: Run automated tests**

```bash
make macos-test-core
make macos-test
make macos-build
```

Expected: all commands pass.

- [ ] **Step 5: Run the physical production-session checklist**

Using the debug build:

1. Cold-connect via saved-ID retrieval.
2. Confirm initial state.
3. Switch Quiet → Aware → original mode; verify each read-back.
4. Set standby to a different allowed value, verify, then restore original.
5. Set spatial audio through each supported value, verify, then restore original.
6. Disconnect out of range and return; verify bounded reconnect.
7. Sleep/wake the Mac; verify reconnection and state reload.
8. Power off and confirm the app does not immediately reconnect.
9. Manually reconnect after powering headphones back on.

Record exact results and firmware in the protocol evidence document.

- [ ] **Step 6: Commit harness and evidence**

```bash
git add apps/macos/UltraController/App apps/macos/UltraController/Tests docs/protocol/qc-ultra-baseline-probe.md
git commit -m "test: verify production QC Ultra session"
```

### Task 8: Run the Plan 2 checkpoint

**Files:**
- Verify all Plan 2 files and evidence.

**Interfaces:**
- Produces for Plan 3: production `CoreBluetoothTransport`, authoritative `HeadphoneSession`, `ApplicationModel`, essential commands, persistence callbacks, and lifecycle recovery.

- [ ] **Step 1: Run all automated tests twice**

```bash
cargo test --workspace
make macos-test-core
make macos-test
make macos-test
```

Expected: both consecutive macOS test runs pass; repeated execution exposes leaked tasks or global-state coupling.

- [ ] **Step 2: Run strict-concurrency release build**

```bash
xcodebuild \
  -project apps/macos/UltraController/UltraController.xcodeproj \
  -scheme UltraController \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_STRICT_CONCURRENCY=complete \
  build
```

Expected: BUILD SUCCEEDED with no Swift concurrency errors.

- [ ] **Step 3: Verify no second Bluetooth owner exists**

```bash
grep -R "CBCentralManager(" apps/macos/UltraController \
  --include='*.swift' \
  | grep -v 'CoreBluetoothTransport.swift' \
  | grep -v 'ProtocolProbe/' \
  && exit 1 || exit 0
```

Expected: exit 0 with no production match outside `CoreBluetoothTransport`.

- [ ] **Step 4: Verify physical evidence contains essential operations**

```bash
for phrase in "mode read-back" "standby read-back" "spatial audio" "sleep/wake" "power off"; do
  grep -qi "$phrase" docs/protocol/qc-ultra-baseline-probe.md || exit 1
done
```

Expected: exit 0.

Plan 2 is complete only after essential production-session commands work on the physical headset and every user-visible success has its defined confirmation evidence.
