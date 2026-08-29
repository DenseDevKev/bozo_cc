# Ultra Controller Foundation and BMAP Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the reproducible native macOS project, port Bozo's BMAP protocol core into tested Swift, establish shared Rust/Swift fixtures, and prove safe read-only communication with the physical QC Ultra.

**Architecture:** The app project is generated reproducibly with XcodeGen but commits the generated `.xcodeproj`; XcodeGen is a development-only tool and is not shipped. `HeadphoneCore` is a local Swift package containing pure protocol types, packet framing, message builders, and parsers. A separate Debug-only sandbox probe validates the service, characteristics, and read-only queries before the production transport/session architecture is built.

**Tech Stack:** Swift 6, Swift Package Manager, XCTest, Xcode 27, XcodeGen, SwiftUI, CoreBluetooth, App Sandbox, Rust/Cargo parity tests, JSON fixtures.

**Spec:** `docs/superpowers/specs/2026-08-29-qc-ultra-macos-controller-design.md`

## Global Constraints

- Work under `apps/macos/UltraController` and leave the existing Rust TUI/daemon behavior unchanged.
- Target macOS 27.0 and `arm64`; do not produce an Intel slice.
- Do not add a runtime dependency on Rust, XcodeGen, Homebrew, Node, or a web runtime.
- Enable App Sandbox and Bluetooth entitlement for every executable that touches CoreBluetooth.
- Use the canonical BMAP service `0000FEBE-0000-1000-8000-00805F9B34FB` and the secure/unsecure characteristic UUIDs from `docs/BMAP.md`.
- The probe performs read-only queries and ordinary safe mode switching only after read-only identity succeeds; it never invokes firmware-update functions or arbitrary packet injection.
- Preserve raw/opaque bytes when a parser does not understand a field.
- Commit after each independently passing task.

---

## File Map

| Path | Responsibility |
|---|---|
| `apps/macos/UltraController/project.yml` | Reproducible Xcode target, package, signing, and build-setting definition. |
| `apps/macos/UltraController/UltraController.xcodeproj` | Generated project committed for Xcode-native use. |
| `apps/macos/UltraController/Brewfile` | Development-only XcodeGen dependency. |
| `apps/macos/UltraController/Config/*.xcconfig` | Shared Debug/Release/macOS 27/arm64 build settings. |
| `apps/macos/UltraController/Config/App.entitlements` | Sandbox, Bluetooth, and App Group entitlements for the main app. |
| `apps/macos/UltraController/Packages/HeadphoneCore` | Pure Swift BMAP package. |
| `fixtures/bmap/*.json` | Language-neutral protocol fixtures consumed by Swift and Rust tests. |
| `crates/bozo-proto/tests/fixture_parity.rs` | Confirms existing Rust behavior matches the shared fixtures. |
| `apps/macos/UltraController/ProtocolProbe` | Debug-only SwiftUI/CoreBluetooth physical-device probe. |
| `docs/protocol/qc-ultra-baseline-probe.md` | Recorded physical-device evidence and firmware context. |

### Task 1: Scaffold the reproducible macOS project and test commands

**Files:**
- Modify: `.gitignore`
- Modify: `Makefile`
- Create: `apps/macos/UltraController/Brewfile`
- Create: `apps/macos/UltraController/project.yml`
- Create: `apps/macos/UltraController/Config/Shared.xcconfig`
- Create: `apps/macos/UltraController/Config/Debug.xcconfig`
- Create: `apps/macos/UltraController/Config/Release.xcconfig`
- Create: `apps/macos/UltraController/Config/App.entitlements`
- Create: `apps/macos/UltraController/Config/Probe.entitlements`
- Create: `apps/macos/UltraController/Config/Info.plist`
- Create: `apps/macos/UltraController/Config/PrivacyInfo.xcprivacy`
- Create: `apps/macos/UltraController/App/Application/UltraControllerApp.swift`
- Create: `apps/macos/UltraController/App/Overview/PlaceholderOverviewView.swift`
- Create: `apps/macos/UltraController/Tests/UltraControllerSmokeTests.swift`
- Create: `apps/macos/UltraController/Scripts/verify-project.sh`
- Generate: `apps/macos/UltraController/UltraController.xcodeproj`

**Interfaces:**
- Consumes: Xcode 27 command-line tools and XcodeGen.
- Produces: schemes `UltraController`, `UltraControllerProtocolProbe`, `UltraControllerTests`, and the Make targets `macos-generate`, `macos-build`, `macos-test`, `macos-probe`.

- [ ] **Step 1: Write the project-verification script before creating the project**

Create `apps/macos/UltraController/Scripts/verify-project.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
APP_DIR="$ROOT/apps/macos/UltraController"
PROJECT="$APP_DIR/UltraController.xcodeproj"

[[ -d "$PROJECT" ]] || { echo "missing $PROJECT" >&2; exit 1; }
[[ -f "$APP_DIR/Config/App.entitlements" ]] || { echo "missing App.entitlements" >&2; exit 1; }
[[ -f "$APP_DIR/Config/PrivacyInfo.xcprivacy" ]] || { echo "missing PrivacyInfo.xcprivacy" >&2; exit 1; }

xcodebuild -project "$PROJECT" -list | grep -q "UltraController"
xcodebuild -project "$PROJECT" -list | grep -q "UltraControllerProtocolProbe"
```

