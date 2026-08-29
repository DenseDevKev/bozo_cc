# Ultra Controller Foundation and BMAP Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the reproducible native macOS project, port Bozo's BMAP protocol core into tested Swift, establish shared Rust/Swift fixtures, and prove safe read-only communication with the physical QC Ultra.

**Architecture:** The app project is generated reproducibly with XcodeGen but commits the generated `.xcodeproj`; XcodeGen is development-only and is not shipped. `HeadphoneCore` is created during scaffolding as a minimal local Swift package, then expanded into the pure BMAP codec, framing, builders, parsers, and models. A separate Debug-only sandbox probe validates the service, characteristics, and safe read paths before the production transport/session architecture is built.

**Tech Stack:** Swift 6, Swift Package Manager, XCTest/XCUITest, Xcode 27, XcodeGen, SwiftUI, CoreBluetooth, App Sandbox, Rust/Cargo parity tests, JSON fixtures.

**Spec:** `docs/superpowers/specs/2026-08-29-qc-ultra-macos-controller-design.md`

## Global Constraints

- Work under `apps/macos/UltraController` and leave the existing Rust TUI/daemon behavior unchanged.
- Target macOS 27.0 and `arm64`; do not produce an Intel slice.
- Do not add a runtime dependency on Rust, XcodeGen, Homebrew, Node, or a web runtime.
- Enable App Sandbox and Bluetooth entitlement for every executable that touches CoreBluetooth.
- Use the canonical BMAP service `0000FEBE-0000-1000-8000-00805F9B34FB` and the secure/unsecure characteristic UUIDs from `docs/BMAP.md`.
- The probe begins read-only. It may perform ordinary mode/standby/spatial writes only after supported identity and read paths are confirmed; it never invokes firmware-update functions, reset, pairing, or arbitrary packet injection.
- Preserve raw/opaque bytes when a parser does not understand a field.
- Keep canonical fixtures at repository path `fixtures/bmap`; tests load them directly from the checkout instead of duplicating them into the Swift package.
- Commit after each independently passing task.

---

## File Map

| Path | Responsibility |
|---|---|
| `.gitignore` | Excludes local Xcode, build, and signing configuration while keeping generated project/shared schemes tracked. |
| `Makefile` | Stable Rust and macOS generation/build/test/probe commands. |
| `apps/macos/UltraController/project.yml` | Reproducible app, probe, unit-test, and UI-test target definition. |
| `apps/macos/UltraController/UltraController.xcodeproj` | Generated project committed for ordinary Xcode use. |
| `apps/macos/UltraController/Brewfile` | Development-only XcodeGen dependency. |
| `apps/macos/UltraController/Config/*.xcconfig` | Shared Debug/Release/macOS 27/arm64 settings and untracked local team configuration. |
| `apps/macos/UltraController/Config/App.entitlements` | Main app sandbox, Bluetooth, and App Group entitlements. |
| `apps/macos/UltraController/Config/Probe.entitlements` | Probe sandbox and Bluetooth entitlements only. |
| `apps/macos/UltraController/Packages/HeadphoneCore` | Pure Swift BMAP package. |
| `fixtures/bmap/*.json` | Language-neutral protocol fixtures consumed directly by Swift and Rust tests. |
| `crates/bozo-proto/tests/fixture_parity.rs` | Confirms the existing Rust codec matches shared fixtures. |
| `apps/macos/UltraController/ProtocolProbe` | Debug-only SwiftUI/CoreBluetooth physical-device probe. |
| `docs/protocol/qc-ultra-baseline-probe.md` | Physical-device environment, reads, safe writes, reconnect evidence, and firmware context. |

