# Ultra Controller Session and Connectivity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the temporary protocol probe with one production CoreBluetooth adapter and a tested `HeadphoneSession` actor that synchronizes state, serializes requests, confirms essential mutations, reconnects safely, and survives normal macOS lifecycle changes.

**Architecture:** `CoreBluetoothTransport` is the only owner of `CBCentralManager`, `CBPeripheral`, and `CBCharacteristic`. It runs on `@MainActor`, copies callbacks into `Sendable` events, and contains no product policy. `HeadphoneSession` is a separate actor that consumes those events, owns one explicit connection generation, serializes BMAP operations, publishes immutable snapshots, and applies bounded reconnect/confirmation rules. Tests use a fake transport and manually advanced clock.

**Tech Stack:** Swift 6 strict concurrency, CoreBluetooth, Foundation async sequences, XCTest, AppKit workspace notifications, `os.Logger`, Plan 1 `HeadphoneCore`.

**Spec:** `docs/superpowers/specs/2026-08-29-qc-ultra-macos-controller-design.md`

## Global Constraints

- Plan 1, including physical baseline evidence, must pass first.
- Exactly one production `CBCentralManager` construction site.
- No CoreBluetooth type escapes `App/Bluetooth`.
- Only one BMAP request or mutation owns response attribution at a time.
- Never replay an ambiguous mutation automatically; read back once.
- Reconnect delays are exactly `1, 2, 5, 10, 30, 30…` seconds.
- Power Off is confirmed by accepted write plus expected disconnect within five seconds.
- Every request records the current connection generation; late events from an old generation are ignored.
- Every task ends with a buildable, testable tree.

---

## File Map

| Path | Responsibility |
|---|---|
| `Packages/HeadphoneCore/Sources/HeadphoneCore/Transport/*` | Framework-neutral IDs, events, errors, and transport protocol. |
| `App/Bluetooth/CoreBluetoothTransport*.swift` | Apple delegate adapter, scan/retrieve/connect/discover/write lifecycle. |
| `App/Bluetooth/DiscoveryPolicy.swift` | Pure retrieve/scan fallback policy. |
| `App/Session/HeadphoneSession.swift` | Authoritative state machine and BMAP orchestration. |
| `App/Session/CommandExecutor.swift` | Single-flight request/mutation execution. |
| `App/Session/ReconnectPolicy.swift` | Deterministic bounded delays. |
| `App/Session/SessionClock.swift` | Production/test time abstraction. |
| `App/Lifecycle/SleepWakeMonitor.swift` | Public macOS sleep/wake bridge. |
| `Tests/Fakes/*` | Fake transport, clock, packets, and connected-session fixture. |
| `App/Diagnostics/ConnectivityHarnessView.swift` | Debug-only physical production-session harness. |

### Task 1: Define the transport-neutral boundary

**Files:**
- Create: `apps/macos/UltraController/Packages/HeadphoneCore/Sources/HeadphoneCore/Transport/HeadphoneID.swift`
- Create: `.../Transport/DiscoveredHeadphone.swift`
- Create: `.../Transport/TransportAvailability.swift`
- Create: `.../Transport/TransportChannel.swift`
- Create: `.../Transport/HeadphoneTransportError.swift`
- Create: `.../Transport/TransportEvent.swift`
- Create: `.../Transport/HeadphoneTransport.swift`
- Test: `.../Tests/HeadphoneCoreTests/TransportValueTests.swift`

**Interfaces:**
- Consumes: Foundation only.
- Produces: `HeadphoneTransport` used by both real and fake implementations.

- [ ] **Step 1: Write failing value tests**

```swift
import XCTest
@testable import HeadphoneCore

final class TransportValueTests: XCTestCase {
    func testCandidateIdentityIsPeripheralUUID() {
        let id = HeadphoneID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        XCTAssertEqual(
            DiscoveredHeadphone(id: id, name: "QC Ultra", rssi: -40, advertisesBMAP: true).id,
            DiscoveredHeadphone(id: id, name: "Renamed", rssi: -70, advertisesBMAP: false).id
        )
    }

    func testEventsAreCodableValueTypes() throws {
        _ = try JSONEncoder().encode(TransportEvent.availabilityChanged(.poweredOn))
    }
}
```

