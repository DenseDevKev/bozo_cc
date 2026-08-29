# Ultra Controller Release Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the feature-complete app into a privacy-reviewed, accessibility-tested, energy-profiled, signed/notarized, physically validated v1 release candidate suitable for personal use or an optional GitHub Release.

**Architecture:** Release hardening adds bounded privacy-aware diagnostics, explicit legal/privacy documentation, repeatable verification scripts, and evidence reports without changing the one-session Bluetooth architecture. A public artifact is generated only from a clean Release archive, verified for architecture and entitlements, notarized with Developer ID credentials supplied outside the repository, and checked on a clean user account or Mac.

**Tech Stack:** Swift 6, `os.Logger`, XCTest/XCUITest, Xcode 27, `xcodebuild`, `xctrace`, `codesign`, `security`, `otool`, `lipo`, `spctl`, `xcrun notarytool`, `xcrun stapler`, `ditto`, `hdiutil`, shell scripts.

**Spec:** `docs/superpowers/specs/2026-08-29-qc-ultra-macos-controller-design.md`

## Global Constraints

- Plans 1–4 and both feasibility gates must pass before a release candidate is labeled v1.
- Ship `arm64` only and target macOS 27.0 or newer.
- Keep App Sandbox enabled and keep the controls extension free of Bluetooth entitlement/code.
- Do not add network client/server entitlements, analytics, telemetry, crash upload, account code, cloud sync, or an auto-updater.
- Keep diagnostics local, bounded, opt-in for raw packet metadata, and redacted by default.
- Never package Rust binaries, the terminal app, `bozod`, XcodeGen, tests, fixture captures, or debug probes in the app bundle.
- Do not store signing identities, Apple credentials, API keys, notarization passwords, or keychain exports in Git.
- Public copy must state that the project is independent and not affiliated with or endorsed by Bose.
- A public release is optional; personal Xcode-signed builds remain supported.
- Performance targets are evidence gates, not assumptions: idle CPU median below 0.2%, desktop-window memory below 80 MB, no repeating idle polling timer, and Low energy impact unless a documented OS floor prevents one target.

---

## File Map

| Path | Responsibility |
|---|---|
| `App/Diagnostics/DiagnosticEvent.swift` | Structured, privacy-classified diagnostic values. |
| `App/Diagnostics/DiagnosticStore.swift` | Bounded in-memory event ring and opt-in raw metadata policy. |
| `App/Diagnostics/SupportBundleExporter.swift` | Explicit, sanitized local support export. |
| `App/Settings/DiagnosticsSettingsView.swift` | User controls for diagnostics/export/clear. |
| `docs/privacy.md` | Plain-language local-only privacy policy. |
| `THIRD_PARTY_NOTICES.md` | Bozo/bozo-bar attribution and license notices. |
| `docs/support.md` | Supported device/firmware scope and troubleshooting. |
| `CHANGELOG.md` | Release history. |
| `Scripts/verify-release.sh` | Bundle architecture, signing, entitlement, dependency, and contents gate. |
| `Scripts/archive.sh` | Clean Release archive and export. |
| `Scripts/package.sh` | ZIP and optional DMG production plus checksums. |
| `Scripts/notarize.sh` | Notary submission and staple using an external keychain profile. |
| `Scripts/profile-idle.sh` | Repeatable ten-minute Time Profiler/memory/CPU capture. |
| `Scripts/validate-app-store-structure.sh` | Store-readiness structure check without submission. |
| `Config/ExportOptions/DeveloperID.plist` | Developer ID export options. |
| `Config/ExportOptions/AppStore.plist` | Future App Store export options. |
| `docs/release/performance-report.md` | Instruments results and accepted deviations. |
| `docs/release/v0.1.0-checklist.md` | Physical/device/system/release acceptance record. |
| `docs/release/supported-firmware.md` | Exact physically validated firmware list and policy. |

### Task 1: Add bounded privacy-aware diagnostics and support export

**Files:**
- Create: `apps/macos/UltraController/App/Diagnostics/DiagnosticCategory.swift`
- Create: `apps/macos/UltraController/App/Diagnostics/DiagnosticPrivacy.swift`
- Create: `apps/macos/UltraController/App/Diagnostics/DiagnosticEvent.swift`
- Create: `apps/macos/UltraController/App/Diagnostics/DiagnosticStore.swift`
- Create: `apps/macos/UltraController/App/Diagnostics/DiagnosticRedactor.swift`
- Create: `apps/macos/UltraController/App/Diagnostics/SupportBundleExporter.swift`
- Create: `apps/macos/UltraController/App/Diagnostics/SupportBundleManifest.swift`
- Create: `apps/macos/UltraController/App/Settings/DiagnosticsSettingsView.swift`
- Modify: `apps/macos/UltraController/App/Settings/SettingsView.swift`
- Modify: `apps/macos/UltraController/App/Bluetooth/CoreBluetoothTransport.swift`
- Modify: `apps/macos/UltraController/App/Session/HeadphoneSession.swift`
- Modify: `apps/macos/UltraController/App/Intents/HeadphoneIntentController.swift`
- Test: `apps/macos/UltraController/Tests/Diagnostics/DiagnosticStoreTests.swift`
- Test: `apps/macos/UltraController/Tests/Diagnostics/DiagnosticRedactorTests.swift`
- Test: `apps/macos/UltraController/Tests/Diagnostics/SupportBundleExporterTests.swift`