Make it executable:

```bash
chmod +x apps/macos/UltraController/Scripts/verify-project.sh
```

- [ ] **Step 2: Run the verifier and confirm the expected failure**

Run:

```bash
apps/macos/UltraController/Scripts/verify-project.sh
```

Expected: FAIL with `missing .../UltraController.xcodeproj`.

- [ ] **Step 3: Add Xcode and Swift build artifacts to `.gitignore`**

Append exactly:

```gitignore

# macOS / Xcode
DerivedData/
*.xcuserstate
xcuserdata/
.swiftpm/
.build/
apps/macos/UltraController/build/
apps/macos/UltraController/.xcodegen-cache/
```

Do not ignore `UltraController.xcodeproj` or shared schemes.

- [ ] **Step 4: Add the development-only XcodeGen dependency**

Create `apps/macos/UltraController/Brewfile`:

```ruby
brew "xcodegen"
```

Run:

```bash
brew bundle --file apps/macos/UltraController/Brewfile
xcodegen --version
```

Expected: `xcodegen --version` exits 0.

- [ ] **Step 5: Create build settings and entitlements**

Create `Config/Shared.xcconfig`:

```xcconfig
MACOSX_DEPLOYMENT_TARGET = 27.0
ARCHS = arm64
ONLY_ACTIVE_ARCH = YES
SWIFT_VERSION = 6.0
SWIFT_STRICT_CONCURRENCY = complete
ENABLE_USER_SCRIPT_SANDBOXING = YES
CODE_SIGN_STYLE = Automatic
DEVELOPMENT_TEAM =
PRODUCT_BUNDLE_IDENTIFIER = dev.densedevkev.ultracontroller
APP_GROUP_IDENTIFIER = group.dev.densedevkev.ultracontroller
```

Create `Config/Debug.xcconfig`:

```xcconfig
#include "Shared.xcconfig"
SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG
ENABLE_TESTABILITY = YES
DEBUG_INFORMATION_FORMAT = dwarf
```

Create `Config/Release.xcconfig`:

```xcconfig
#include "Shared.xcconfig"
SWIFT_COMPILATION_MODE = wholemodule
SWIFT_OPTIMIZATION_LEVEL = -O
DEBUG_INFORMATION_FORMAT = dwarf-with-dsym
DEAD_CODE_STRIPPING = YES
```

Create `Config/App.entitlements` and `Config/Probe.entitlements` with the same initial content:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.device.bluetooth</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.dev.densedevkev.ultracontroller</string>
    </array>
</dict>
</plist>
```

Create `Config/Info.plist` with `NSBluetoothAlwaysUsageDescription` set to `Ultra Controller uses Bluetooth to read and change settings on your selected QC Ultra headphones.`

Create `Config/PrivacyInfo.xcprivacy` with empty collected-data and tracking arrays:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key><false/>
    <key>NSPrivacyTrackingDomains</key><array/>
    <key>NSPrivacyCollectedDataTypes</key><array/>
    <key>NSPrivacyAccessedAPITypes</key><array/>
</dict>
</plist>
```

- [ ] **Step 6: Create the minimal app and smoke test**

Create `App/Application/UltraControllerApp.swift`:

```swift
import SwiftUI

@main
struct UltraControllerApp: App {
    var body: some Scene {
        WindowGroup {
            PlaceholderOverviewView()
                .frame(minWidth: 680, minHeight: 460)
        }
    }
}
```

Create `App/Overview/PlaceholderOverviewView.swift`:

```swift
import SwiftUI

struct PlaceholderOverviewView: View {
    var body: some View {
        ContentUnavailableView(
            "Ultra Controller",
            systemImage: "headphones",
            description: Text("Protocol foundation is not connected yet.")
        )
        .accessibilityIdentifier("overview.placeholder")
    }
}
```

Create `Tests/UltraControllerSmokeTests.swift`:

```swift
import XCTest
@testable import UltraController

final class UltraControllerSmokeTests: XCTestCase {
    func testTestBundleLoads() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 7: Define and generate the Xcode project**

Create `project.yml` with these targets and settings:

```yaml
name: UltraController
options:
  createIntermediateGroups: true
  deploymentTarget:
    macOS: "27.0"
configs:
  Debug: debug
  Release: release
packages:
  HeadphoneCore:
    path: Packages/HeadphoneCore
settings:
  base:
    ARCHS: arm64
    SWIFT_VERSION: 6.0
    SWIFT_STRICT_CONCURRENCY: complete
    GENERATE_INFOPLIST_FILE: false