Run `make macos-test-core`; expect undefined-type failure.

- [ ] **Step 2: Implement exact value types**

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

public enum TransportChannel: String, Codable, Sendable { case secure, unsecure }

public enum HeadphoneTransportError: Error, Codable, Equatable, Sendable {
    case bluetoothUnavailable(TransportAvailability)
    case unknownPeripheral(HeadphoneID)
    case connectionFailed(String?)
    case serviceMissing
    case characteristicMissing
    case notificationsFailed(String?)
    case writeFailed(String?)
    case scanFailed(String?)
}

public enum TransportEvent: Codable, Equatable, Sendable {
    case availabilityChanged(TransportAvailability)
    case discovered(DiscoveredHeadphone)
    case connected(HeadphoneID)
    case channelReady(HeadphoneID, TransportChannel)
    case notification(HeadphoneID, [UInt8])
    case disconnected(HeadphoneID, String?)
    case failed(HeadphoneTransportError)
}
```

- [ ] **Step 3: Define the actor-safe protocol**

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

`write(segment:)` confirms only CoreBluetooth acceptance, never headphone-level success.

- [ ] **Step 4: Verify and commit**

```bash
make macos-test-core
git add apps/macos/UltraController/Packages/HeadphoneCore
git commit -m "feat: define headphone transport boundary"
```

### Task 2: Implement the one production CoreBluetooth adapter

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
- Consumes: Plan 1 validated service/channel policy and `HeadphoneTransport`.
- Produces: one central, one selected peripheral, one selected BMAP characteristic, one event stream.

- [ ] **Step 1: Write pure policy tests**

```swift
final class DiscoveryPolicyTests: XCTestCase {
    func testSavedDevicePrecedesScan() {
        var policy = DiscoveryPolicy(savedID: HeadphoneID(rawValue: UUID()))
        XCTAssertEqual(policy.next(after: .started), .retrieveSaved)
        XCTAssertEqual(policy.next(after: .savedNotFound), .retrieveConnected)
        XCTAssertEqual(policy.next(after: .connectedNotFound), .scanFiltered(seconds: 5))
        XCTAssertEqual(policy.next(after: .scanFoundNothing), .scanUnfiltered(seconds: 5))
        XCTAssertEqual(policy.next(after: .scanFoundNothing), .stopUnavailable)
    }
}

final class CoreBluetoothStateMapperTests: XCTestCase {
    func testAuthorizationAndPowerAreDistinct() {
        XCTAssertEqual(CoreBluetoothStateMapper.map(.unauthorized), .unauthorized)
        XCTAssertEqual(CoreBluetoothStateMapper.map(.poweredOff), .poweredOff)
    }
}
```

Run `make macos-test`; expect failure.

- [ ] **Step 2: Implement constants and policy**

```swift
enum BluetoothUUIDs {
    static let bmapService = CBUUID(string: "FEBE")
    static let secure = CBUUID(string: "C65B8F2F-AEE2-4C89-B758-BC4892D6F2D8")
    static let unsecure = CBUUID(string: "D417C028-9818-4354-99D1-2AC09D074591")
}
```

`DiscoveryPolicy` allows one active step and one bounded unfiltered fallback only.

- [ ] **Step 3: Implement transport storage and stream**

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
        events = pair.stream
        continuation = pair.continuation
        central = CBCentralManager(delegate: nil, queue: .main)
        super.init()
        central.delegate = self
    }
}
```

Do not enable CoreBluetooth state restoration in v1.

- [ ] **Step 4: Implement retrieve/scan/connect/discovery**

- Saved ID: `retrievePeripherals(withIdentifiers:)`.
- Connected BMAP: `retrieveConnectedPeripherals(withServices:)`.
- Filtered scan: `[BluetoothUUIDs.bmapService]`, five-second timeout.
- Unfiltered fallback: five seconds; names are discovery hints only.
- Retain every emitted peripheral.
- Discover BMAP service then secure/unsecure characteristics.
- Select secure first only when it supports notify and a write mode; otherwise qualifying unsecure.
- Emit `channelReady` only after notifications are confirmed enabled.

- [ ] **Step 5: Implement writes and copied notifications**