### Task 1: Scaffold the reproducible macOS project, minimal package, and test targets

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
- Create locally, do not commit: `apps/macos/UltraController/Config/Local.xcconfig`
- Create: `apps/macos/UltraController/Packages/HeadphoneCore/Package.swift`
- Create: `apps/macos/UltraController/Packages/HeadphoneCore/Sources/HeadphoneCore/HeadphoneCore.swift`
- Create: `apps/macos/UltraController/Packages/HeadphoneCore/Tests/HeadphoneCoreTests/HeadphoneCoreSmokeTests.swift`
- Create: `apps/macos/UltraController/App/Application/UltraControllerApp.swift`
- Create: `apps/macos/UltraController/App/Overview/PlaceholderOverviewView.swift`
- Create: `apps/macos/UltraController/ProtocolProbe/ProtocolProbeApp.swift`
- Create: `apps/macos/UltraController/Tests/UltraControllerSmokeTests.swift`
- Create: `apps/macos/UltraController/UITests/UltraControllerUITestSmokeTests.swift`
- Create: `apps/macos/UltraController/Tests/TestSupport/XCTestAsyncSupport.swift`
- Create: `apps/macos/UltraController/Scripts/verify-project.sh`
- Generate: `apps/macos/UltraController/UltraController.xcodeproj`

**Interfaces:**
- Consumes: Xcode 27 command-line tools and XcodeGen.
- Produces: schemes `UltraController` and `UltraControllerProtocolProbe`; targets `UltraController`, `UltraControllerProtocolProbe`, `UltraControllerTests`, and `UltraControllerUITests`; Make targets `macos-generate`, `macos-build`, `macos-test`, `macos-test-core`, and `macos-probe`.

- [ ] **Step 1: Write the project-verification script before creating the project**

Create `apps/macos/UltraController/Scripts/verify-project.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
APP_DIR="$ROOT/apps/macos/UltraController"
PROJECT="$APP_DIR/UltraController.xcodeproj"

[[ -d "$PROJECT" ]] || { echo "missing $PROJECT" >&2; exit 1; }
[[ -f "$APP_DIR/Packages/HeadphoneCore/Package.swift" ]] || { echo "missing HeadphoneCore package" >&2; exit 1; }
[[ -f "$APP_DIR/Config/App.entitlements" ]] || { echo "missing App.entitlements" >&2; exit 1; }
[[ -f "$APP_DIR/Config/PrivacyInfo.xcprivacy" ]] || { echo "missing PrivacyInfo.xcprivacy" >&2; exit 1; }

LIST_OUTPUT="$(xcodebuild -project "$PROJECT" -list)"
grep -q "UltraController" <<<"$LIST_OUTPUT"
grep -q "UltraControllerProtocolProbe" <<<"$LIST_OUTPUT"
grep -q "UltraControllerTests" <<<"$LIST_OUTPUT"
grep -q "UltraControllerUITests" <<<"$LIST_OUTPUT"
```

Run:

```bash
chmod +x apps/macos/UltraController/Scripts/verify-project.sh
apps/macos/UltraController/Scripts/verify-project.sh
```

Expected: FAIL with `missing .../UltraController.xcodeproj`.

- [ ] **Step 2: Add Xcode/local-signing artifacts to `.gitignore`**

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
apps/macos/UltraController/Config/Local.xcconfig
```

Do not ignore `UltraController.xcodeproj`, shared schemes, `project.yml`, or entitlement files.

- [ ] **Step 3: Install the development-only generator and configure the local team**

Create `apps/macos/UltraController/Brewfile`:

```ruby
brew "xcodegen"
```

Run:

```bash
brew bundle --file apps/macos/UltraController/Brewfile
xcodegen --version
: "${DEVELOPMENT_TEAM:?Export DEVELOPMENT_TEAM with your Apple Developer team identifier before signed builds}"
printf 'DEVELOPMENT_TEAM = %s\n' "$DEVELOPMENT_TEAM" \
  > apps/macos/UltraController/Config/Local.xcconfig
```

Expected: XcodeGen exits 0 and the untracked `Local.xcconfig` contains one concrete team identifier.

- [ ] **Step 4: Create build settings**

`Config/Shared.xcconfig`:

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
MARKETING_VERSION = 0.1.0
CURRENT_PROJECT_VERSION = 1
#include? "Local.xcconfig"
```

`Config/Debug.xcconfig`:

```xcconfig
#include "Shared.xcconfig"
SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG
ENABLE_TESTABILITY = YES
DEBUG_INFORMATION_FORMAT = dwarf
```

`Config/Release.xcconfig`:

```xcconfig
#include "Shared.xcconfig"
SWIFT_COMPILATION_MODE = wholemodule
SWIFT_OPTIMIZATION_LEVEL = -O
DEBUG_INFORMATION_FORMAT = dwarf-with-dsym
DEAD_CODE_STRIPPING = YES
```