targets:
  UltraController:
    type: application
    platform: macOS
    sources:
      - App
    resources:
      - path: Config/PrivacyInfo.xcprivacy
    configFiles:
      Debug: Config/Debug.xcconfig
      Release: Config/Release.xcconfig
    info:
      path: Config/Info.plist
    entitlements:
      path: Config/App.entitlements
    dependencies:
      - package: HeadphoneCore
    settings:
      base:
        PRODUCT_NAME: Ultra Controller
        PRODUCT_BUNDLE_IDENTIFIER: dev.densedevkev.ultracontroller
  UltraControllerProtocolProbe:
    type: application
    platform: macOS
    sources:
      - ProtocolProbe
    configFiles:
      Debug: Config/Debug.xcconfig
      Release: Config/Release.xcconfig
    info:
      path: Config/Info.plist
    entitlements:
      path: Config/Probe.entitlements
    dependencies:
      - package: HeadphoneCore
    settings:
      base:
        PRODUCT_NAME: Ultra Controller Protocol Probe
        PRODUCT_BUNDLE_IDENTIFIER: dev.densedevkev.ultracontroller.probe
  UltraControllerTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - Tests
    dependencies:
      - target: UltraController
schemes:
  UltraController:
    build:
      targets:
        UltraController: all
        UltraControllerTests: [test]
    test:
      targets:
        - UltraControllerTests
  UltraControllerProtocolProbe:
    build:
      targets:
        UltraControllerProtocolProbe: all
```

Before generation, create an empty compilable probe entry point:

```swift
// ProtocolProbe/ProtocolProbeApp.swift
import SwiftUI

@main
struct ProtocolProbeApp: App {
    var body: some Scene {
        WindowGroup { Text("Protocol probe not implemented") }
    }
}
```

Run:

```bash
cd apps/macos/UltraController
xcodegen generate --spec project.yml
cd ../../..
```

- [ ] **Step 8: Add Make targets**

Append to the root `Makefile`:

```make
MACOS_DIR = apps/macos/UltraController
MACOS_PROJECT = $(MACOS_DIR)/UltraController.xcodeproj
MACOS_DEST = platform=macOS,arch=arm64

.PHONY: macos-generate macos-build macos-test macos-test-core macos-probe

macos-generate:
	cd $(MACOS_DIR) && xcodegen generate --spec project.yml

macos-test-core:
	cd $(MACOS_DIR)/Packages/HeadphoneCore && swift test

macos-build: macos-generate
	xcodebuild -project $(MACOS_PROJECT) -scheme UltraController -destination '$(MACOS_DEST)' CODE_SIGNING_ALLOWED=NO build

macos-test: macos-generate
	xcodebuild -project $(MACOS_PROJECT) -scheme UltraController -destination '$(MACOS_DEST)' CODE_SIGNING_ALLOWED=NO test

macos-probe: macos-generate
	xcodebuild -project $(MACOS_PROJECT) -scheme UltraControllerProtocolProbe -destination '$(MACOS_DEST)' build
	open "$$(xcodebuild -project $(MACOS_PROJECT) -scheme UltraControllerProtocolProbe -showBuildSettings | awk '/ TARGET_BUILD_DIR /{dir=$$3} / FULL_PRODUCT_NAME /{name=$$3} END{print dir "/" name}')"
```

- [ ] **Step 9: Run the scaffold verification**

Run:

```bash
apps/macos/UltraController/Scripts/verify-project.sh
make macos-build
make macos-test
```

Expected: all commands exit 0; the unit test reports one passing test.

- [ ] **Step 10: Commit the scaffold**

```bash
git add .gitignore Makefile apps/macos/UltraController
git commit -m "build: scaffold native Ultra Controller project"
```

### Task 2: Implement the BMAP packet codec with Rust parity

**Files:**
- Create: `apps/macos/UltraController/Packages/HeadphoneCore/Package.swift`
- Create: `apps/macos/UltraController/Packages/HeadphoneCore/Sources/HeadphoneCore/BMAP/BMAPOperator.swift`
- Create: `apps/macos/UltraController/Packages/HeadphoneCore/Sources/HeadphoneCore/BMAP/BMAPFunctionBlock.swift`
- Create: `apps/macos/UltraController/Packages/HeadphoneCore/Sources/HeadphoneCore/BMAP/BMAPPacket.swift`
- Create: `apps/macos/UltraController/Packages/HeadphoneCore/Sources/HeadphoneCore/BMAP/BMAPCodecError.swift`
- Create: `apps/macos/UltraController/Packages/HeadphoneCore/Tests/HeadphoneCoreTests/BMAPPacketTests.swift`

**Interfaces:**
- Consumes: raw BMAP bytes documented in `crates/bozo-proto/src/bmap/packet.rs`.
- Produces: `BMAPOperator`, `BMAPFunctionBlock`, `BMAPPacket`, `BMAPPacket.decode(_:)`, `BMAPPacket.decodeMany(_:)`, and `BMAPPacket.encoded()`.

- [ ] **Step 1: Create the Swift package manifest**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HeadphoneCore",
    platforms: [.macOS("27.0")],
    products: [.library(name: "HeadphoneCore", targets: ["HeadphoneCore"])],
    targets: [
        .target(name: "HeadphoneCore"),
        .testTarget(name: "HeadphoneCoreTests", dependencies: ["HeadphoneCore"]),
    ]
)
```

- [ ] **Step 2: Write failing codec tests using Bozo's exact bytes**