Prefer `.withResponse`. For `.withoutResponse`, wait for `canSendWriteWithoutResponse` and resume from `peripheralIsReady(toSendWriteWithoutResponse:)`. Copy notification `Data` immediately to `[UInt8]`; never parse BMAP in delegate callbacks. Map all framework errors to `HeadphoneTransportError`.

- [ ] **Step 6: Verify and commit**

```bash
make macos-test
make macos-build
git add apps/macos/UltraController/App/Bluetooth apps/macos/UltraController/Tests/Bluetooth
git commit -m "feat: add CoreBluetooth transport adapter"
```

### Task 3: Add deterministic time and fake transport

**Files:**
- Create: `apps/macos/UltraController/App/Session/SessionClock.swift`
- Create: `apps/macos/UltraController/App/Session/ReconnectPolicy.swift`
- Create: `apps/macos/UltraController/Tests/Fakes/TestSessionClock.swift`
- Create: `apps/macos/UltraController/Tests/Fakes/FakeHeadphoneTransport.swift`
- Create: `apps/macos/UltraController/Tests/Fakes/HeadphoneTestFixtures.swift`
- Test: `apps/macos/UltraController/Tests/Session/ReconnectPolicyTests.swift`
- Test: `apps/macos/UltraController/Tests/Fakes/FakeHeadphoneTransportTests.swift`

**Interfaces:**
- Produces: clock, reconnect policy, fake transport, deterministic packet/candidate fixtures.

- [ ] **Step 1: Write reconnect tests**

```swift
func testBackoffCapsAtThirtySeconds() {
    var policy = ReconnectPolicy()
    XCTAssertEqual((0..<7).map { _ in policy.nextDelay() },
                   [.seconds(1), .seconds(2), .seconds(5), .seconds(10), .seconds(30), .seconds(30), .seconds(30)])
}
```

Run `make macos-test`; expect failure.

- [ ] **Step 2: Implement clock and policy**

```swift
protocol SessionClock: Sendable { func sleep(for duration: Duration) async throws }

struct ContinuousSessionClock: SessionClock {
    func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }
}
```

`TestSessionClock` stores requested sleeps and resumes each only through `advanceNextSleep()`.

- [ ] **Step 3: Implement fake transport exactly**

`@MainActor final class FakeHeadphoneTransport` conforms to `HeadphoneTransport`, owns a nonisolated buffered stream, records calls/segments, and provides:

```swift
func emit(_ event: TransportEvent)
func queueWriteFailure(_ error: HeadphoneTransportError)
func clearRecordedCalls()
var writtenSegments: [[UInt8]] { get }
var calls: [RecordedTransportCall] { get }
```

`HeadphoneTestFixtures` defines one stable candidate, supported/unsupported product packets, capabilities, mode list/config/current, battery, standby, and spatial packets. No session type is referenced yet, so this task remains buildable.

- [ ] **Step 4: Verify and commit**

```bash
make macos-test
git add apps/macos/UltraController/App/Session apps/macos/UltraController/Tests/Fakes apps/macos/UltraController/Tests/Session/ReconnectPolicyTests.swift
git commit -m "test: add deterministic transport and clock"
```

### Task 4: Implement the authoritative session and connected-session test fixture

**Files:**
- Create: `apps/macos/UltraController/App/Session/ConnectionPhase.swift`
- Create: `apps/macos/UltraController/App/Session/HeadphoneCommand.swift`
- Create: `apps/macos/UltraController/App/Session/HeadphoneSnapshot.swift`
- Create: `apps/macos/UltraController/App/Session/HeadphoneSessionError.swift`
- Create: `apps/macos/UltraController/App/Session/SupportedDeviceProfile.swift`
- Create: `apps/macos/UltraController/App/Session/HeadphoneSession.swift`
- Create: `apps/macos/UltraController/App/Resources/QCUltraGen1Profile.json`
- Create: `apps/macos/UltraController/Tests/Fakes/SessionFixture.swift`
- Test: `apps/macos/UltraController/Tests/Session/HeadphoneSessionStateTests.swift`
- Test: `apps/macos/UltraController/Tests/Session/InitialSynchronizationTests.swift`

**Interfaces:**
- Produces: snapshots/current snapshot, start/select/reconnect/forget/sleep/wake, supported-device validation, and reusable connected fixture.