**Interfaces:**
- Consumes: transport/session/intent lifecycle events.
- Produces: capped local event history, normal privacy-safe unified logging, and an explicit sanitized ZIP support bundle.

- [ ] **Step 1: Write bounded-store and redaction tests**

```swift
final class DiagnosticStoreTests: XCTestCase {
    func testRingKeepsNewestFiveHundredEvents() async {
        let store = DiagnosticStore(capacity: 500)
        for index in 0..<600 {
            await store.append(.test(index: index))
        }
        let events = await store.snapshot()
        XCTAssertEqual(events.count, 500)
        XCTAssertEqual(events.first?.sequence, 100)
        XCTAssertEqual(events.last?.sequence, 599)
    }
}

final class DiagnosticRedactorTests: XCTestCase {
    func testPeripheralUUIDIsRedactedByDefault() {
        let input = "Peripheral 123E4567-E89B-12D3-A456-426614174000 disconnected"
        XCTAssertEqual(
            DiagnosticRedactor.default.redact(input),
            "Peripheral <redacted-uuid> disconnected"
        )
    }

    func testPacketPayloadIsOmittedWithoutRawCaptureConsent() {
        let event = DiagnosticEvent.packet(functionBlock: 31, function: 6, operator: 3, payloadHex: "DEADBEEF")
        XCTAssertNil(event.exportedPayload(includeRawMetadata: false))
    }
}
```

- [ ] **Step 2: Run and verify failure**

```bash
make macos-test
```

Expected: FAIL because diagnostic types are undefined.

- [ ] **Step 3: Define structured diagnostic events**

```swift
enum DiagnosticCategory: String, Codable, Sendable {
    case application, bluetooth, bmap, session, appIntents, persistence
}

enum DiagnosticPrivacy: String, Codable, Sendable {
    case normal
    case privateValue
    case rawProtocolMetadata
}

struct DiagnosticEvent: Codable, Equatable, Sendable {
    let sequence: UInt64
    let timestamp: Date
    let category: DiagnosticCategory
    let name: String
    let privacy: DiagnosticPrivacy
    let fields: [String: String]
}
```

Do not store `CBPeripheral`, `Error`, or other non-Codable framework objects. Convert them immediately into bounded typed fields.

- [ ] **Step 4: Implement the actor-owned bounded store**

```swift
actor DiagnosticStore {
    private let capacity: Int
    private var nextSequence: UInt64 = 0
    private var events: [DiagnosticEvent] = []

    init(capacity: Int = 500) { self.capacity = capacity }

    func append(category: DiagnosticCategory, name: String,
                privacy: DiagnosticPrivacy = .normal,
                fields: [String: String] = [:]) {
        let event = DiagnosticEvent(
            sequence: nextSequence,
            timestamp: .now,
            category: category,
            name: name,
            privacy: privacy,
            fields: fields
        )
        nextSequence += 1
        events.append(event)
        if events.count > capacity { events.removeFirst(events.count - capacity) }
    }

    func snapshot() -> [DiagnosticEvent] { events }
    func clear() { events.removeAll(keepingCapacity: true) }
}
```

- [ ] **Step 5: Add privacy-aware unified logging**

Use one `Logger` per category. Normal builds log state transitions, operation names, durations, and typed error categories. Stable UUIDs, serials, product identifiers, and packet payloads use `.private` interpolation or remain omitted. Do not continuously write a custom log file.

- [ ] **Step 6: Implement explicit support-bundle export**

The exporter creates a temporary directory with:

```text
UltraController-Support-<timestamp>/
├── manifest.json
├── events.json
├── capabilities.json
├── verified-mode-profile-checksum.txt
└── README.txt
```

`manifest.json` includes app version/build, macOS version, Mac architecture, headphone firmware, connected/disconnected state, and whether raw protocol metadata was explicitly included. It excludes full peripheral UUID, serial number, raw mode names when the user chose custom names, audio history, and all credentials.

