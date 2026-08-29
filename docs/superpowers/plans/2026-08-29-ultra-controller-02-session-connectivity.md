# Ultra Controller Session and Connectivity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the temporary protocol probe with one production CoreBluetooth transport and a fully tested `HeadphoneSession` actor that synchronizes state, serializes commands, reconnects safely, and verifies essential controls on the physical QC Ultra.

**Architecture:** `CoreBluetoothTransport` is a `@MainActor` delegate adapter that owns Apple Bluetooth objects and emits bounded value-type events through a nonisolated `AsyncStream`. `HeadphoneSession` is a separate actor that owns the connection state machine, request serialization, command confirmation, reconnection, and authoritative snapshots. Tests use a deterministic fake transport, clock, and `SessionFixture`; no SwiftUI view or App Intent accesses CoreBluetooth directly.

**Tech Stack:** Swift 6 strict concurrency, CoreBluetooth, Foundation async sequences, XCTest, `NSWorkspace` sleep/wake notifications, `os.Logger`, `HeadphoneCore` from Plan 1.

**Spec:** `docs/superpowers/specs/2026-08-29-qc-ultra-macos-controller-design.md`

## Global Constraints

- Plan 1 must pass, including committed physical baseline-probe evidence.
- Maintain exactly one `CBCentralManager` and one selected peripheral connection.
- Do not use CoreBluetooth objects outside `CoreBluetoothTransport`.
- Serialize BMAP operations because the protocol has no general request identifier.
- Never automatically retry an ambiguous mutation; read the affected property instead.
- Use reconnect delays `1s, 2s, 5s, 10s, 30s`, then remain at 30 seconds without a tight scan loop.
- Power Off succeeds only after an accepted write and expected link loss inside the command window.
- A disconnect invalidates commands and responses tied to the old connection generation.
- Keep the main app local-only and sandboxed.

---

## File Map

| Path | Responsibility |
|---|---|
| `Packages/HeadphoneCore/Sources/HeadphoneCore/Transport/*` | Transport-neutral IDs, candidates, events, errors, and protocol. |
| `App/Bluetooth/CoreBluetoothTransport*.swift` | Apple delegate adapter and BLE write/discovery lifecycle. |
| `App/Bluetooth/DiscoveryPolicy.swift` | Pure retrieve/filtered-scan/fallback policy. |
| `App/Session/HeadphoneSession.swift` | Authoritative connection, request, command, and snapshot actor. |
| `App/Session/ConnectionPhase.swift` | Explicit public state machine. |
| `App/Session/CommandExecutor.swift` | Single-flight operation execution and confirmation. |
| `App/Session/ReconnectPolicy.swift` | Deterministic bounded backoff. |
| `App/Session/SessionClock.swift` | Production/test time abstraction. |
| `App/Lifecycle/SleepWakeMonitor.swift` | Public macOS notifications converted into session calls. |
| `Tests/Fakes/FakeHeadphoneTransport.swift` | Scriptable transport. |
| `Tests/Fakes/TestSessionClock.swift` | Manually advanced clock. |
| `Tests/Fakes/SessionFixture.swift` | Shared connected/disconnected test harness and response helpers. |
| `Tests/Session/*Tests.swift` | State, command, timeout, reconnect, and cancellation tests. |
| `App/Diagnostics/ConnectivityHarnessView.swift` | Debug-only physical integration surface used before product UI. |