- [ ] **Step 1: Write actor-isolated state tests**

```swift
@MainActor
func testUnsupportedDeviceNeverEnablesWrites() async throws {
    let fixture = SessionFixture()
    await fixture.session.start(savedID: nil)
    fixture.transport.emit(.availabilityChanged(.poweredOn))
    fixture.transport.emit(.discovered(.qcUltraCandidate))
    await fixture.session.select(.qcUltraCandidate.id)
    fixture.transport.emit(.connected(.qcUltraCandidate.id))
    fixture.transport.emit(.channelReady(.qcUltraCandidate.id, .secure))
    await fixture.waitForPacket(functionBlock: .settings, function: ProductMessages.nameFunction)
    fixture.respond(ProductMessages.statusName("Bose Other Product"))
    let snapshot = await fixture.session.currentSnapshot()
    XCTAssertEqual(snapshot.phase, .failed(.unsupportedDevice))
    XCTAssertFalse(snapshot.writesEnabled)
}
```

Also test legal phase progression and ignored old-generation events. Run `make macos-test`; expect failure.

- [ ] **Step 2: Define state and snapshot**

```swift
enum ConnectionPhase: Equatable, Sendable {
    case unconfigured, permissionRequired, bluetoothUnavailable, scanning
    case connecting(name: String?), loadingState, connected
    case reconnecting(attempt: Int), sleeping, unavailable
    case failed(HeadphoneSessionError)
}

enum HeadphoneCommand: Equatable, Sendable {
    case setCurrentMode(UInt8), setStandby(UInt8)
    case setSpatialAudio(SpatialAudioMode), powerOff, refresh
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

Every publication increments revision and emits a complete snapshot.

- [ ] **Step 3: Implement exact supported-device profile**

Generate `QCUltraGen1Profile.json` from Plan 1 evidence. Include the exact observed product string and required parsed capability/essential responses. Name alone never enables writes.

- [ ] **Step 4: Implement event loop, generation, and initial sync**

Create the transport event-consumer once. Increment generation on each new connection/disconnect/forget. Initial serial order: identity → capabilities → all valid mode IDs → current mode → battery → each mode config → standby → spatial. Enter connected only after identity, capabilities, mode IDs/current, and battery; unsupported optional reads may remain nil.

- [ ] **Step 5: Implement `SessionFixture` without placeholder bodies**

`@MainActor final class SessionFixture` contains real implementations for:

| Method | Exact behavior |
|---|---|
| `init()` | Creates fake transport, test clock, session, and packet decoder for recorded segments. |
| `static connected() async throws` | Starts session, emits powered-on/candidate/connect/channel-ready, waits for each initial request, responds with supported deterministic fixture packets, and asserts final connected state before returning. |
| `waitForPacket(functionBlock:function:) async` | Polls recorded complete reassembled packets using `Task.yield()` with a bounded iteration count; fails the test if absent. |
| `respond(_:)` | Encodes/segments the packet and emits each segment as a notification for the selected fixture ID. |
| `respondCurrentMode`, `respondStandby`, `respondSpatial` | Build and emit typed status packets. |
| `latestSnapshot()` | Calls `session.currentSnapshot()`. |
| `scriptWriteFailure(_:)` | Queues one fake transport write failure. |

No method is left with a stub, `fatalError`, or comment-only body.

- [ ] **Step 6: Verify and commit**

```bash
make macos-test
git add apps/macos/UltraController/App/Session apps/macos/UltraController/App/Resources/QCUltraGen1Profile.json apps/macos/UltraController/Tests/Fakes/SessionFixture.swift apps/macos/UltraController/Tests/Session
git commit -m "feat: add authoritative headphone session"
```

### Task 5: Implement single-flight requests and confirmed essential commands

**Files:**
- Create: `apps/macos/UltraController/App/Session/BMAPRequestKey.swift`
- Create: `apps/macos/UltraController/App/Session/PendingRequest.swift`
- Create: `apps/macos/UltraController/App/Session/CommandExecutor.swift`
- Modify: `apps/macos/UltraController/App/Session/HeadphoneSession.swift`
- Test: `apps/macos/UltraController/Tests/Session/CommandExecutorTests.swift`
- Test: `apps/macos/UltraController/Tests/Session/EssentialCommandTests.swift`

**Interfaces:**
- Produces: `refresh`, `setCurrentMode`, `setStandby`, `setSpatialAudio`, and `powerOff` with explicit outcomes.

- [ ] **Step 1: Write valid actor-isolated confirmation tests**

```swift
@MainActor
func testSetModeKeepsOldConfirmedValueUntilReadBack() async throws {
    let fixture = try await SessionFixture.connected()
    let task = Task { try await fixture.session.setCurrentMode(2) }
    await fixture.waitForPacket(functionBlock: .audioModes, function: AudioModeMessages.currentFunction)
    XCTAssertEqual(await fixture.session.currentSnapshot().currentModeID, 1)
    fixture.respondCurrentMode(1)
    await XCTAssertThrowsErrorAsync(try await task.value) { error in
        XCTAssertEqual(error as? HeadphoneSessionError, .verificationMismatch)
    }
}