Compress with Foundation's `FileManager.zipItem(at:to:)` if available in the final SDK; otherwise invoke no shell from the shipped app—export the directory through `NSSavePanel` and let the release plan's test helper zip it outside the app. The shipped application must not launch `/usr/bin/zip`.

- [ ] **Step 7: Add Diagnostics settings**

Hidden developer diagnostics offers:

- Enable bounded detailed events.
- Include raw protocol metadata in the next export, off by default, with warning.
- Export Support Bundle.
- Clear Diagnostics.
- Current event count and oldest/newest timestamp.

No arbitrary packet injection or remote upload button exists.

- [ ] **Step 8: Run tests and commit**

```bash
make macos-test

git add apps/macos/UltraController/App/Diagnostics \
  apps/macos/UltraController/App/Settings \
  apps/macos/UltraController/App/Bluetooth/CoreBluetoothTransport.swift \
  apps/macos/UltraController/App/Session/HeadphoneSession.swift \
  apps/macos/UltraController/App/Intents/HeadphoneIntentController.swift \
  apps/macos/UltraController/Tests/Diagnostics
git commit -m "feat: add private bounded diagnostics"
```

### Task 2: Complete privacy, attribution, support, and release documentation

**Files:**
- Modify: `README.md`
- Create: `THIRD_PARTY_NOTICES.md`
- Create: `docs/privacy.md`
- Create: `docs/support.md`
- Create: `docs/release/supported-firmware.md`
- Create: `CHANGELOG.md`
- Modify: `apps/macos/UltraController/App/Settings/AboutView.swift`
- Modify: `apps/macos/UltraController/App/Resources/Localizable.xcstrings`
- Test: `apps/macos/UltraController/Tests/Documentation/BundledDocumentationTests.swift`

**Interfaces:**
- Consumes: final app behavior and physically validated firmware evidence.
- Produces: accurate public documentation and bundled About/privacy/attribution copy.

- [ ] **Step 1: Write bundled-document tests**

```swift
final class BundledDocumentationTests: XCTestCase {
    func testRequiredLegalCopyIsBundled() throws {
        let notices = try XCTUnwrap(Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md"))
        let text = try String(contentsOf: notices)
        XCTAssertTrue(text.contains("NerdySouth/bozo"))
        XCTAssertTrue(text.contains("NerdySouth/bozo-bar"))
        XCTAssertTrue(text.contains("MIT License"))
    }

    func testPrivacyCopyStatesNoTelemetry() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "privacy", withExtension: "md"))
        let text = try String(contentsOf: url)
        XCTAssertTrue(text.contains("does not collect analytics or telemetry"))
    }
}
```

- [ ] **Step 2: Run and verify failure**

```bash
make macos-test
```

Expected: FAIL because documents are absent from app resources.

- [ ] **Step 3: Update the root README with a separate product section**

Add these exact sections without replacing Bozo's existing Rust documentation:

```markdown
## Ultra Controller for macOS
### Status
### Supported hardware and macOS version
### Architecture and relationship to Bozo
### Building the native app
### Privacy
### Distribution
### Project independence
```

State clearly that Ultra Controller ports and tests BMAP knowledge from Bozo but ships no Rust daemon/runtime.

- [ ] **Step 4: Write `THIRD_PARTY_NOTICES.md`**

Include:

- repository MIT license reference
- `NerdySouth/bozo` copyright/URL and MIT notice
- `NerdySouth/bozo-bar` copyright/URL and MIT notice
- a note identifying files or algorithms derived from each project
- no copied Bose artwork, proprietary source, or decompiled APK content in distributed artifacts

Copy the full MIT license text once and state that all included MIT components are covered by it.

- [ ] **Step 5: Write the privacy policy**

`docs/privacy.md` states:

- control occurs locally over Bluetooth
- no account, cloud sync, ads, analytics, telemetry, or automatic crash upload
- no microphone/audio/listening-history collection
- locally stored preferences and shared snapshot fields
- optional local diagnostics and explicit export behavior
- no required network entitlement
- how to clear selected device/preferences/diagnostics

- [ ] **Step 6: Write support and firmware policy**

`docs/support.md` covers permission recovery, Bluetooth off, out of range, competing controller, reconnect, forgetting/re-onboarding, Control Center fallback, and collecting a support bundle.

`docs/release/supported-firmware.md` uses:

```markdown
# Supported Firmware

## Physically validated
| Headphone generation | Firmware | Essential controls | Advanced fields | Control Center policy | Validation report |

## Unknown firmware policy
- Essential reads must pass capability and parser validation.
- Advanced editing remains disabled unless an exact verified profile exists.
- Unknown payloads fail closed.
```

Populate the physically tested firmware from Gate A/B evidence.

- [ ] **Step 7: Create the changelog**