- [ ] **Step 5: Create exact entitlements, Info.plist, and privacy manifest**

`Config/App.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.device.bluetooth</key><true/>
<key>com.apple.security.application-groups</key>
<array><string>group.dev.densedevkev.ultracontroller</string></array>
</dict></plist>
```

`Config/Probe.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.device.bluetooth</key><true/>
</dict></plist>
```

`Config/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>$(DEVELOPMENT_LANGUAGE)</string>
<key>CFBundleDisplayName</key><string>$(PRODUCT_NAME)</string>
<key>CFBundleExecutable</key><string>$(EXECUTABLE_NAME)</string>
<key>CFBundleIdentifier</key><string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>$(PRODUCT_NAME)</string>
<key>CFBundlePackageType</key><string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
<key>CFBundleShortVersionString</key><string>$(MARKETING_VERSION)</string>
<key>CFBundleVersion</key><string>$(CURRENT_PROJECT_VERSION)</string>
<key>LSMinimumSystemVersion</key><string>$(MACOSX_DEPLOYMENT_TARGET)</string>
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Ultra Controller uses Bluetooth to read and change settings on your selected QC Ultra headphones.</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Kevin. MIT licensed.</string>
</dict></plist>
```

`Config/PrivacyInfo.xcprivacy`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>NSPrivacyTracking</key><false/>
<key>NSPrivacyTrackingDomains</key><array/>
<key>NSPrivacyCollectedDataTypes</key><array/>
<key>NSPrivacyAccessedAPITypes</key><array/>
</dict></plist>
```

- [ ] **Step 6: Create the minimal `HeadphoneCore` package before Xcode generation**

`Package.swift`:

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

`Sources/HeadphoneCore/HeadphoneCore.swift`:

```swift
public enum HeadphoneCoreBuild {
    public static let schemaVersion = 1
}
```

`Tests/HeadphoneCoreTests/HeadphoneCoreSmokeTests.swift`:

```swift
import XCTest
@testable import HeadphoneCore

final class HeadphoneCoreSmokeTests: XCTestCase {
    func testPackageLoads() {
        XCTAssertEqual(HeadphoneCoreBuild.schemaVersion, 1)
    }
}
```

- [ ] **Step 7: Create the minimal app, probe, and tests**

`App/Application/UltraControllerApp.swift`:

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

`App/Overview/PlaceholderOverviewView.swift`:

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

`ProtocolProbe/ProtocolProbeApp.swift`:

```swift
import SwiftUI

@main
struct ProtocolProbeApp: App {
    var body: some Scene {
        WindowGroup { Text("Protocol probe not implemented") }
    }
}
```

`Tests/UltraControllerSmokeTests.swift`:

```swift
import XCTest
@testable import UltraController

final class UltraControllerSmokeTests: XCTestCase {
    func testTestBundleLoads() { XCTAssertTrue(true) }
}
```

`UITests/UltraControllerUITestSmokeTests.swift`:

```swift
import XCTest

final class UltraControllerUITestSmokeTests: XCTestCase {
    func testPlaceholderLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["overview.placeholder"].waitForExistence(timeout: 5))
    }
}
```

Create shared async test support for later plans:

```swift
import XCTest

func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line,
    verify: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        verify(error)
    }
}
```

- [ ] **Step 8: Define and generate the Xcode project**

Create `project.yml`:

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
        PRODUCT_MODULE_NAME: UltraController
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
        PRODUCT_MODULE_NAME: UltraControllerProtocolProbe
        PRODUCT_BUNDLE_IDENTIFIER: dev.densedevkev.ultracontroller.probe
  UltraControllerTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - Tests
    dependencies:
      - target: UltraController
  UltraControllerUITests:
    type: bundle.ui-testing
    platform: macOS
    sources:
      - UITests
    dependencies:
      - target: UltraController
schemes:
  UltraController:
    build:
      targets:
        UltraController: all
        UltraControllerTests: [test]
        UltraControllerUITests: [test]
    test:
      targets:
        - UltraControllerTests
        - UltraControllerUITests
  UltraControllerProtocolProbe:
    build:
      targets:
        UltraControllerProtocolProbe: all
```

Run:

```bash
cd apps/macos/UltraController
xcodegen generate --spec project.yml
cd ../../..
```