@MainActor
func testPowerOffRequiresExpectedDisconnect() async throws {
    let fixture = try await SessionFixture.connected()
    let task = Task { try await fixture.session.powerOff() }
    await fixture.waitForPacket(functionBlock: .control, function: PowerMessages.powerFunction)
    fixture.transport.emit(.disconnected(.qcUltraCandidate.id, nil))
    try await task.value
    XCTAssertEqual(await fixture.session.currentSnapshot().phase, .unavailable)
}
```

Run `make macos-test`; expect failure.

- [ ] **Step 2: Define request correlation**

```swift
struct BMAPRequestKey: Hashable, Sendable {
    let functionBlock: BMAPFunctionBlock
    let function: UInt8
}
```

`PendingRequest` stores key, generation, expected response operators, timeout, and continuation. `CommandExecutor` permits one active request/mutation and routes parsed responses/errors by key and current generation.

- [ ] **Step 3: Implement ordinary mutations**

Validate connection/identity/capability; encode/segment/write; observe immediate error/result; issue matching GET; compare; update snapshot only from confirmed data. On mismatch throw `.verificationMismatch`.

- [ ] **Step 4: Implement ambiguous timeout**

Never replay mutation. Read back once: requested value means success; different means mismatch; second timeout means `.outcomeUnknown` and stale snapshot.

- [ ] **Step 5: Implement Power Off**

Write, fail on immediate error, then wait five seconds for current-generation disconnect. On expected disconnect suppress auto-reconnect until manual reconnect or next process launch. No disconnect means outcome unknown.

- [ ] **Step 6: Coalesce safely**

Drop queued duplicate refresh, replace only not-yet-started mode selection with latest, never cancel already-written mutation, publish pending command.

- [ ] **Step 7: Verify and commit**

```bash
make macos-test
git add apps/macos/UltraController/App/Session apps/macos/UltraController/Tests/Session
git commit -m "feat: verify essential headphone commands"
```

### Task 6: Implement reconnect, stale state, sleep/wake, and forget

**Files:**
- Create: `apps/macos/UltraController/App/Lifecycle/SleepWakeMonitor.swift`
- Modify: `apps/macos/UltraController/App/Session/HeadphoneSession.swift`
- Test: `apps/macos/UltraController/Tests/Session/ReconnectSessionTests.swift`
- Test: `apps/macos/UltraController/Tests/Session/SleepWakeSessionTests.swift`
- Test: `apps/macos/UltraController/Tests/Session/ForgetDeviceTests.swift`

**Interfaces:**
- Produces: deterministic auto/manual reconnect and lifecycle cleanup.

- [ ] **Step 1: Write tests for exact delays and one attempt at a time**

Assert `1,2,5,10,30`, reset after confirmed connection, pause during sleep, manual reconnect bypasses wait, and forgetting cancels all work/clears selection.

- [ ] **Step 2: Implement reconnect**

On unexpected disconnect mark stale, cancel old generation, publish attempt, sleep through injected clock, retrieve saved ID before scanning, and own exactly one `reconnectTask`.

- [ ] **Step 3: Implement sleep/wake and forget**

Observe `NSWorkspace.willSleepNotification`/`didWakeNotification`. Sleep stops scans/timers without forgetting; wake begins clean reconnect/full sync. Forget stops scan, disconnects, cancels work, increments generation, clears state, publishes unconfigured, and invokes a persistence callback.

- [ ] **Step 4: Verify and commit**

```bash
make macos-test
git add apps/macos/UltraController/App/Lifecycle apps/macos/UltraController/App/Session apps/macos/UltraController/Tests/Session
git commit -m "feat: add reliable reconnect and lifecycle recovery"
```

### Task 7: Add one observable application model and verify production code physically

**Files:**
- Create: `apps/macos/UltraController/App/Application/PendingAction.swift`
- Create: `apps/macos/UltraController/App/Application/PresentationError.swift`
- Create: `apps/macos/UltraController/App/Application/ApplicationModel.swift`
- Create: `apps/macos/UltraController/App/Diagnostics/ConnectivityHarnessView.swift`
- Modify: `apps/macos/UltraController/App/Application/UltraControllerApp.swift`
- Test: `apps/macos/UltraController/Tests/Application/ApplicationModelTests.swift`
- Update: `docs/protocol/qc-ultra-baseline-probe.md`

**Interfaces:**
- Produces: one `@MainActor @Observable ApplicationModel`; Plan 3 wraps session behind a protocol without changing behavior.

- [ ] **Step 1: Write a real-session/fake-transport model test**

```swift
@MainActor
func testModelDoesNotOptimisticallyChangeConfirmedMode() async throws {
    let fixture = try await SessionFixture.connected()
    let model = ApplicationModel(session: fixture.session)
    model.selectMode(2)
    await fixture.waitForPacket(functionBlock: .audioModes, function: AudioModeMessages.currentFunction)
    XCTAssertEqual(model.snapshot.currentModeID, 1)
    XCTAssertEqual(model.pendingAction, .setMode(2))
}
```

- [ ] **Step 2: Implement model**

```swift
@MainActor
@Observable
final class ApplicationModel {
    private let session: HeadphoneSession
    private var observationTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?