```markdown
# Changelog

## [Unreleased]

## [0.1.0] - 2026-__-__
### Added
- Native macOS desktop and menu-bar controller for QC Ultra Headphones Gen 1.
- Verified essential controls and evidence-backed advanced mode fields.
- Control Center/system menu-bar controls according to the recorded lifecycle policy.
### Privacy
- Local-only operation with no analytics, account, or required network access.
```

Keep the release date under `[Unreleased]` until the release candidate passes; the final release task replaces the date.

- [ ] **Step 8: Bundle and present the documents**

Add `THIRD_PARTY_NOTICES.md`, `docs/privacy.md`, and `docs/support.md` to the app resource target. `AboutView` opens native sheets rendering these bundled files, displays version/build, and states `Ultra Controller is an independent project and is not affiliated with or endorsed by Bose.`

- [ ] **Step 9: Run tests and commit**

```bash
make macos-generate
make macos-test

git add README.md THIRD_PARTY_NOTICES.md CHANGELOG.md docs/privacy.md docs/support.md docs/release/supported-firmware.md \
  apps/macos/UltraController/App/Settings/AboutView.swift \
  apps/macos/UltraController/App/Resources/Localizable.xcstrings \
  apps/macos/UltraController/project.yml \
  apps/macos/UltraController/Tests/Documentation
git commit -m "docs: add Ultra Controller privacy and attribution"
```

### Task 3: Add repeatable energy, memory, and lifecycle profiling

**Files:**
- Create: `apps/macos/UltraController/Scripts/profile-idle.sh`
- Create: `apps/macos/UltraController/Scripts/profile-reconnect.sh`
- Create: `apps/macos/UltraController/Scripts/summarize-process-samples.py`
- Create: `apps/macos/UltraController/App/Diagnostics/PerformanceScenario.swift`
- Modify: `apps/macos/UltraController/App/Application/AppEnvironment.swift`
- Create: `docs/release/performance-report.md`
- Test: `apps/macos/UltraController/Tests/Diagnostics/PerformanceScenarioTests.swift`

**Interfaces:**
- Consumes: Release app and deterministic `--performance-scenario` launch arguments.
- Produces: ten-minute CPU/RSS samples, Instruments traces, reconnect measurements, and a committed performance report.

- [ ] **Step 1: Add deterministic profiling launch scenarios**

```swift
enum PerformanceScenario: String {
    case idleWindowlessConnected
    case idleDesktopConnected
    case reconnectUnavailable
}
```

In non-App-Store development/release test builds only, `--performance-scenario <value>` selects a scripted or physical profiling path and disables unrelated onboarding animation. It must not create a fake success state in ordinary builds.

- [ ] **Step 2: Write scenario parsing tests**

```swift
func testPerformanceScenarioParsesKnownValue() {
    XCTAssertEqual(
        PerformanceScenario(arguments: ["app", "--performance-scenario", "idleDesktopConnected"]),
        .idleDesktopConnected
    )
}

func testUnknownScenarioIsIgnored() {
    XCTAssertNil(PerformanceScenario(arguments: ["app", "--performance-scenario", "unknown"]))
}
```

- [ ] **Step 3: Implement process sampling script**

Create `profile-idle.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:?usage: profile-idle.sh /path/to/Ultra\ Controller.app output-dir}"
OUTPUT_DIR="${2:?missing output directory}"
SCENARIO="${3:-idleWindowlessConnected}"
DURATION_SECONDS="${DURATION_SECONDS:-600}"
SAMPLE_INTERVAL="${SAMPLE_INTERVAL:-5}"

mkdir -p "$OUTPUT_DIR"
open -n "$APP_PATH" --args --performance-scenario "$SCENARIO"
PID="$(pgrep -n -x 'Ultra Controller')"
trap 'kill "$PID" 2>/dev/null || true' EXIT

printf 'timestamp,cpu_percent,rss_kb\n' > "$OUTPUT_DIR/process.csv"
END=$((SECONDS + DURATION_SECONDS))
while (( SECONDS < END )); do
  read -r CPU RSS < <(ps -p "$PID" -o %cpu=,rss=)
  printf '%s,%s,%s\n' "$(date -u +%FT%TZ)" "$CPU" "$RSS" >> "$OUTPUT_DIR/process.csv"
  sleep "$SAMPLE_INTERVAL"
done

xcrun xctrace record \
  --template 'Time Profiler' \
  --attach "$PID" \
  --time-limit 30s \
  --output "$OUTPUT_DIR/time-profiler.trace"

python3 "$(dirname "$0")/summarize-process-samples.py" \
  "$OUTPUT_DIR/process.csv" \
  > "$OUTPUT_DIR/summary.json"
```