- [ ] **Step 9: Add Make targets**

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
	open "$$(xcodebuild -project $(MACOS_PROJECT) -scheme UltraControllerProtocolProbe -destination '$(MACOS_DEST)' -showBuildSettings | awk '/ TARGET_BUILD_DIR /{dir=$$3} / FULL_PRODUCT_NAME /{name=$$3} END{print dir "/" name}')"
```

- [ ] **Step 10: Run scaffold verification and commit**

```bash
apps/macos/UltraController/Scripts/verify-project.sh
make macos-test-core
make macos-build
make macos-test

git add .gitignore Makefile apps/macos/UltraController
git commit -m "build: scaffold native Ultra Controller project"
```

Expected: package, unit, UI, and app builds pass; `Local.xcconfig` remains untracked.

### Task 2: Implement the BMAP packet codec with Rust parity

**Files:**
- Create: `apps/macos/UltraController/Packages/HeadphoneCore/Sources/HeadphoneCore/BMAP/BMAPOperator.swift`
- Create: `.../BMAP/BMAPFunctionBlock.swift`
- Create: `.../BMAP/BMAPPacket.swift`
- Create: `.../BMAP/BMAPCodecError.swift`
- Create: `apps/macos/UltraController/Packages/HeadphoneCore/Tests/HeadphoneCoreTests/BMAPPacketTests.swift`

**Interfaces:**
- Consumes: raw BMAP bytes documented in `crates/bozo-proto/src/bmap/packet.rs`.
- Produces: `BMAPOperator`, `BMAPFunctionBlock`, `BMAPPacket`, `BMAPPacket.decode(_:)`, `BMAPPacket.decodeMany(_:)`, and `BMAPPacket.encoded()`.

- [ ] **Step 1: Write failing codec tests using Bozo's exact bytes**

```swift
import XCTest
@testable import HeadphoneCore

final class BMAPPacketTests: XCTestCase {
    func testBatteryQueryEncodingMatchesRust() throws {
        let packet = BMAPPacket(functionBlock: .status, function: 0x02, operator: .get, payload: [])
        XCTAssertEqual(try packet.encoded(), [0x02, 0x02, 0x01, 0x00])
    }