Create `BMAPPacketTests.swift`:

```swift
import XCTest
@testable import HeadphoneCore

final class BMAPPacketTests: XCTestCase {
    func testBatteryQueryEncodingMatchesRust() throws {
        let packet = BMAPPacket(
            functionBlock: .status,
            function: 0x02,
            operator: .get,
            payload: []
        )
        XCTAssertEqual(try packet.encoded(), [0x02, 0x02, 0x01, 0x00])
    }

    func testPowerOffEncodingMatchesRust() throws {
        let packet = BMAPPacket(
            functionBlock: .control,
            function: 0x04,
            operator: .start,
            payload: [0x00]
        )
        XCTAssertEqual(try packet.encoded(), [0x07, 0x04, 0x05, 0x01, 0x00])
    }

    func testDecodeRejectsTruncatedPayload() {
        XCTAssertThrowsError(try BMAPPacket.decode([0x01, 0x05, 0x02, 0x05, 0xAA, 0xBB]))
    }

    func testDecodeManyParsesConcatenatedPackets() throws {
        let packets = try BMAPPacket.decodeMany([
            0x02, 0x02, 0x01, 0x00,
            0x01, 0x05, 0x01, 0x00,
        ])
        XCTAssertEqual(packets.map(\.functionBlock), [.status, .settings])
    }
}
```

- [ ] **Step 3: Run the package tests and verify failure**

```bash
cd apps/macos/UltraController/Packages/HeadphoneCore
swift test --filter BMAPPacketTests
```

Expected: FAIL because `BMAPPacket` is undefined.

- [ ] **Step 4: Implement typed enums and errors**

Define all function blocks currently represented by Bozo, including `.audioModes = 0x1F`, and operators `.set` through `.processing` with raw values `0...7`.

```swift
public enum BMAPOperator: UInt8, Sendable, Codable, CaseIterable {
    case set = 0, get = 1, setGet = 2, status = 3
    case error = 4, start = 5, result = 6, processing = 7

    public var isResponse: Bool {
        switch self {
        case .status, .error, .result, .processing: true
        default: false
        }
    }
}

public enum BMAPCodecError: Error, Equatable, Sendable {
    case packetTooShort(actual: Int)
    case unknownFunctionBlock(UInt8)
    case unknownOperator(UInt8)
    case payloadTooLong(Int)
    case payloadLengthMismatch(expected: Int, actual: Int)
}
```

- [ ] **Step 5: Implement `BMAPPacket`**

```swift
public struct BMAPPacket: Equatable, Sendable, Codable {
    public let functionBlock: BMAPFunctionBlock
    public let function: UInt8
    public let deviceID: UInt8
    public let port: UInt8
    public let `operator`: BMAPOperator
    public let payload: [UInt8]

    public init(
        functionBlock: BMAPFunctionBlock,
        function: UInt8,
        deviceID: UInt8 = 0,
        port: UInt8 = 0,
        operator: BMAPOperator,
        payload: [UInt8]
    ) {
        self.functionBlock = functionBlock
        self.function = function
        self.deviceID = deviceID
        self.port = port
        self.operator = `operator`
        self.payload = payload
    }

    public func encoded() throws -> [UInt8] {
        guard payload.count <= UInt8.max else { throw BMAPCodecError.payloadTooLong(payload.count) }
        return [
            functionBlock.rawValue,
            function,
            (deviceID << 6) | (port << 4) | (`operator`.rawValue & 0x0F),
            UInt8(payload.count),
        ] + payload
    }
}
```

Implement `decode(_:)` and `decodeMany(_:)` with the same length checks as the Rust implementation; `decodeMany` must throw on trailing or truncated data rather than silently discard it.

- [ ] **Step 6: Run codec tests**

```bash
swift test --filter BMAPPacketTests
```

Expected: all four tests pass.

- [ ] **Step 7: Commit the codec**

```bash
git add apps/macos/UltraController/Packages/HeadphoneCore
git commit -m "feat: add Swift BMAP packet codec"
```

### Task 3: Implement BLE segmentation and reassembly

**Files:**
- Create: `apps/macos/UltraController/Packages/HeadphoneCore/Sources/HeadphoneCore/BMAP/BLESegmenter.swift`
- Create: `apps/macos/UltraController/Packages/HeadphoneCore/Sources/HeadphoneCore/BMAP/BLEReassembler.swift`
- Create: `apps/macos/UltraController/Packages/HeadphoneCore/Tests/HeadphoneCoreTests/BLEFramingTests.swift`

**Interfaces:**
- Consumes: encoded BMAP bytes.
- Produces: `BLESegmenter.segment(_:) -> [[UInt8]]` and mutable `BLEReassembler.feed(_:) -> Result<[UInt8]?, BLEFramingError>`.

- [ ] **Step 1: Write framing tests**