### Task 1: Define transport-neutral IDs, events, errors, and protocol

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
- Produces: `HeadphoneID`, `DiscoveredHeadphone`, `TransportEvent`, and the `HeadphoneTransport` contract used by real and fake transports.

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

    func testTransportEventContainsOnlyCodableValues() throws {
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
public protocol HeadphoneTransport: AnyObject, Sendable {
    var events: AsyncStream<TransportEvent> { get }

    @MainActor func retrievePeripheral(id: HeadphoneID) async
    @MainActor func retrieveConnectedBMAPPeripherals() async
    @MainActor func startScanning(filterToBMAPService: Bool) async throws
    @MainActor func stopScanning() async
    @MainActor func connect(to id: HeadphoneID) async throws
    @MainActor func disconnect() async
    @MainActor func write(segment: [UInt8]) async throws
}
```

`write(segment:)` returns only after CoreBluetooth accepts that segment according to the selected write type. Device/application success remains a session responsibility.

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
- Consumes: `HeadphoneTransport` and Plan 1's physical discovery/channel evidence.
- Produces: one `@MainActor final class CoreBluetoothTransport` with a single central, selected peripheral, BMAP characteristic, and nonisolated event stream.

- [ ] **Step 1: Write discovery-policy and state-mapping tests**

```swift
final class DiscoveryPolicyTests: XCTestCase {
    func testSavedIdentifierIsTriedBeforeScanning() {
        let policy = DiscoveryPolicy(savedID: HeadphoneID(rawValue: UUID()))
        XCTAssertEqual(policy.nextAction(after: .started), .retrieveSaved)
    }

    func testFilteredScanFallsBackToOneBoundedUnfilteredScan() {
        var policy = DiscoveryPolicy(savedID: nil)
        XCTAssertEqual(policy.nextAction(after: .started), .retrieveConnected)
        XCTAssertEqual(policy.nextAction(after: .retrievalEmpty), .scanFiltered(seconds: 5))
        XCTAssertEqual(policy.nextAction(after: .scanEmpty), .scanUnfiltered(seconds: 5))
        XCTAssertEqual(policy.nextAction(after: .scanEmpty), .stopUnavailable)
    }
}

final class CoreBluetoothStateMapperTests: XCTestCase {
    func testUnauthorizedIsDistinctFromPoweredOff() {
        XCTAssertEqual(CoreBluetoothStateMapper.map(.unauthorized), .unauthorized)
        XCTAssertEqual(CoreBluetoothStateMapper.map(.poweredOff), .poweredOff)
    }
}
```

- [ ] **Step 2: Run and verify failure**

```bash
make macos-test
```

Expected: FAIL because policy/mapper types are undefined.

- [ ] **Step 3: Implement constants and pure policy**

```swift
enum BluetoothUUIDs {
    static let bmapService = CBUUID(string: "FEBE")
    static let secure = CBUUID(string: "C65B8F2F-AEE2-4C89-B758-BC4892D6F2D8")
    static let unsecure = CBUUID(string: "D417C028-9818-4354-99D1-2AC09D074591")
}
```

Map every `CBManagerState`. `DiscoveryPolicy` must permit only one active action and produce retrieve-saved → retrieve-connected → filtered scan → unfiltered bounded scan → unavailable.

- [ ] **Step 4: Create the event stream and one-central invariant**

```swift
@MainActor
final class CoreBluetoothTransport: NSObject, HeadphoneTransport {
    nonisolated let events: AsyncStream<TransportEvent>
    private let continuation: AsyncStream<TransportEvent>.Continuation
    private let central: CBCentralManager
    private var peripherals: [HeadphoneID: CBPeripheral] = [:]
    private var selectedPeripheral: CBPeripheral?
    private var selectedCharacteristic: CBCharacteristic?
    private var selectedChannel: TransportChannel?
    private var scanTimeoutTask: Task<Void, Never>?

    override init() {
        let pair = AsyncStream<TransportEvent>.makeStream(bufferingPolicy: .bufferingNewest(256))
        self.events = pair.stream
        self.continuation = pair.continuation
        self.central = CBCentralManager(delegate: nil, queue: .main)
        super.init()
        self.central.delegate = self
    }
}
```

Construct `CBCentralManager` exactly once. Do not enable CoreBluetooth state restoration in v1.

- [ ] **Step 5: Implement retrieval and bounded scanning**

- `retrievePeripheral(id:)` calls `retrievePeripherals(withIdentifiers:)`.
- `retrieveConnectedBMAPPeripherals()` calls `retrieveConnectedPeripherals(withServices:)`.
- Filtered scanning uses `[BluetoothUUIDs.bmapService]`.
- Unfiltered fallback may emit name-hint candidates, but they remain unverified until session BMAP validation.
- Retain every emitted peripheral in `peripherals`.
- `stopScanning()` always stops the central and cancels the timeout task.

- [ ] **Step 6: Implement service/characteristic discovery**

After connect: discover only BMAP service, then secure/unsecure UUIDs. Select secure when it supports `.notify` and either `.write` or `.writeWithoutResponse`; otherwise select qualifying unsecure. Subscribe and emit `.channelReady` only after notification state confirms enabled.

- [ ] **Step 7: Implement segment writes with backpressure**

Prefer `.withResponse`. Otherwise wait for `canSendWriteWithoutResponse`, write one segment, and resume from `peripheralIsReady(toSendWriteWithoutResponse:)`. Map `CBError` to bounded `HeadphoneTransportError` values without exposing CoreBluetooth objects/errors outside the adapter.

- [ ] **Step 8: Emit copied notification bytes**

```swift
let bytes = characteristic.value.map { [UInt8]($0) } ?? []
continuation.yield(.notification(id, bytes))
```

Do not parse BMAP in delegate callbacks.

- [ ] **Step 9: Run tests/build and commit**

```bash
make macos-test
make macos-build
git add apps/macos/UltraController/App/Bluetooth apps/macos/UltraController/Tests/Bluetooth
git commit -m "feat: add CoreBluetooth transport adapter"
```

### Task 3: Add deterministic clocks, reconnect policy, fake transport, and session fixture

**Files:**
- Create: `apps/macos/UltraController/App/Session/SessionClock.swift`
- Create: `apps/macos/UltraController/App/Session/ReconnectPolicy.swift`
- Create: `apps/macos/UltraController/Tests/Fakes/TestSessionClock.swift`
- Create: `apps/macos/UltraController/Tests/Fakes/FakeHeadphoneTransport.swift`
- Create: `apps/macos/UltraController/Tests/Fakes/SessionFixture.swift`
- Create: `apps/macos/UltraController/Tests/Fakes/HeadphoneTestFixtures.swift`
- Test: `apps/macos/UltraController/Tests/Session/ReconnectPolicyTests.swift`
- Test: `apps/macos/UltraController/Tests/Fakes/FakeHeadphoneTransportTests.swift`

**Interfaces:**
- Consumes: `HeadphoneTransport`.
- Produces: `SessionClock`, `ContinuousSessionClock`, `ReconnectPolicy`, `TestSessionClock`, `FakeHeadphoneTransport`, and reusable `SessionFixture` response helpers.

- [ ] **Step 1: Write reconnect-policy tests**

```swift
final class ReconnectPolicyTests: XCTestCase {
    func testBackoffCapsAtThirtySeconds() {
        var policy = ReconnectPolicy()
        XCTAssertEqual((0..<7).map { _ in policy.nextDelay() },
                       [.seconds(1), .seconds(2), .seconds(5), .seconds(10), .seconds(30), .seconds(30), .seconds(30)])
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

- [ ] **Step 3: Implement clock and policy**

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

`TestSessionClock` records sleeps and resumes only when the test calls `advanceNextSleep()`. Session tests never use wall-clock delay.

- [ ] **Step 4: Implement the fake transport**

`@MainActor final class FakeHeadphoneTransport` owns a nonisolated event stream, records method calls and segments, and exposes:

```swift
func emit(_ event: TransportEvent)
func queueWriteFailure(_ error: HeadphoneTransportError)
func clearRecordedCalls()
var writtenSegments: [[UInt8]] { get }
var calls: [RecordedTransportCall] { get }
```

- [ ] **Step 5: Define `SessionFixture` once for every later test**

```swift
@MainActor
final class SessionFixture {
    let transport = FakeHeadphoneTransport()
    let clock = TestSessionClock()
    lazy var session = HeadphoneSession(transport: transport, clock: clock)

    static func connected() async throws -> SessionFixture { /* script full supported sync */ }
    func waitForPacket(functionBlock: BMAPFunctionBlock, function: UInt8) async { /* inspect segmented writes */ }
    func respond(_ packet: BMAPPacket) { /* segment and emit notification */ }
    func respondCurrentMode(_ id: UInt8) { /* typed helper */ }
    func respondStandby(_ minutes: UInt8) { /* typed helper */ }
    func respondSpatial(_ mode: SpatialAudioMode) { /* typed helper */ }
    func latestSnapshot() async -> HeadphoneSnapshot { /* consume or ask session */ }
}
```

Implement the bodies in this task; comments above describe the exact responsibilities, not code to leave unfinished. `HeadphoneTestFixtures` contains deterministic candidate, profile, product, capability, mode, and battery packets.

- [ ] **Step 6: Run tests and commit**

```bash
make macos-test
git add apps/macos/UltraController/App/Session apps/macos/UltraController/Tests/Fakes apps/macos/UltraController/Tests/Session/ReconnectPolicyTests.swift
git commit -m "test: add deterministic session fixtures"
```

### Task 4: Implement the authoritative state machine and initial synchronization

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
- Consumes: one transport, clock, BMAP parsers, and the Plan 1 identity/capability fingerprint.
- Produces: `snapshots`, `start(savedID:)`, `select(_:)`, `manualReconnect()`, `forgetDevice()`, `suspendForSleep()`, `resumeAfterWake()`, and `currentSnapshot()`.

- [ ] **Step 1: Write state-transition tests**

```swift
func testUnsupportedDeviceNeverEnablesWrites() async throws {
    let fixture = await MainActor.run { SessionFixture() }
    await fixture.session.start(savedID: nil)
    await MainActor.run {
        fixture.transport.emit(.availabilityChanged(.poweredOn))
        fixture.transport.emit(.discovered(.qcUltraCandidate))
    }
    await fixture.session.select(.qcUltraCandidate.id)
    await MainActor.run {
        fixture.transport.emit(.connected(.qcUltraCandidate.id))
        fixture.transport.emit(.channelReady(.qcUltraCandidate.id, .secure))
    }
    await fixture.waitForPacket(functionBlock: .settings, function: 0x02)
    fixture.respond(ProductMessages.statusName("Bose Other Product"))
    let snapshot = await fixture.session.currentSnapshot()
    XCTAssertEqual(snapshot.phase, .failed(.unsupportedDevice))
    XCTAssertFalse(snapshot.writesEnabled)
}
```

Also test every legal state transition and ignore late old-generation events.

- [ ] **Step 2: Run and verify failure**

```bash
make macos-test
```

Expected: FAIL because session state types are undefined.

- [ ] **Step 3: Define explicit state and complete snapshots**

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
    var firmwareVersion: String?
    var battery: [BatteryComponent]
    var capabilities: AudioModeCapabilities?
    var modes: [AudioMode]
    var currentModeID: UInt8?
    var standbyMinutes: UInt8?
    var spatialAudioMode: SpatialAudioMode?
    var confirmedAt: Date?
    var isStale: Bool
    var writesEnabled: Bool
    var pendingCommand: HeadphoneCommand?
}
```

Every publication increments `revision` and emits a complete immutable snapshot.

- [ ] **Step 4: Implement supported-device validation**

Create `QCUltraGen1Profile.json` from Plan 1's evidence. Example shape:

```json
{
  "schemaVersion": 1,
  "acceptedProductNames": ["Bose QuietComfort Ultra Headphones"],
  "requiredFunctionBlocks": [0, 1, 2, 5, 7, 31],
  "requiresAudioModesCapabilities": true
}
```

Replace the example product string with the exact observed value. A name match alone is insufficient: AudioModes capabilities, mode list/current, and battery must parse before `writesEnabled` becomes true.

- [ ] **Step 5: Implement one event-consumer task and connection generation**

`start(savedID:)` creates the event-consumer task once. Maintain `connectionGeneration: UInt64`; pending requests record it and old-generation responses/disconnects cannot complete current work.

- [ ] **Step 6: Implement initial query order**

After `.channelReady`, run one query at a time:

1. Product name/identity.
2. AudioModes capabilities.
3. All mode indexes.
4. Current mode.
5. Battery.
6. Each valid ModeConfig.
7. Standby.
8. Spatial audio.

Enter connected only after supported identity, capabilities, mode list, current mode, and battery. Typed unsupported responses may leave standby/spatial nil.

- [ ] **Step 7: Run tests and commit**

```bash
make macos-test
git add apps/macos/UltraController/App/Session apps/macos/UltraController/App/Resources/QCUltraGen1Profile.json apps/macos/UltraController/Tests/Session
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
- Consumes: connected session and BMAP builders/parsers.
- Produces: `setCurrentMode`, `setStandby`, `setSpatialAudio`, `powerOff`, and `refresh` with verified results.

- [ ] **Step 1: Write confirmation tests**

```swift
func testSetModeDoesNotChangeConfirmedSnapshotBeforeReadBack() async throws {
    let fixture = try await MainActor.run { try await SessionFixture.connected() }
    let task = Task { try await fixture.session.setCurrentMode(2) }
    await fixture.waitForPacket(functionBlock: .audioModes, function: 0x03)
    XCTAssertEqual(await fixture.session.currentSnapshot().currentModeID, 1)
    fixture.respondCurrentMode(1)
    await XCTAssertThrowsErrorAsync(try await task.value) { error in
        XCTAssertEqual(error as? HeadphoneSessionError, .verificationMismatch)
    }
}

func testPowerOffRequiresExpectedDisconnect() async throws {
    let fixture = try await MainActor.run { try await SessionFixture.connected() }
    let task = Task { try await fixture.session.powerOff() }
    await fixture.waitForPacket(functionBlock: .control, function: 0x04)
    await MainActor.run {
        fixture.transport.emit(.disconnected(.qcUltraCandidate.id, nil))
    }
    try await task.value
    XCTAssertEqual(await fixture.session.currentSnapshot().phase, .unavailable)
}
```

Use an async factory helper outside `MainActor.run` if the compiler rejects an async closure there; the production requirement is deterministic setup, not that exact helper spelling.

- [ ] **Step 2: Run and verify failure**

```bash
make macos-test
```

Expected: FAIL because command APIs are undefined.

- [ ] **Step 3: Define correlation and command types**

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

Only one pending request or mutating command owns response attribution. Recognized unsolicited status notifications may update the snapshot after parsing.

- [ ] **Step 4: Implement ordinary mutation transaction**

For mode, standby, and spatial audio:

1. Validate generation, identity, connection, and capability.
2. Encode/segment/write.
3. Observe immediate BMAP error/result when emitted.
4. Issue matching GET.
5. Parse/compare.
6. Update snapshot only from confirmed data.
7. Throw `.verificationMismatch` on disagreement.

- [ ] **Step 5: Implement ambiguous timeout behavior**

Never replay a timed-out mutation. Read back once: matching value means success; differing value means mismatch; second timeout means `.outcomeUnknown` and stale state.

- [ ] **Step 6: Implement Power Off**

Write Power Off, fail on immediate BMAP/transport error, then wait five seconds for current-generation disconnect. On disconnect, suppress automatic reconnect until explicit manual reconnect or next process launch. Without disconnect, return `.outcomeUnknown`.

- [ ] **Step 7: Coalesce repeated actions**

Drop duplicate queued refreshes, replace a not-yet-started mode selection with the newest selection, never cancel an already-written mutation, and publish pending command so UI disables conflicts.

- [ ] **Step 8: Run tests and commit**

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
- Produces: bounded reconnect; `suspendForSleep`, `resumeAfterWake`, `manualReconnect`, and `forgetDevice`.

- [ ] **Step 1: Write exact reconnect/lifecycle tests**

Assert delay sequence, one scan/connection attempt at a time, reset after confirmed connection, pause while sleeping, immediate manual reconnect, and full forget cleanup.

- [ ] **Step 2: Run and verify failure**

```bash
make macos-test
```

Expected: reconnect/sleep tests fail.

- [ ] **Step 3: Implement bounded reconnect**

On unexpected disconnect: mark state stale, cancel old-generation work, publish reconnect attempt, sleep via injected clock, retrieve saved ID before scanning, use one reconnect task, and cap at 30 seconds.

- [ ] **Step 4: Implement public sleep/wake monitor**

Observe `NSWorkspace.willSleepNotification` and `NSWorkspace.didWakeNotification`. Sleep stops scan/timers without forgetting selection; wake performs a clean reconnect/full sync.

- [ ] **Step 5: Implement forget cleanup**

Stop scan, disconnect, cancel reconnect/commands, increment generation, clear selected/device state, publish unconfigured, and invoke a later persistence callback.

- [ ] **Step 6: Run tests and commit**

```bash
make macos-test
git add apps/macos/UltraController/App/Lifecycle apps/macos/UltraController/App/Session apps/macos/UltraController/Tests/Session
git commit -m "feat: add reliable reconnect and lifecycle recovery"
```

### Task 7: Add `ApplicationModel`, debug harness, and physical production-session verification

**Files:**
- Create: `apps/macos/UltraController/App/Application/ApplicationModel.swift`
- Create: `apps/macos/UltraController/App/Application/PendingAction.swift`
- Create: `apps/macos/UltraController/App/Diagnostics/ConnectivityHarnessView.swift`
- Modify: `apps/macos/UltraController/App/Application/UltraControllerApp.swift`
- Test: `apps/macos/UltraController/Tests/Application/ApplicationModelTests.swift`
- Update: `docs/protocol/qc-ultra-baseline-probe.md`

**Interfaces:**
- Consumes: concrete production session in this plan; Plan 3 introduces the `HeadphoneSessionClient` protocol around the same methods.
- Produces: one `@MainActor @Observable ApplicationModel` and physical evidence that production—not probe—code performs essential operations.

- [ ] **Step 1: Write model test using the real session plus fake transport**

```swift
@MainActor
func testModelKeepsConfirmedModeUntilSessionReadBack() async throws {
    let fixture = try await SessionFixture.connected()
    let model = ApplicationModel(session: fixture.session)
    model.selectMode(2)
    await fixture.waitForPacket(functionBlock: .audioModes, function: 0x03)
    XCTAssertEqual(model.snapshot.currentModeID, 1)
    XCTAssertEqual(model.pendingAction, .setMode(2))
}
```

- [ ] **Step 2: Implement observable model**

```swift
@MainActor
@Observable
final class ApplicationModel {
    private let session: HeadphoneSession
    private var observationTask: Task<Void, Never>?

    private(set) var snapshot: HeadphoneSnapshot
    private(set) var candidates: [DiscoveredHeadphone] = []
    private(set) var pendingAction: PendingAction?
    private(set) var lastError: PresentationError?
}
```

Track one task per user action. Map typed errors into concise presentation values while retaining diagnostic category/code.

- [ ] **Step 3: Build the DEBUG connectivity harness**

Display phase/candidates, Connect/Reconnect/Refresh/Forget, battery/modes/current/standby/spatial, essential mutation controls, pending action, confirmation result, and sanitized event log. Wrap in `#if DEBUG`; Plan 3 replaces it with product surfaces.

- [ ] **Step 4: Run automated tests/build**

```bash
make macos-test-core
make macos-test
make macos-build
```

- [ ] **Step 5: Run physical production-session checklist**

Cold-connect via saved ID, confirm initial state, cycle modes and restore, change/restore standby, change/restore spatial if supported, out-of-range return, sleep/wake, Power Off, power on, and manual reconnect. Record exact read-back and firmware in baseline evidence.

- [ ] **Step 6: Commit**

```bash
git add apps/macos/UltraController/App apps/macos/UltraController/Tests/Application docs/protocol/qc-ultra-baseline-probe.md
git commit -m "test: verify production QC Ultra session"
```

### Task 8: Run the Plan 2 checkpoint

**Files:**
- Verify all Plan 2 files/evidence.

**Interfaces:**
- Produces for Plan 3: production transport, authoritative session, essential commands, observable app model, persistence callback, and lifecycle recovery.

- [ ] **Step 1: Run all tests twice**

```bash
cargo test --workspace
make macos-test-core
make macos-test
make macos-test
```

Expected: both macOS runs pass; repeated execution catches leaked tasks/global coupling.

- [ ] **Step 2: Run strict-concurrency Release build**

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

Expected: BUILD SUCCEEDED with no concurrency error.

- [ ] **Step 3: Verify one production Bluetooth owner**

```bash
MATCHES="$(grep -R "CBCentralManager(" apps/macos/UltraController/App --include='*.swift' || true)"
test "$(printf '%s\n' "$MATCHES" | sed '/^$/d' | wc -l | tr -d ' ')" = "1"
printf '%s\n' "$MATCHES" | grep -q 'CoreBluetoothTransport.swift'
```

- [ ] **Step 4: Verify physical evidence contains essential operations**

```bash
for phrase in "mode read-back" "standby read-back" "spatial audio" "sleep/wake" "power off"; do
  grep -qi "$phrase" docs/protocol/qc-ultra-baseline-probe.md || exit 1
done
```

Plan 2 is complete only after essential production-session commands work on the physical headset and every success has its defined confirmation evidence.