    func testPowerOffEncodingMatchesRust() throws {
        let packet = BMAPPacket(functionBlock: .control, function: 0x04, operator: .start, payload: [0x00])
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

- [ ] **Step 2: Run and verify failure**

```bash
make macos-test-core
```

Expected: FAIL because `BMAPPacket` is undefined.

- [ ] **Step 3: Implement typed enums and errors**

Define every function block currently represented by Bozo, including `.audioModes = 0x1F`, and operators `.set` through `.processing` with raw values `0...7`.

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

- [ ] **Step 4: Implement `BMAPPacket`**

```swift
public struct BMAPPacket: Equatable, Sendable, Codable {
    public let functionBlock: BMAPFunctionBlock
    public let function: UInt8
    public let deviceID: UInt8
    public let port: UInt8
    public let `operator`: BMAPOperator
    public let payload: [UInt8]

    public init(functionBlock: BMAPFunctionBlock, function: UInt8,
                deviceID: UInt8 = 0, port: UInt8 = 0,
                operator: BMAPOperator, payload: [UInt8]) {
        self.functionBlock = functionBlock
        self.function = function
        self.deviceID = deviceID
        self.port = port
        self.operator = `operator`
        self.payload = payload
    }

    public func encoded() throws -> [UInt8] {
        guard payload.count <= UInt8.max else { throw BMAPCodecError.payloadTooLong(payload.count) }
        return [functionBlock.rawValue, function,
                (deviceID << 6) | (port << 4) | (`operator`.rawValue & 0x0F),
                UInt8(payload.count)] + payload
    }
}
```

Implement `decode(_:)` and `decodeMany(_:)` with the Rust length checks. `decodeMany` throws on trailing/truncated data instead of silently dropping it.

- [ ] **Step 5: Run tests and commit**

```bash
make macos-test-core
git add apps/macos/UltraController/Packages/HeadphoneCore
git commit -m "feat: add Swift BMAP packet codec"
```

### Task 3: Implement BLE segmentation and reassembly

**Files:**
- Create: `.../Sources/HeadphoneCore/BMAP/BLESegmenter.swift`
- Create: `.../Sources/HeadphoneCore/BMAP/BLEReassembler.swift`
- Create: `.../Tests/HeadphoneCoreTests/BLEFramingTests.swift`

**Interfaces:**
- Consumes: encoded BMAP bytes.
- Produces: `BLESegmenter.segment(_:) -> [[UInt8]]` and mutable `BLEReassembler.feed(_:) throws -> [UInt8]?`.

- [ ] **Step 1: Write framing tests**

```swift
final class BLEFramingTests: XCTestCase {
    func testSingleSegmentUsesZeroHeader() throws {
        let data: [UInt8] = [0x01, 0x05, 0x02, 0x02, 0x05, 0x01]
        XCTAssertEqual(try BLESegmenter.segment(data), [[0x00] + data])
    }

    func testTwentyFiveBytesUseTwoSegments() throws {
        let segments = try BLESegmenter.segment([UInt8](repeating: 0xBB, count: 25))
        XCTAssertEqual(segments.compactMap(\.first), [0x10, 0x11])
        XCTAssertEqual(segments.map(\.count), [20, 7])
    }

    func testOutOfOrderSegmentsReassemble() throws {
        let data = [UInt8](0..<30)
        let segments = try BLESegmenter.segment(data)
        var reassembler = BLEReassembler()
        XCTAssertNil(try reassembler.feed(segments[1]))
        XCTAssertEqual(try reassembler.feed(segments[0]), data)
    }

    func testConflictingDuplicateResetsStream() throws {
        var reassembler = BLEReassembler()
        _ = try reassembler.feed([0x10, 0xAA])
        XCTAssertThrowsError(try reassembler.feed([0x10, 0xBB]))
    }
}
```

- [ ] **Step 2: Run and verify failure**

```bash
make macos-test-core
```

Expected: FAIL because framing types are undefined.

- [ ] **Step 3: Implement segmentation with the 4-bit limit**

```swift
public enum BLESegmenter {
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

- [ ] **Step 4: Implement reassembly**

Store segments by index plus one expected count. Exact duplicate segments are idempotent. A duplicate index with different bytes throws `.conflictingDuplicate(index:)` and resets. Inconsistent maximum index, out-of-range index, empty segment, and more than 16 segments throw typed errors and reset. Complete as soon as every index is present, regardless of arrival order.

- [ ] **Step 5: Run all package tests and commit**

```bash
make macos-test-core
git add apps/macos/UltraController/Packages/HeadphoneCore
git commit -m "feat: add BMAP BLE framing"
```

### Task 4: Add typed models and essential BMAP messages

**Files:**
- Create: `.../Sources/HeadphoneCore/Models/BatteryComponent.swift`
- Create: `.../Models/HeadphoneIdentity.swift`
- Create: `.../Models/AudioModeCapabilities.swift`
- Create: `.../Models/AudioMode.swift`
- Create: `.../Models/SpatialAudioMode.swift`
- Create: `.../Protocol/ProductMessages.swift`
- Create: `.../Protocol/BatteryMessages.swift`
- Create: `.../Protocol/StandbyMessages.swift`
- Create: `.../Protocol/PowerMessages.swift`
- Create: `.../Protocol/AudioModeMessages.swift`
- Create: `.../Protocol/SpatialAudioMessages.swift`
- Create: `.../Protocol/BMAPResponseError.swift`
- Test: matching `EssentialMessageTests.swift` and parser test files.

**Interfaces:**
- Consumes: `BMAPPacket`.
- Produces: pure request builders and throwing parsers for product name/identity, battery, standby, power, AudioModes capabilities/all/current/config, and AudioManagement spatial audio function `0x0F`.

- [ ] **Step 1: Write request-builder tests with exact bytes**

```swift
func testEssentialRequestBytes() throws {
    XCTAssertEqual(try BatteryMessages.query().encoded(), [0x02, 0x02, 0x01, 0x00])
    XCTAssertEqual(try StandbyMessages.set(minutes: 30).encoded(), [0x01, 0x04, 0x02, 0x01, 0x1E])
    XCTAssertEqual(try AudioModeMessages.queryAll().encoded(), [0x1F, 0x01, 0x01, 0x00])
    XCTAssertEqual(try AudioModeMessages.queryCapabilities().encoded(), [0x1F, 0x02, 0x01, 0x00])
    XCTAssertEqual(try AudioModeMessages.queryCurrent().encoded(), [0x1F, 0x03, 0x01, 0x00])
    XCTAssertEqual(try AudioModeMessages.queryConfiguration(index: 2).encoded(), [0x1F, 0x06, 0x01, 0x01, 0x02])
    XCTAssertEqual(try SpatialAudioMessages.query().encoded(), [0x05, 0x0F, 0x01, 0x00])
    XCTAssertEqual(try PowerMessages.powerOff().encoded(), [0x07, 0x04, 0x05, 0x01, 0x00])
}
```

- [ ] **Step 2: Write parser tests**

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
    payload[0] = 2; payload[2] = 12; payload[3] = 1; payload[5] = 1
    Array("Music".utf8).enumerated().forEach { payload[6 + $0.offset] = $0.element }
    payload[38] = 0xA1; payload[39] = 0xB2; payload[40] = 0xC3
    payload[41] = 0b0001_1111; payload[42] = 7; payload[43] = 1
    payload[44] = 2; payload[45] = 0xD4; payload[46] = 1; payload[47] = 1
    let packet = BMAPPacket(functionBlock: .audioModes, function: 0x06, operator: .status,
                            payload: payload)
    let mode = try AudioModeMessages.parseConfiguration(packet)
    XCTAssertEqual(mode.name, "Music")
    XCTAssertEqual(mode.opaqueReservedBytes, [0xA1, 0xB2, 0xC3, 0xD4])
    XCTAssertEqual(mode.rawPayload, payload)
}
```

- [ ] **Step 3: Run and verify failure**

```bash
make macos-test-core
```

Expected: FAIL because message/model types are undefined.

- [ ] **Step 4: Implement public model shapes**

```swift
public struct BatteryComponent: Sendable, Codable, Equatable, Identifiable {
    public let id: UInt8
    public let percentage: UInt8
    public let remainingMinutes: UInt16?
}

public enum SpatialAudioMode: UInt8, Sendable, Codable, CaseIterable {
    case off = 0, still = 1, motion = 2
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

Every parser verifies function block, function, response operator, and minimum/exact structure. If `operator == .error`, throw `BMAPResponseError` with the first error byte and optional function-specific byte. Unknown enum values are retained as raw values or cause a typed unsupported-value error; never coerce them to `off` or `false`.

Battery accepts one legacy short percentage response only when physically observed and recorded; otherwise require complete four-byte components. ModeConfig retains its entire raw payload and reserved bytes at 38–40 and 45.

- [ ] **Step 6: Run all package tests and commit**

```bash
make macos-test-core
git add apps/macos/UltraController/Packages/HeadphoneCore
git commit -m "feat: add typed QC Ultra BMAP messages"
```

### Task 5: Establish shared JSON fixtures and Rust/Swift parity

**Files:**
- Create: `fixtures/bmap/manifest.json`
- Create: `fixtures/bmap/*.json`
- Create: `apps/macos/UltraController/Packages/HeadphoneCore/Tests/HeadphoneCoreTests/FixtureLoader.swift`
- Create: `.../FixtureParityTests.swift`
- Create: `crates/bozo-proto/tests/fixture_parity.rs`
- Modify: `crates/bozo-proto/Cargo.toml` only for missing test-only dependencies.

**Interfaces:**
- Consumes: canonical files under repository `fixtures/bmap`.
- Produces: one corpus proven to decode identically in Swift and Rust without copying/symlinking fixture resources into the package.

- [ ] **Step 1: Define the manifest and fixture schema**

`fixtures/bmap/manifest.json`:

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

Each file uses:

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

Use exact bytes from tested Bozo behavior. Never commit serials or full peripheral identifiers.

- [ ] **Step 2: Write the Swift filesystem fixture loader and failing parity test**

```swift
import Foundation

struct FixtureLoader {
    static func repositoryRoot(filePath: StaticString = #filePath) -> URL {
        var url = URL(fileURLWithPath: String(describing: filePath))
        for _ in 0..<8 { url.deleteLastPathComponent() }
        return url
    }

    static func data(named name: String) throws -> Data {
        let url = repositoryRoot()
            .appendingPathComponent("fixtures/bmap")
            .appendingPathComponent(name)
        return try Data(contentsOf: url)
    }
}
```

`FixtureParityTests` loads the manifest, decodes each `wireHex`, calls `BMAPPacket.decode`, and compares every expected header/payload field.

Run:

```bash
make macos-test-core
```

Expected: FAIL until all fixture files/Decodable test structs exist.

- [ ] **Step 3: Make Swift parity tests pass**

Implement fixture Decodable structs and a strict hex decoder that rejects odd length or invalid characters. Do not add SwiftPM resource declarations for repository-external paths.

- [ ] **Step 4: Write the Rust parity integration test**

Use `env!("CARGO_MANIFEST_DIR")` to resolve `../../fixtures/bmap`:

```rust
#[test]
fn shared_fixtures_decode_with_rust_codec() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/bmap");
    let manifest: Manifest = serde_json::from_slice(&fs::read(root.join("manifest.json")).unwrap()).unwrap();
    for filename in manifest.fixtures {
        let fixture: Fixture = serde_json::from_slice(&fs::read(root.join(filename)).unwrap()).unwrap();
        let bytes = hex::decode(&fixture.wire_hex).unwrap();
        let packet = BmapPacket::from_bytes(&bytes).unwrap();
        assert_eq!(u8::from(packet.function_block), fixture.expected.function_block);
        assert_eq!(packet.function, fixture.expected.function);
        assert_eq!(u8::from(packet.operator), fixture.expected.operator);
        assert_eq!(hex::encode(packet.payload), fixture.expected.payload_hex.to_lowercase());
    }
}
```

Add `hex` and `serde_json` as dev-dependencies only when absent.

- [ ] **Step 5: Run parity verification and commit**

```bash
cargo test -p bozo-proto --test fixture_parity
make macos-test-core
cargo test --workspace

git add fixtures/bmap crates/bozo-proto apps/macos/UltraController/Packages/HeadphoneCore
git commit -m "test: share BMAP fixtures across Rust and Swift"
```

### Task 6: Build and run the sandboxed protocol probe

**Files:**
- Replace: `apps/macos/UltraController/ProtocolProbe/ProtocolProbeApp.swift`
- Create: `apps/macos/UltraController/ProtocolProbe/ProbeView.swift`
- Create: `apps/macos/UltraController/ProtocolProbe/ProbeViewModel.swift`
- Create: `apps/macos/UltraController/ProtocolProbe/ProbeCentral.swift`
- Create: `apps/macos/UltraController/ProtocolProbe/ProbeEvent.swift`
- Create: `apps/macos/UltraController/Tests/ProtocolProbeReducerTests.swift`
- Create: `docs/protocol/qc-ultra-baseline-probe.md`

**Interfaces:**
- Consumes: `HeadphoneCore`, CoreBluetooth, physical QC Ultra.
- Produces: evidence for service/characteristic discovery, supported identity fingerprint, battery, mode capabilities/list/config, current mode, standby, spatial audio, and safe essential writes.

- [ ] **Step 1: Write reducer tests**

```swift
func testProbeEventsProduceReadableRows() {
    var state = ProbeViewModel.State()
    state.reduce(.discovered(name: "QC Ultra", idSuffix: "0001", rssi: -42))
    state.reduce(.battery([BatteryComponent(id: 0, percentage: 85, remainingMinutes: 300)]))
    XCTAssertEqual(state.rows.map(\.title), ["Discovered", "Battery"])
}
```

Run `make macos-test`; expect failure until reducer/events exist.

- [ ] **Step 2: Implement `ProbeCentral`**

Use:

```swift
private let serviceUUID = CBUUID(string: "FEBE")
private let secureUUID = CBUUID(string: "C65B8F2F-AEE2-4C89-B758-BC4892D6F2D8")
private let unsecureUUID = CBUUID(string: "D417C028-9818-4354-99D1-2AC09D074591")
```

Discovery order:

1. `retrieveConnectedPeripherals(withServices: [serviceUUID])`.
2. Filtered service scan for five seconds.
3. If empty, unfiltered scan for five seconds; name-matched devices remain unverified until BMAP reads succeed.

Prefer a characteristic supporting notify plus write; prefer secure when both qualify. Feed notifications through `BLEReassembler`, then `BMAPPacket.decodeMany`.

- [ ] **Step 3: Send the safe initial read sequence**

After notification subscription:

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

Serialize writes 100 ms apart. After capabilities/list arrives, query every reported mode index. Never brute-force `0..<10`.

- [ ] **Step 4: Build the probe UI without raw command entry**

Provide Bluetooth state, Start/Stop Scan, candidate list, Connect/Disconnect, parsed response table, scrubbed raw hex, and `Copy Sanitized Session`. Omit full UUIDs/serials and omit arbitrary packet input.

- [ ] **Step 5: Run automated tests and signed probe build**

```bash
make macos-test-core
make macos-test
make macos-probe
```

Expected: tests pass, the app is signed with the local team, opens, and prompts for Bluetooth on first use.

- [ ] **Step 6: Execute physical read-only validation**

Record:

1. Retrieval/scan path.
2. BMAP service and selected characteristic properties.
3. Notification success.
4. Product name and strongest non-user-editable identity/capability fingerprint available.
5. Battery and remaining time.
6. Capabilities, valid indexes, current mode, and every mode config.
7. Standby.
8. Spatial audio or exact typed unsupported/error response.
9. Three disconnect/reconnect read repetitions.

- [ ] **Step 7: Execute safe essential write/restore checks**

Only after supported identity is confirmed:

1. Record original active mode, standby, and spatial mode.
2. Switch to another existing mode; GET current mode and confirm; restore original.
3. Set standby to another documented allowed value; GET and confirm; restore original.
4. If spatial audio is supported, set one other supported value; GET and confirm; restore original.
5. Send Power Off last; confirm expected disconnect and no further operation.

Do not test advanced ModeConfig writes in this plan.

- [ ] **Step 8: Write the evidence document**

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

## Essential write and restoration
| Operation | Original | Requested | Confirmed | Restored |

## Reconnect repetitions
| Attempt | Discovery path | Characteristic | Initial sync result |

## Identity fingerprint used by production
## Unsupported or ambiguous behavior
## Fixtures added
## Gate conclusion
```

Populate every field and commit no unsanitized identifier.

- [ ] **Step 9: Commit probe/evidence**

```bash
git add apps/macos/UltraController/ProtocolProbe apps/macos/UltraController/Tests/ProtocolProbeReducerTests.swift \
  docs/protocol/qc-ultra-baseline-probe.md fixtures/bmap
git commit -m "test: validate QC Ultra protocol baseline"
```

### Task 7: Run the Plan 1 checkpoint

**Files:**
- Verify all files created by Tasks 1–6.

**Interfaces:**
- Produces for Plan 2: tested `HeadphoneCore`, shared fixtures, working BLE discovery/channel policy, supported-device fingerprint, and physical baseline evidence.

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

Expected: every command exits 0 with nonzero test counts and zero failures.

- [ ] **Step 3: Verify architecture and entitlements**

```bash
APP_PATH="$(find ~/Library/Developer/Xcode/DerivedData -path '*Build/Products/Debug/Ultra Controller.app' -print -quit)"
test -n "$APP_PATH"
lipo -archs "$APP_PATH/Contents/MacOS/Ultra Controller" | grep -qx arm64
codesign -d --entitlements :- "$APP_PATH" 2>/dev/null \
  | grep -q 'com.apple.security.app-sandbox'
codesign -d --entitlements :- "$APP_PATH" 2>/dev/null \
  | grep -q 'com.apple.security.device.bluetooth'
```

- [ ] **Step 4: Verify evidence completeness**

```bash
grep -q 'Headphone firmware:' docs/protocol/qc-ultra-baseline-probe.md
grep -q '## Identity fingerprint used by production' docs/protocol/qc-ultra-baseline-probe.md
grep -q '## Gate conclusion' docs/protocol/qc-ultra-baseline-probe.md
! grep -E 'TBD|TODO|REPLACE_ME|<fill' docs/protocol/qc-ultra-baseline-probe.md
```

Expected: all checks exit 0.

- [ ] **Step 5: Commit only actual verification fixes**

```bash
git status --short
```

Plan 1 is complete only when the signed probe has read and safely restored essential settings on the physical headset and the evidence is committed; codec tests alone are insufficient.