```swift
import XCTest
@testable import HeadphoneCore

final class BLEFramingTests: XCTestCase {
    func testSingleSegmentUsesZeroHeader() throws {
        let data: [UInt8] = [0x01, 0x05, 0x02, 0x02, 0x05, 0x01]
        XCTAssertEqual(try BLESegmenter.segment(data), [[0x00] + data])
    }

    func testTwentyFiveBytesUseTwoSegments() throws {
        let segments = try BLESegmenter.segment([UInt8](repeating: 0xBB, count: 25))
        XCTAssertEqual(segments.map(\.first), [0x10, 0x11])
        XCTAssertEqual(segments.map(\.count), [20, 7])
    }

    func testOutOfOrderSegmentsReassemble() throws {
        let data = [UInt8](0..<30)
        let segments = try BLESegmenter.segment(data)
        var reassembler = BLEReassembler()
        XCTAssertNil(try reassembler.feed(segments[1]).get())
        XCTAssertEqual(try reassembler.feed(segments[0]).get(), data)
    }

    func testConflictingDuplicateResetsStream() throws {
        var reassembler = BLEReassembler()
        _ = try reassembler.feed([0x10, 0xAA]).get()
        XCTAssertThrowsError(try reassembler.feed([0x10, 0xBB]).get())
    }
}
```

- [ ] **Step 2: Run and verify failure**

```bash
swift test --filter BLEFramingTests
```

Expected: FAIL because framing types are undefined.

- [ ] **Step 3: Implement segmentation with the 4-bit segment limit**

```swift
public enum BLESegmenter {
    public static let maximumSegmentLength = 20
    public static let dataBytesPerSegment = 19

    public static func segment(_ data: [UInt8]) throws -> [[UInt8]] {
        let chunks = data.isEmpty ? [[]] : stride(from: 0, to: data.count, by: dataBytesPerSegment)
            .map { Array(data[$0..<min($0 + dataBytesPerSegment, data.count)]) }
        guard chunks.count <= 16 else { throw BLEFramingError.tooManySegments(chunks.count) }
        let maximumIndex = UInt8(chunks.count - 1)
        return chunks.enumerated().map { index, chunk in
            [(maximumIndex << 4) | UInt8(index)] + chunk
        }
    }
}
```

- [ ] **Step 4: Implement reassembly with duplicate and consistency checks**

`BLEReassembler` stores `[Int: [UInt8]]`, one expected segment count, and resets after a completed frame or any error. An exact duplicate is idempotent; a duplicate index with different bytes returns `.conflictingDuplicate(index:)` and resets.

- [ ] **Step 5: Run framing and full package tests**

```bash
swift test --filter BLEFramingTests
swift test
```

Expected: all tests pass.

- [ ] **Step 6: Commit framing**

```bash
git add apps/macos/UltraController/Packages/HeadphoneCore
git commit -m "feat: add BMAP BLE framing"
```

### Task 4: Add typed headphone models and essential BMAP messages

**Files:**
- Create: `.../Sources/HeadphoneCore/Models/BatteryComponent.swift`
- Create: `.../Sources/HeadphoneCore/Models/HeadphoneIdentity.swift`
- Create: `.../Sources/HeadphoneCore/Models/AudioModeCapabilities.swift`
- Create: `.../Sources/HeadphoneCore/Models/AudioMode.swift`
- Create: `.../Sources/HeadphoneCore/Models/SpatialAudioMode.swift`
- Create: `.../Sources/HeadphoneCore/Protocol/ProductMessages.swift`
- Create: `.../Sources/HeadphoneCore/Protocol/BatteryMessages.swift`
- Create: `.../Sources/HeadphoneCore/Protocol/StandbyMessages.swift`
- Create: `.../Sources/HeadphoneCore/Protocol/PowerMessages.swift`
- Create: `.../Sources/HeadphoneCore/Protocol/AudioModeMessages.swift`
- Create: `.../Sources/HeadphoneCore/Protocol/SpatialAudioMessages.swift`
- Create: `.../Sources/HeadphoneCore/Protocol/BMAPResponseError.swift`
- Test: matching files under `Tests/HeadphoneCoreTests/`

**Interfaces:**
- Consumes: `BMAPPacket`.
- Produces: pure request builders and throwing parsers for product name, battery, standby, power, AudioModes capabilities/current/list/config, and spatial audio function `AudioManagement/0x0F`.

- [ ] **Step 1: Write request-builder tests with exact bytes**

```swift
func testEssentialRequestBytes() throws {
    XCTAssertEqual(try BatteryMessages.query().encoded(), [0x02, 0x02, 0x01, 0x00])
    XCTAssertEqual(try StandbyMessages.set(minutes: 30).encoded(), [0x01, 0x04, 0x02, 0x01, 0x1E])
    XCTAssertEqual(try AudioModeMessages.queryCapabilities().encoded(), [0x1F, 0x02, 0x01, 0x00])
    XCTAssertEqual(try AudioModeMessages.queryCurrent().encoded(), [0x1F, 0x03, 0x01, 0x00])
    XCTAssertEqual(try AudioModeMessages.queryConfiguration(index: 2).encoded(), [0x1F, 0x06, 0x01, 0x01, 0x02])
    XCTAssertEqual(try SpatialAudioMessages.query().encoded(), [0x05, 0x0F, 0x01, 0x00])
    XCTAssertEqual(try PowerMessages.powerOff().encoded(), [0x07, 0x04, 0x05, 0x01, 0x00])
}
```