- [ ] **Step 4: Implement sample summarization**

`summarize-process-samples.py` reads CSV and writes JSON:

```json
{
  "samples": 120,
  "cpuMedianPercent": 0.1,
  "cpuP95Percent": 0.4,
  "rssMedianMB": 61.2,
  "rssMaximumMB": 72.8
}
```

Use Python's `statistics.median` and a deterministic nearest-rank P95 calculation. Add a script self-test with a temporary three-row CSV.

- [ ] **Step 5: Add reconnect profiling**

`profile-reconnect.sh` launches the physical app with diagnostics enabled, keeps the selected headphones unavailable for five minutes, then exports diagnostic event timestamps. Assert delays follow `1, 2, 5, 10, 30, 30...` with no overlapping scans. Repeat once through Mac sleep/wake.

- [ ] **Step 6: Run the profiling matrix**

Profile Release builds for:

1. Connected, no window visible, ten minutes.
2. Connected, desktop window visible, ten minutes.
3. Selected headphones unavailable, five minutes.
4. Ten connect/disconnect cycles.
5. App and control extension after Control Center actions.

Use Instruments Time Profiler, Allocations, Leaks, and Energy Log. Capture screenshots or exported trace references locally; do not commit large `.trace` bundles. Commit only summaries and observations.

- [ ] **Step 7: Write `performance-report.md`**

```markdown
# Ultra Controller Performance Report

## Environment
- App commit:
- Configuration:
- macOS build:
- Mac model:
- Headphone firmware:

## Idle results
| Scenario | Duration | CPU median | CPU P95 | RSS median | RSS max | Energy |

## Reconnect behavior
| Scenario | Attempts | Delay sequence | Overlap observed | Sleep/wake result |

## Leak and retention checks
## Timer and wakeup audit
## Bundle size
## Deviations and disposition
## Performance gate conclusion
```

A deviation requires a concrete root cause and user-approved adjustment before public release. Do not silently relax the spec target.

- [ ] **Step 8: Commit profiling tooling and report**

```bash
chmod +x apps/macos/UltraController/Scripts/profile-idle.sh apps/macos/UltraController/Scripts/profile-reconnect.sh
make macos-test
! grep -E 'TBD|TODO|REPLACE_ME' docs/release/performance-report.md

git add apps/macos/UltraController/Scripts apps/macos/UltraController/App/Diagnostics/PerformanceScenario.swift \
  apps/macos/UltraController/App/Application/AppEnvironment.swift \
  apps/macos/UltraController/Tests/Diagnostics/PerformanceScenarioTests.swift \
  docs/release/performance-report.md
git commit -m "perf: profile Ultra Controller release behavior"
```

### Task 4: Build deterministic archive, packaging, and bundle-verification scripts

**Files:**
- Modify: `apps/macos/UltraController/Config/Shared.xcconfig`
- Create: `apps/macos/UltraController/Config/ExportOptions/DeveloperID.plist`
- Create: `apps/macos/UltraController/Config/ExportOptions/AppStore.plist`
- Create: `apps/macos/UltraController/Scripts/archive.sh`
- Create: `apps/macos/UltraController/Scripts/package.sh`
- Create: `apps/macos/UltraController/Scripts/verify-release.sh`
- Create: `apps/macos/UltraController/Scripts/validate-app-store-structure.sh`
- Create: `apps/macos/UltraController/Tests/Scripts/verify_release_script_test.sh`

**Interfaces:**
- Consumes: clean Release build, externally supplied team/signing variables.
- Produces: exported app, ZIP/DMG/checksums, and a machine-readable release-verification report.

- [ ] **Step 1: Set explicit version/build values**

Append to `Shared.xcconfig`:

```xcconfig
MARKETING_VERSION = 0.1.0
CURRENT_PROJECT_VERSION = 1
APPLICATION_EXTENSION_API_ONLY = NO
```

Set `APPLICATION_EXTENSION_API_ONLY = YES` only on the controls extension target in `project.yml`.

- [ ] **Step 2: Create export option plists**

`DeveloperID.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>developer-id</string>
<key>signingStyle</key><string>automatic</string>
<key>stripSwiftSymbols</key><true/>
</dict></plist>
```

`AppStore.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>signingStyle</key><string>automatic</string>
<key>uploadSymbols</key><true/>
</dict></plist>
```

If Xcode 27 changes an export method token, update to the exact value emitted by Xcode's archive organizer and record the change in the release checklist.

- [ ] **Step 3: Implement the archive script**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
APP_DIR="$ROOT/apps/macos/UltraController"
BUILD_DIR="$ROOT/build/ultra-controller"
TEAM_ID="${DEVELOPMENT_TEAM:?set DEVELOPMENT_TEAM}"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cd "$APP_DIR"
xcodegen generate --spec project.yml