    private(set) var snapshot: HeadphoneSnapshot
    private(set) var candidates: [DiscoveredHeadphone] = []
    private(set) var pendingAction: PendingAction?
    private(set) var lastError: PresentationError?
}
```

Observe snapshots once, track one user-action task, expose candidate/connect/refresh/mutation/reconnect/forget APIs, and map typed errors to user-facing categories while retaining diagnostics.

- [ ] **Step 3: Build DEBUG connectivity harness**

Display phase/candidates/connect/reconnect/refresh/forget, all essential confirmed values/actions, pending state/result, and sanitized event log. No raw command field.

- [ ] **Step 4: Run production physical checklist**

Cold saved-ID connect, initial sync, modes/restore, standby/restore, spatial/restore, out-of-range return, sleep/wake, Power Off, power on/manual reconnect. Update baseline evidence with exact firmware/read-back.

- [ ] **Step 5: Verify and commit**

```bash
make macos-test-core
make macos-test
make macos-build
git add apps/macos/UltraController/App apps/macos/UltraController/Tests/Application docs/protocol/qc-ultra-baseline-probe.md
git commit -m "test: verify production QC Ultra session"
```

### Task 8: Run the Plan 2 checkpoint

**Files:**
- Verify all Plan 2 files/evidence.

**Interfaces:**
- Produces for Plan 3: production transport/session, confirmed commands, app model, persistence callback, lifecycle recovery.

- [ ] **Step 1: Run complete suite twice**

```bash
cargo test --workspace
make macos-test-core
make macos-test
make macos-test
```

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

- [ ] **Step 3: Verify one Bluetooth owner**

```bash
MATCHES="$(grep -R 'CBCentralManager(' apps/macos/UltraController/App --include='*.swift' || true)"
COUNT="$(printf '%s\n' "$MATCHES" | sed '/^$/d' | wc -l | tr -d ' ')"
test "$COUNT" = "1"
printf '%s\n' "$MATCHES" | grep -q 'CoreBluetoothTransport.swift'
```

- [ ] **Step 4: Verify physical evidence**

```bash
for phrase in 'mode read-back' 'standby read-back' 'spatial audio' 'sleep/wake' 'power off'; do
  grep -qi "$phrase" docs/protocol/qc-ultra-baseline-probe.md || exit 1
done
```

Plan 2 completes only after physical production-session confirmation and fresh automated output.