- [ ] **Step 2: Write parser tests**

Cover these exact cases:

```swift
func testBatteryParser() throws {
    let packet = BMAPPacket(functionBlock: .status, function: 0x02, operator: .status,
                            payload: [85, 0x01, 0x2C, 0])
    XCTAssertEqual(try BatteryMessages.parse(packet), [
        BatteryComponent(id: 0, percentage: 85, remainingMinutes: 300)
    ])
}

func testAudioModeCapabilitiesParser() throws {
    let packet = BMAPPacket(functionBlock: .audioModes, function: 0x02, operator: .status,
                            payload: [2, 3, 0, 0, 0, 0b0011_1111, 1])
    let value = try AudioModeMessages.parseCapabilities(packet)
    XCTAssertEqual(value.boseModeCount, 2)
    XCTAssertEqual(value.userModeCount, 3)
    XCTAssertTrue(value.supportsSpatialAudio)
    XCTAssertTrue(value.supportsANCToggle)
}

func testModeConfigPreservesOpaqueBytes() throws {
    var payload = [UInt8](repeating: 0, count: 48)
    payload[0] = 2
    payload[2] = 12
    payload[3] = 1
    payload[5] = 1
    Array("Music".utf8).enumerated().forEach { payload[6 + $0.offset] = $0.element }
    payload[38] = 0xA1
    payload[39] = 0xB2
    payload[40] = 0xC3
    payload[41] = 0b0001_1111
    payload[42] = 7
    payload[43] = 1
    payload[44] = 2
    payload[46] = 1
    payload[47] = 1
    let packet = BMAPPacket(functionBlock: .audioModes, function: 0x06, operator: .status,
                            payload: payload)
    let mode = try AudioModeMessages.parseConfiguration(packet)
    XCTAssertEqual(mode.name, "Music")
    XCTAssertEqual(mode.opaqueReservedBytes, [0xA1, 0xB2, 0xC3, 0x00])
}
```

- [ ] **Step 3: Run and verify parser-test failure**

```bash
swift test --filter EssentialMessageTests
```

Expected: FAIL because message/model types are undefined.

- [ ] **Step 4: Implement the model interfaces**

Use these public shapes:

```swift
public struct BatteryComponent: Sendable, Codable, Equatable, Identifiable {
    public let id: UInt8
    public let percentage: UInt8
    public let remainingMinutes: UInt16?
}

public enum SpatialAudioMode: UInt8, Sendable, Codable, CaseIterable {
    case off = 0
    case still = 1
    case motion = 2
}

public struct AudioModeCapabilities: Sendable, Codable, Equatable {
    public let boseModeCount: UInt8
    public let userModeCount: UInt8
    public let supportsCNC: Bool
    public let supportsAutoCNC: Bool
    public let supportsSpatialAudio: Bool
    public let supportsWindBlock: Bool
    public let supportsFavorites: Bool
    public let supportsANCToggle: Bool
    public let minimumFavoriteCount: UInt8?
}

public struct AudioMode: Sendable, Codable, Equatable, Identifiable {
    public let id: UInt8
    public let promptID: UInt8
    public let isUserConfigurable: Bool
    public let isUserConfigured: Bool
    public let isFavorite: Bool
    public let name: String
    public let mutableFieldMask: UInt8
    public let cncLevel: UInt8?
    public let autoCNCEnabled: Bool?
    public let spatialAudioMode: SpatialAudioMode?
    public let windBlockEnabled: Bool?
    public let ancEnabled: Bool?
    public let opaqueReservedBytes: [UInt8]
    public let rawPayload: [UInt8]
}
```

- [ ] **Step 5: Implement strict response validation**

Every parser must verify function block, function ID, response operator, and minimum length. If `operator == .error`, throw `BMAPResponseError` with the first error byte and optional function-specific byte. Unknown enum values must be retained as raw values or return a typed unsupported-value error; do not silently coerce them to `off` or `false`.

- [ ] **Step 6: Run all package tests**

```bash
swift test
```

Expected: all packet, framing, and message tests pass.

- [ ] **Step 7: Commit essential messages**

```bash
git add apps/macos/UltraController/Packages/HeadphoneCore
git commit -m "feat: add typed QC Ultra BMAP messages"
```

### Task 5: Establish shared JSON fixtures and Rust/Swift parity

**Files:**
- Create: `fixtures/bmap/manifest.json`
- Create: `fixtures/bmap/*.json`
- Create: `apps/macos/UltraController/Packages/HeadphoneCore/Tests/HeadphoneCoreTests/FixtureLoader.swift`
- Create: `apps/macos/UltraController/Packages/HeadphoneCore/Tests/HeadphoneCoreTests/FixtureParityTests.swift`
- Create: `crates/bozo-proto/tests/fixture_parity.rs`
- Modify: `crates/bozo-proto/Cargo.toml` only if `serde_json` is not already available to integration tests.

**Interfaces:**
- Consumes: language-neutral fixture schema.
- Produces: one fixture corpus proven to decode identically in Swift and Rust.