xcodebuild clean archive \
  -project UltraController.xcodeproj \
  -scheme UltraController \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$BUILD_DIR/UltraController.xcarchive" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO

xcodebuild -exportArchive \
  -archivePath "$BUILD_DIR/UltraController.xcarchive" \
  -exportPath "$BUILD_DIR/export" \
  -exportOptionsPlist Config/ExportOptions/DeveloperID.plist
```

- [ ] **Step 4: Implement bundle verification**

`verify-release.sh APP_PATH REPORT_PATH` checks:

1. `lipo -archs` equals exactly `arm64`.
2. `codesign --verify --deep --strict --verbose=2` passes.
3. Main app and embedded extension have expected bundle IDs.
4. Main app entitlements contain sandbox, Bluetooth, and App Group.
5. Extension entitlements contain sandbox and App Group but not Bluetooth.
6. `PrivacyInfo.xcprivacy`, `THIRD_PARTY_NOTICES.md`, privacy, and support docs are bundled.
7. One `.appex` exists at the expected path.
8. No file named `bozod`, `bozo`, `cargo`, `node`, `xcodegen`, or test bundle exists inside the app.
9. `otool -L` shows only system/Swift/runtime libraries expected for a native app.
10. `spctl --assess --type execute --verbose=4` passes after notarization; before notarization, the script records `pending-notarization` rather than falsely marking complete.

Write JSON with every check and status. Exit nonzero when any mandatory check fails.

- [ ] **Step 5: Write a shell regression test for the verifier**

The test builds a fake app tree with a fake `bozod` file and invokes a `--filesystem-only` mode of `verify-release.sh`. Expected: nonzero exit and report entry `forbiddenRuntimeFiles: failed`. Remove the forbidden file and expect the filesystem-only checks to pass.

- [ ] **Step 6: Implement packaging**

`package.sh APP_PATH OUTPUT_DIR`:

```bash
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
ZIP="$OUTPUT_DIR/UltraController-$VERSION-arm64.zip"
DMG="$OUTPUT_DIR/UltraController-$VERSION-arm64.dmg"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP"
STAGING="$(mktemp -d)"
cp -R "$APP_PATH" "$STAGING/"
hdiutil create -volname "Ultra Controller" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
shasum -a 256 "$ZIP" "$DMG" > "$OUTPUT_DIR/SHA256SUMS"
rm -rf "$STAGING"
```

The package contains only the app; no installer scripts or background helpers.

- [ ] **Step 7: Add future App Store structural validation**

`validate-app-store-structure.sh APP_PATH` checks sandboxing, public bundle structure, extension embedding, no Developer ID-only updater/helper, no network entitlement, no external executable, and no executable code outside the expected app/extension binaries. It does not claim App Review approval.

When App Store distribution credentials exist, additionally run an App Store archive/export with `AppStore.plist` but do not upload it.

- [ ] **Step 8: Run script tests and commit**

```bash
bash apps/macos/UltraController/Tests/Scripts/verify_release_script_test.sh
shellcheck apps/macos/UltraController/Scripts/*.sh

git add apps/macos/UltraController/Config apps/macos/UltraController/Scripts apps/macos/UltraController/Tests/Scripts
git commit -m "build: add signed release verification pipeline"
```

If `shellcheck` is unavailable, install it as a development tool and record the version in `docs/release/v0.1.0-checklist.md`; it is not a runtime dependency.

### Task 5: Add notarization and stapling without storing credentials

**Files:**
- Create: `apps/macos/UltraController/Scripts/notarize.sh`
- Modify: `apps/macos/UltraController/Scripts/verify-release.sh`
- Create: `docs/release/notarization.md`

**Interfaces:**
- Consumes: Developer ID-signed ZIP/DMG, keychain profile name in `NOTARY_PROFILE`.
- Produces: accepted notarization result, stapled app/DMG, and post-notarization verification report.

- [ ] **Step 1: Document one-time local credential setup**

Create `docs/release/notarization.md`:

```bash
xcrun notarytool store-credentials "UltraControllerNotary" \
  --apple-id "$APPLE_ID" \
  --team-id "$DEVELOPMENT_TEAM" \
  --password "$APP_SPECIFIC_PASSWORD"
```

State that environment values and keychain material are never committed. The repository records only the profile name `UltraControllerNotary` as an example.

- [ ] **Step 2: Implement notarization script**

```bash
#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:?usage: notarize.sh app-path zip-path dmg-path}"
ZIP_PATH="${2:?missing zip path}"
DMG_PATH="${3:?missing dmg path}"
PROFILE="${NOTARY_PROFILE:?set NOTARY_PROFILE to a notarytool keychain profile}"

xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

xcrun notarytool submit "$DMG_PATH" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"
```

- [ ] **Step 3: Handle failures without hiding them**

On notary rejection, print the submission ID and fetch the log:

```bash
xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$PROFILE"
```

Do not staple or package a release after a rejected submission. Save the log outside Git unless it has been reviewed for sensitive metadata.

- [ ] **Step 4: Run a Developer ID dry run**

Before public distribution:

```bash
DEVELOPMENT_TEAM="$TEAM_ID" apps/macos/UltraController/Scripts/archive.sh
apps/macos/UltraController/Scripts/package.sh \
  build/ultra-controller/export/Ultra\ Controller.app \
  build/ultra-controller/artifacts
```

If Developer ID credentials are unavailable because this remains personal-only, record `Not run — no public distribution intended` in the release checklist. Do not claim notarization success.

- [ ] **Step 5: Run notarization when public distribution is chosen**

```bash
NOTARY_PROFILE=UltraControllerNotary \
apps/macos/UltraController/Scripts/notarize.sh \
  build/ultra-controller/export/Ultra\ Controller.app \
  build/ultra-controller/artifacts/UltraController-0.1.0-arm64.zip \
  build/ultra-controller/artifacts/UltraController-0.1.0-arm64.dmg
```

- [ ] **Step 6: Commit scripts/documentation**

```bash
git add apps/macos/UltraController/Scripts/notarize.sh docs/release/notarization.md
git commit -m "build: add optional Developer ID notarization"
```

### Task 6: Execute the complete physical and clean-install release checklist

**Files:**
- Create: `docs/release/v0.1.0-checklist.md`
- Modify: `CHANGELOG.md`
- Create: `docs/release/v0.1.0-release-notes.md`

**Interfaces:**
- Consumes: signed Release build, Gate A/B evidence, performance report, supported-firmware policy.
- Produces: signed-off v0.1.0 release record and user-facing release notes.

- [ ] **Step 1: Create the checklist with explicit evidence columns**

```markdown
# Ultra Controller v0.1.0 Release Checklist

## Build identity
| Check | Command/evidence | Result |

## Automated tests
| Suite | Command | Tests/failures | Result |

## Physical QC Ultra
| Scenario | Expected | Observed | Result |

## macOS lifecycle
| Scenario | Expected | Observed | Result |

## Accessibility and appearance
| Check | Evidence | Result |

## Privacy and security
| Check | Evidence | Result |

## Performance
| Metric | Target | Observed | Result |

## Signing and distribution
| Check | Evidence | Result |

## Known limitations
## Release decision
```

- [ ] **Step 2: Run all automated suites from a clean checkout/worktree**

```bash
cargo test --workspace
make macos-generate
git diff --exit-code -- apps/macos/UltraController/UltraController.xcodeproj
make macos-test-core
make macos-test
xcodebuild -project apps/macos/UltraController/UltraController.xcodeproj \
  -scheme UltraController \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Record exact test counts and zero failures. A command's exit 0 without test count is not enough; inspect the test summary.

- [ ] **Step 3: Run the physical headset matrix**

With the exact firmware listed in `supported-firmware.md`:

1. Fresh install and first Bluetooth permission.
2. Existing macOS audio pairing and app selection.
3. Unsupported Bose/BMAP candidate rejection if another test device is available; otherwise use the scripted integration test and record physical test unavailable.
4. Cold launch and saved-device retrieval.
5. Quiet, Aware, and every stored custom mode.
6. Spatial/Immersive states admitted to v1.
7. Standby values and restoration.
8. Every verified advanced field, Apply, reconnect, and persistence behavior.
9. Partial/rejected write presentation using the fake transport plus one safe physical rejection case when available.
10. Power Off expected disconnect and manual reconnect after powering on.
11. Out-of-range and return.
12. Bluetooth off/on.
13. Mac sleep/wake.
14. Bose app closed, recently used, and—only if safe—open.
15. Ten repeated reconnect cycles.

- [ ] **Step 4: Run app-surface and Control Center matrix**

- Desktop-first launch.
- Menu-bar-first launch.
- Window close/reopen.
- App menu-bar controls.
- Control Center and system-pinned controls in every Gate B-supported lifecycle state.
- Terminated-app fallback exactly as documented.
- Launch at login.
- Forget and re-onboard.
- Ensure all surfaces converge on one confirmed state.

- [ ] **Step 5: Run accessibility and appearance pass**

Use keyboard-only operation and VoiceOver through onboarding, Overview, Modes Apply/conflict/failure, Settings, menu bar, and Power Off confirmation. Check light/dark, increased contrast, reduced transparency, reduced motion, active/inactive windows, and system controls.

- [ ] **Step 6: Verify privacy/security and bundle contents**

Export a default support bundle and search for the physical peripheral UUID/serial/raw custom mode name. Expected: no match. Verify the app bundle has no network entitlement, Rust executable, debug probe, tests, raw physical fixture identifiers, or developer credentials.

- [ ] **Step 7: Perform a clean-install test**

Install the exported app into `/Applications` in a clean macOS user account or another supported Apple-silicon Mac. Verify Gatekeeper launch, Bluetooth permission, extension discovery, onboarding, essential controls, and removal/reinstall. For a public artifact, verify notarization without bypassing Gatekeeper.

- [ ] **Step 8: Finalize changelog and release notes**

Replace the `0.1.0` date in `CHANGELOG.md` with the actual release date only after all mandatory checks pass.

`v0.1.0-release-notes.md` includes:

- supported device, firmware, and macOS version
- essential features
- advanced fields actually admitted by Gate A
- Control Center lifecycle policy from Gate B
- privacy statement
- known limitations
- SHA-256 checksums for public artifacts when created
- independent/non-Bose notice

- [ ] **Step 9: Commit the completed release record**

```bash
! grep -E 'TBD|TODO|REPLACE_ME|PENDING' \
  docs/release/v0.1.0-checklist.md \
  docs/release/v0.1.0-release-notes.md \
  docs/release/performance-report.md

git add CHANGELOG.md docs/release
git commit -m "docs: complete Ultra Controller v0.1.0 release validation"
```

If a mandatory check fails, keep the version under `[Unreleased]`, document the failure, and do not make this commit with a passing release decision.

### Task 7: Run the final v1 checkpoint

**Files:**
- Verify all app, extension, documentation, scripts, and evidence files.

**Interfaces:**
- Produces: personal v1 build or optional signed/notarized GitHub Release candidate.

- [ ] **Step 1: Verify the repository and generated project are clean**

```bash
make macos-generate
git diff --exit-code -- apps/macos/UltraController/UltraController.xcodeproj
git status --short
```

Expected: generated project has no drift and tracked tree is clean.

- [ ] **Step 2: Run the complete automated verification**

```bash
cargo test --workspace
make macos-test-core
make macos-test
bash apps/macos/UltraController/Tests/Scripts/verify_release_script_test.sh
apps/macos/UltraController/Scripts/check-localized-strings.sh
```

Expected: zero failures and nonzero test counts.

- [ ] **Step 3: Archive and verify the Release app**

```bash
DEVELOPMENT_TEAM="$TEAM_ID" apps/macos/UltraController/Scripts/archive.sh
APP_PATH="build/ultra-controller/export/Ultra Controller.app"
apps/macos/UltraController/Scripts/verify-release.sh \
  "$APP_PATH" \
  build/ultra-controller/release-verification.json
apps/macos/UltraController/Scripts/validate-app-store-structure.sh "$APP_PATH"
```

Expected: every mandatory JSON check passes. When public distribution is not intended, notarization may be recorded as `not-applicable-personal-build`; code/signing/entitlement checks still pass.

- [ ] **Step 4: Confirm performance and physical evidence are final**

```bash
for file in \
  docs/protocol/qc-ultra-baseline-probe.md \
  docs/protocol/qc-ultra-advanced-mode-validation.md \
  docs/platform/control-center-lifecycle.md \
  docs/release/performance-report.md \
  docs/release/v0.1.0-checklist.md; do
  test -s "$file" || exit 1
  ! grep -E 'TBD|TODO|REPLACE_ME|PENDING' "$file" || exit 1
done
```

Expected: exit 0.

- [ ] **Step 5: Verify no forbidden architecture or dependency entered the bundle**

```bash
lipo -archs "$APP_PATH/Contents/MacOS/Ultra Controller" | grep -qx arm64
! find "$APP_PATH" -type f \( -name bozo -o -name bozod -o -name node -o -name cargo \) -print -quit | grep .
! codesign -d --entitlements :- "$APP_PATH" 2>/dev/null | grep -q 'com.apple.security.network.client'
! grep -R -E 'import CoreBluetooth|CBCentralManager' "$APP_PATH/Contents/PlugIns" 2>/dev/null
```

Expected: all checks exit 0.

- [ ] **Step 6: Package/notarize only when distribution is selected**

For personal use, install the signed app from the archive and stop. For GitHub distribution, package, notarize, staple, rerun `verify-release.sh`, and attach ZIP/DMG/checksums/release notes only after the release checklist's decision is `PASS`.

Plan 5 is complete only when the release record contains fresh command output and physical-device evidence; do not infer release readiness from earlier plan checkpoints.