- [ ] **Step 1: Define the fixture schema and seed manifest**

Create `manifest.json`:

```json
{
  "schemaVersion": 1,
  "fixtures": [
    "battery-query.json",
    "battery-primary-status.json",
    "standby-30-set.json",
    "power-off-start.json",
    "audio-mode-capabilities-status.json",
    "audio-mode-config-music-status.json",
    "spatial-audio-query.json"
  ]
}
```

Each fixture file uses:

```json
{
  "name": "battery-query",
  "direction": "request",
  "wireHex": "02020100",
  "expected": {
    "functionBlock": 2,
    "function": 2,
    "operator": 1,
    "payloadHex": ""
  }
}
```

Use the exact bytes asserted by the Swift tests and Bozo's Rust tests. Do not put device identifiers, serial numbers, or unreviewed physical captures in Git.

- [ ] **Step 2: Write the failing Swift fixture test**

`FixtureParityTests` must iterate `manifest.json`, decode `wireHex`, call `BMAPPacket.decode`, and compare every header field and payload against `expected`.

Run:

```bash
cd apps/macos/UltraController/Packages/HeadphoneCore
swift test --filter FixtureParityTests
```

Expected: FAIL until `FixtureLoader` and test-resource declarations are added.

- [ ] **Step 3: Add fixture resources to `Package.swift` and make Swift tests pass**

Add to the test target:

```swift
.testTarget(
    name: "HeadphoneCoreTests",
    dependencies: ["HeadphoneCore"],
    resources: [.copy("../../../../../fixtures/bmap")]
)
```

If SwiftPM rejects a resource outside the package root, create `Tests/HeadphoneCoreTests/Fixtures` as a symlink to `../../../../../../fixtures/bmap` and commit the symlink; do not duplicate the fixture contents.

- [ ] **Step 4: Write the Rust parity integration test**

The Rust test must:

```rust
#[test]
fn shared_fixtures_decode_with_rust_codec() {
    let manifest = load_manifest("../../fixtures/bmap/manifest.json");
    for filename in manifest.fixtures {
        let fixture = load_fixture(&format!("../../fixtures/bmap/{filename}"));
        let bytes = hex::decode(&fixture.wire_hex).unwrap();
        let packet = BmapPacket::from_bytes(&bytes).unwrap();
        assert_eq!(u8::from(packet.function_block), fixture.expected.function_block);
        assert_eq!(packet.function, fixture.expected.function);
        assert_eq!(u8::from(packet.operator), fixture.expected.operator);
        assert_eq!(hex::encode(packet.payload), fixture.expected.payload_hex.to_lowercase());
    }
}
```

Add `hex` and `serde_json` as dev-dependencies only when missing.

- [ ] **Step 5: Run parity verification**

```bash
cargo test -p bozo-proto --test fixture_parity
make macos-test-core
cargo test --workspace
```

Expected: all three commands pass.

- [ ] **Step 6: Commit fixtures and parity tests**

```bash
git add fixtures/bmap crates/bozo-proto apps/macos/UltraController/Packages/HeadphoneCore
git commit -m "test: share BMAP fixtures across Rust and Swift"
```

### Task 6: Build and run the sandboxed read-only protocol probe

**Files:**
- Replace: `apps/macos/UltraController/ProtocolProbe/ProtocolProbeApp.swift`
- Create: `apps/macos/UltraController/ProtocolProbe/ProbeView.swift`
- Create: `apps/macos/UltraController/ProtocolProbe/ProbeViewModel.swift`
- Create: `apps/macos/UltraController/ProtocolProbe/ProbeCentral.swift`
- Create: `apps/macos/UltraController/ProtocolProbe/ProbeEvent.swift`
- Create: `docs/protocol/qc-ultra-baseline-probe.md`

**Interfaces:**
- Consumes: `HeadphoneCore`, CoreBluetooth, physical QC Ultra.
- Produces: evidence for service/characteristic discovery, identity/name, battery, mode capabilities/list/config, current mode, standby, and spatial audio reads.

- [ ] **Step 1: Write the probe state-reducer tests**

Create a testable reducer in `ProbeViewModel` and tests under `Tests/ProtocolProbeReducerTests.swift`:

```swift
func testProbeEventsProduceReadableRows() {
    var model = ProbeViewModel.State()
    model.reduce(.discovered(name: "QC Ultra", id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!))
    model.reduce(.battery([BatteryComponent(id: 0, percentage: 85, remainingMinutes: 300)]))
    XCTAssertEqual(model.rows.map(\.title), ["Discovered", "Battery"])
}
```

Run `make macos-test`; expect failure until reducer and event types exist.

- [ ] **Step 2: Implement `ProbeCentral` as a Debug-only CoreBluetooth delegate**

Use these constants:

```swift
private let serviceUUID = CBUUID(string: "FEBE")
private let secureUUID = CBUUID(string: "C65B8F2F-AEE2-4C89-B758-BC4892D6F2D8")
private let unsecureUUID = CBUUID(string: "D417C028-9818-4354-99D1-2AC09D074591")
```

Discovery order:

1. `retrieveConnectedPeripherals(withServices: [serviceUUID])`.
2. Filtered scan for `serviceUUID` for five seconds.
3. If empty, unfiltered scan for five seconds and show candidates as unverified until ProductInfo/name and capability reads succeed.

The probe prefers a characteristic that supports notify plus write; prefer secure when both qualify. It feeds notification bytes through `BLEReassembler`, then `BMAPPacket.decodeMany`.

- [ ] **Step 3: Send only the safe initial read sequence**

After notifications are enabled, serialize these reads with 100 ms between writes:

```swift
let initialQueries: [BMAPPacket] = [
    ProductMessages.queryName(),
    BatteryMessages.query(),
    AudioModeMessages.queryCapabilities(),
    AudioModeMessages.queryAll(),
    AudioModeMessages.queryCurrent(),
    StandbyMessages.query(),
    SpatialAudioMessages.query(),
]
```

After capabilities/list arrives, query each reported mode index with `AudioModeMessages.queryConfiguration(index:)`. Do not brute-force `0..<10`.

- [ ] **Step 4: Build a simple native probe UI**

`ProbeView` provides:

- Bluetooth state.
- Start/Stop Scan.
- Candidate list with name, UUID suffix, RSSI, and advertised service status.
- Connect/Disconnect.
- Table of parsed responses and raw scrubbed hex.
- `Copy Sanitized Session` button that excludes the full peripheral UUID and any serial response.

Do not add an arbitrary packet-entry field.

- [ ] **Step 5: Run automated tests and build the signed probe**

```bash
make macos-test-core
make macos-test
make macos-probe
```

Expected: tests pass, Xcode signs/opens the probe, and macOS prompts for Bluetooth permission on first use.

- [ ] **Step 6: Execute the physical read-only checklist**

With the QC Ultra powered on and already paired as an audio device:

1. Confirm the probe discovers or retrieves it.
2. Confirm service discovery finds at least one valid BMAP characteristic.
3. Confirm notification subscription succeeds.
4. Record product display name and any stable identity fields available.
5. Record battery and remaining minutes.
6. Record capabilities, all valid mode indices, current mode, and every mode config.
7. Record standby value.
8. Record spatial audio response or the exact BMAP unsupported/error response.
9. Disconnect and reconnect three times; confirm reads remain deterministic.
10. Do not execute advanced writes or firmware functions.

- [ ] **Step 7: Commit the evidence document**

Create `docs/protocol/qc-ultra-baseline-probe.md` with:

```markdown
# QC Ultra Baseline Probe

## Environment
- macOS build:
- Xcode build:
- Mac model:
- Headphone firmware:

## BLE discovery
| Check | Result | Evidence |

## BMAP reads
| Function | Request hex | Response operator | Sanitized response hex | Parsed value |

## Reconnect repetitions
| Attempt | Discovery path | Characteristic | Initial sync result |

## Unsupported or ambiguous behavior
## Fixtures added
## Gate conclusion
```

Populate every field from the run; do not commit unsanitized identifiers.

- [ ] **Step 8: Commit the probe and evidence**

```bash
git add apps/macos/UltraController/ProtocolProbe apps/macos/UltraController/Tests docs/protocol fixtures/bmap
git commit -m "test: validate read-only QC Ultra protocol baseline"
```

### Task 7: Run the Plan 1 checkpoint

**Files:**
- Verify all files created by Tasks 1–6.

**Interfaces:**
- Produces for Plan 2: tested `HeadphoneCore`, shared fixtures, known working BLE discovery/characteristic policy, and physical baseline evidence.

- [ ] **Step 1: Regenerate and verify no project drift**

```bash
make macos-generate
git diff --exit-code -- apps/macos/UltraController/UltraController.xcodeproj
```

Expected: no diff.

- [ ] **Step 2: Run all automated foundation tests**

```bash
cargo test --workspace
make macos-test-core
make macos-test
make macos-build
```

Expected: every command exits 0 with zero test failures.

- [ ] **Step 3: Verify architecture and entitlements**

```bash
APP_PATH="$(find ~/Library/Developer/Xcode/DerivedData -path '*Build/Products/Debug/Ultra Controller.app' -print -quit)"
lipo -archs "$APP_PATH/Contents/MacOS/Ultra Controller"
codesign -d --entitlements :- "$APP_PATH" 2>/dev/null
```

Expected: architecture output is only `arm64`; entitlements include sandbox, Bluetooth, and the configured App Group.

- [ ] **Step 4: Verify the evidence document is complete**

```bash
grep -q "Headphone firmware:" docs/protocol/qc-ultra-baseline-probe.md
grep -q "## Gate conclusion" docs/protocol/qc-ultra-baseline-probe.md
! grep -E "TBD|TODO|<fill|REPLACE_ME" docs/protocol/qc-ultra-baseline-probe.md
```

Expected: all checks exit 0.

- [ ] **Step 5: Commit any verification-only fixes**

```bash
git status --short
# Commit only if verification required an actual tracked fix.
```

Plan 1 is complete only when the debug probe has read the physical headset successfully and the evidence is committed; a passing codec test alone is not the checkpoint.
