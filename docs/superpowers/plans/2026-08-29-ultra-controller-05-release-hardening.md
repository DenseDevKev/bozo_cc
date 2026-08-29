# Ultra Controller Release Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the feature-complete app into a privacy-reviewed, accessibility-tested, energy-profiled, signed/notarized, physically validated v1 candidate suitable for personal use or an optional GitHub Release.

**Architecture:** Hardening adds bounded privacy-aware diagnostics, explicit documentation, repeatable local verification, and evidence reports without changing the one-session architecture. Public artifacts come only from a clean Release archive, are checked for architecture/entitlements/contents, optionally notarized with credentials stored outside Git, and are tested in a clean user account or Mac.

**Tech Stack:** Swift 6, `os.Logger`, XCTest/XCUITest, Xcode 27, `xcodebuild`, `xctrace`, `codesign`, `otool`, `lipo`, `spctl`, `xcrun notarytool`, `xcrun stapler`, `ditto`, `hdiutil`, shell/Python scripts.

**Spec:** `docs/superpowers/specs/2026-08-29-qc-ultra-macos-controller-design.md`

## Global Constraints

- Plans 1–4 and both gate conclusions must pass before labeling v1 complete.
- Ship `arm64` only; minimum macOS 27.0.
- Keep App Sandbox; controls extension has App Group but no Bluetooth entitlement/code.
- No network entitlement, analytics, telemetry, crash upload, account, cloud, updater, helper, or downloaded executable code.
- Diagnostics are local, capped, redacted by default; raw protocol metadata requires explicit opt-in.
- Never package Rust binaries, TUI/daemon, XcodeGen, tests, fixtures, or Debug probes.
- Never commit Apple credentials, signing keys, notary passwords, keychain exports, or team secrets.
- Public copy states independent/non-affiliated Bose status.
- Public distribution is optional; personal signed builds are valid.
- Performance evidence targets: idle CPU median below 0.2%, desktop RSS below 80 MB, no app-created idle polling timer, Low energy unless an OS floor is documented and approved.

---

## File Map

| Path | Responsibility |
|---|---|
| `App/Diagnostics/Diagnostic*.swift` | Structured privacy-classified bounded events. |
| `App/Diagnostics/SupportBundleExporter.swift` | Explicit single-file sanitized support export. |
| `App/Settings/DiagnosticsSettingsView.swift` | Enable/export/clear diagnostics. |
| `docs/privacy.md` | Local-only privacy statement. |
| `THIRD_PARTY_NOTICES.md` | Bozo/bozo-bar MIT attribution. |
| `docs/support.md` | Supported scope and troubleshooting. |
| `docs/release/supported-firmware.md` | Exact validated firmware/profile policy. |
| `CHANGELOG.md` | Release history. |
| `Scripts/profile-*.sh` | Repeatable CPU/RSS/trace/reconnect evidence. |
| `Scripts/archive.sh` | Clean Release archive/export. |
| `Scripts/verify-release.sh` | Bundle/signing/entitlement/dependency checks. |
| `Scripts/package.sh` | ZIP/DMG/checksum output. |
| `Scripts/notarize.sh` | Optional notary/staple flow. |
| `Scripts/validate-app-store-structure.sh` | Future-store structural check, not submission. |
| `docs/release/performance-report.md` | Measured performance evidence. |
| `docs/release/v0.1.0-checklist.md` | Final automated/physical/accessibility/security record. |

### Task 1: Add bounded privacy-aware diagnostics and one-file support export

**Files:**
- Create: `apps/macos/UltraController/App/Diagnostics/DiagnosticCategory.swift`
- Create: `.../DiagnosticPrivacy.swift`
- Create: `.../DiagnosticEvent.swift`
- Create: `.../DiagnosticStore.swift`
- Create: `.../DiagnosticRedactor.swift`
- Create: `.../SupportBundle.swift`
- Create: `.../SupportBundleExporter.swift`
- Create: `apps/macos/UltraController/App/Settings/DiagnosticsSettingsView.swift`
- Modify: `apps/macos/UltraController/App/Settings/SettingsView.swift`
- Modify: `apps/macos/UltraController/App/Bluetooth/CoreBluetoothTransport.swift`
- Modify: `apps/macos/UltraController/App/Session/HeadphoneSession.swift`
- Modify: `apps/macos/UltraController/App/Intents/HeadphoneIntentController.swift`
- Test: `apps/macos/UltraController/Tests/Diagnostics/DiagnosticStoreTests.swift`
- Test: `.../DiagnosticRedactorTests.swift`
- Test: `.../SupportBundleExporterTests.swift`

**Interfaces:**
- Consumes: transport/session/intent lifecycle events.
- Produces: 500-event ring, privacy-safe unified logging, and a single sanitized `.ultracontroller-support.json` file saved explicitly by the user.

- [ ] **Step 1: Write bounded/redaction/export tests**

```swift
func testRingKeepsNewestFiveHundred() async {
    let store = DiagnosticStore(capacity: 500)
    for index in 0..<600 { await store.append(.test(index: index)) }
    let events = await store.snapshot()
    XCTAssertEqual(events.count, 500)
    XCTAssertEqual(events.first?.sequence, 100)
    XCTAssertEqual(events.last?.sequence, 599)
}

func testPeripheralUUIDIsRedacted() {
    XCTAssertEqual(
        DiagnosticRedactor.default.redact("123E4567-E89B-12D3-A456-426614174000 disconnected"),
        "<redacted-uuid> disconnected"
    )
}

func testDefaultSupportFileExcludesRawPayloadAndCustomNames() throws {
    let data = try SupportBundleExporter().encode(.fixture, includeRawProtocolMetadata: false)
    let text = String(decoding: data, as: UTF8.self)
    XCTAssertFalse(text.contains("DEADBEEF"))
    XCTAssertFalse(text.contains("Kevin Custom Mode"))
}
```

- [ ] **Step 2: Run and verify failure**

```bash
make macos-test
```

- [ ] **Step 3: Define diagnostics**

```swift
enum DiagnosticCategory: String, Codable, Sendable {
    case application, bluetooth, bmap, session, appIntents, persistence
}

enum DiagnosticPrivacy: String, Codable, Sendable {
    case normal, privateValue, rawProtocolMetadata
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

Store no CoreBluetooth objects/errors. Convert immediately to bounded value fields. `DiagnosticStore` is an actor with capacity 500 and `append/snapshot/clear`.

- [ ] **Step 4: Add privacy-aware unified logging**

One `Logger` per category. Release logs state transitions, operation/duration, and typed error class. UUID/serial/product IDs use private interpolation or are omitted. Raw packet payload is off by default. No continuous custom log file.

- [ ] **Step 5: Implement exact single-file support schema**

```swift
struct SupportBundle: Codable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let appVersion: String
    let appBuild: String
    let macOSVersion: String
    let architecture: String
    let headphoneFirmware: String?
    let connectionState: String
    let capabilities: SupportCapabilities
    let verifiedProfileSHA256: String?
    let rawProtocolMetadataIncluded: Bool
    let events: [DiagnosticEvent]
}
```

Exporter redacts UUID/serial/custom mode names, filters `.privateValue`, and filters `.rawProtocolMetadata` unless opted in. Save through `NSSavePanel` as `UltraController-Support-<UTC timestamp>.ultracontroller-support.json` using atomic `Data.write`. The shipped app invokes no shell/zip process.

- [ ] **Step 6: Add Diagnostics settings**

Hidden developer section: enable bounded detailed events; include raw metadata next export (off, warning); Export; Clear; event count/time range. No packet injection/upload.

- [ ] **Step 7: Run tests and commit**

```bash
make macos-test
git add apps/macos/UltraController/App/Diagnostics apps/macos/UltraController/App/Settings apps/macos/UltraController/App/Bluetooth/CoreBluetoothTransport.swift apps/macos/UltraController/App/Session/HeadphoneSession.swift apps/macos/UltraController/App/Intents/HeadphoneIntentController.swift apps/macos/UltraController/Tests/Diagnostics
git commit -m "feat: add private bounded diagnostics"
```

### Task 2: Complete privacy, attribution, support, firmware, and About documentation

**Files:**
- Modify: `README.md`
- Create: `THIRD_PARTY_NOTICES.md`
- Create: `docs/privacy.md`
- Create: `docs/support.md`
- Create: `docs/release/supported-firmware.md`
- Create: `CHANGELOG.md`
- Modify: `apps/macos/UltraController/project.yml`
- Modify: `apps/macos/UltraController/App/Settings/AboutView.swift`
- Modify: `apps/macos/UltraController/App/Resources/Localizable.xcstrings`
- Create: `apps/macos/UltraController/Tests/Documentation/BundledDocumentationTests.swift`

**Interfaces:**
- Consumes: actual final behavior/gate evidence.
- Produces: accurate repository and bundled copy.

- [ ] **Step 1: Write bundled-document tests**

Use a `BundledDocumentLoader(bundle:)` injected with `Bundle.main` in app and test fixture bundle in unit tests. Assert notices contain `NerdySouth/bozo`, `NerdySouth/bozo-bar`, `MIT License`; privacy contains `does not collect analytics or telemetry`.

- [ ] **Step 2: Update root README without replacing Rust documentation**

Add:

```markdown
## Ultra Controller for macOS
### Status
### Supported hardware and macOS
### Architecture and relationship to Bozo
### Building
### Privacy
### Distribution
### Project independence
```

State Bozo supplies protocol knowledge/fixtures; shipped app has no Rust runtime.

- [ ] **Step 3: Write notices/privacy/support/firmware policy**

`THIRD_PARTY_NOTICES.md`: upstream URLs/copyright/MIT, derived algorithms/files, no Bose artwork/proprietary/decompiled content distributed.

`docs/privacy.md`: local Bluetooth; no account/cloud/ads/analytics/telemetry/crash upload/mic/audio/history; local preferences/shared snapshot; optional export; clearing data; no network entitlement.

`docs/support.md`: permission, Bluetooth off, unavailable/busy controller, reconnect, forget/re-onboard, system-control fallback, support export.

`docs/release/supported-firmware.md`:

```markdown
# Supported Firmware
## Physically validated
| Generation | Firmware | Essential controls | Advanced fields | System-control policy | Evidence |
## Unknown firmware policy
- Essential reads must pass strict parsers and capability validation.
- Advanced editing is disabled without an exact profile.
- Unknown payloads fail closed.
```

Populate from Gate A/B.

- [ ] **Step 4: Create changelog without date placeholders**

```markdown
# Changelog

## [Unreleased]

## [0.1.0] - Unreleased
### Added
- Native desktop and app-menu-bar controller for QC Ultra Headphones Gen 1.
- Verified essential controls and Gate A-admitted advanced fields.
- macOS system controls according to the Gate B policy.
### Privacy
- Local-only operation with no account, analytics, telemetry, or required network.
```

Final release task replaces only the second `Unreleased` with the actual date.

- [ ] **Step 5: Bundle/present documentation**

Add notices/privacy/support as app resources. About shows version/build, sheets for each document, source link, and `Ultra Controller is an independent project and is not affiliated with or endorsed by Bose.`

- [ ] **Step 6: Run tests/commit**

```bash
make macos-generate
make macos-test
git add README.md THIRD_PARTY_NOTICES.md CHANGELOG.md docs/privacy.md docs/support.md docs/release/supported-firmware.md apps/macos/UltraController/project.yml apps/macos/UltraController/App/Settings/AboutView.swift apps/macos/UltraController/App/Resources/Localizable.xcstrings apps/macos/UltraController/Tests/Documentation
git commit -m "docs: add Ultra Controller privacy and attribution"
```

### Task 3: Add repeatable CPU, RSS, energy, leak, timer, and reconnect profiling

**Files:**
- Create: `apps/macos/UltraController/App/Diagnostics/PerformanceScenario.swift`
- Modify: `apps/macos/UltraController/App/Application/AppEnvironment.swift`
- Create: `apps/macos/UltraController/Scripts/profile-idle.sh`
- Create: `apps/macos/UltraController/Scripts/profile-reconnect.sh`
- Create: `apps/macos/UltraController/Scripts/summarize-process-samples.py`
- Create: `apps/macos/UltraController/Tests/Diagnostics/PerformanceScenarioTests.swift`
- Create: `docs/release/performance-report.md`

**Interfaces:**
- Consumes: Release app and deterministic launch arguments.
- Produces: ten-minute sample summaries, local traces, reconnect timing evidence, committed report.

- [ ] **Step 1: Add/test profiling scenarios**

```swift
enum PerformanceScenario: String {
    case idleWindowlessConnected, idleDesktopConnected, reconnectUnavailable
}
```

Parse only `--performance-scenario <known value>` in development/release-test builds; ordinary distribution ignores it. Tests verify known and unknown parsing.

- [ ] **Step 2: Implement idle sampler**

```bash
#!/usr/bin/env bash
set -euo pipefail
APP_PATH="${1:?usage: profile-idle.sh app-path output-dir scenario}"
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
python3 "$(dirname "$0")/summarize-process-samples.py" "$OUTPUT_DIR/process.csv" > "$OUTPUT_DIR/summary.json"
```

Record separate 60-second `xcrun xctrace record --template 'Time Profiler' --attach <PID>` plus Allocations/Leaks/Energy traces while the app is running; keep large traces local.

- [ ] **Step 3: Implement deterministic Python summary/test**

Output `samples`, CPU median/P95, RSS median/max MB using `statistics.median` and nearest-rank P95. Include `--self-test` with known CSV expected values.

- [ ] **Step 4: Implement reconnect timing script**

With selected headset unavailable for five minutes, export diagnostic timestamps and assert `1,2,5,10,30,30...` within scheduler tolerance and no overlap. Repeat sleep/wake. Script exits nonzero on overlap or sub-second loop.

- [ ] **Step 5: Run matrix/write report**

Profile windowless connected 10m, desktop connected 10m, unavailable 5m, ten reconnect cycles, and after system controls. `performance-report.md` records environment/commit/firmware, CPU/RSS/Energy, reconnect delays, leaks/retention, timer/wakeup audit, bundle size, deviations, conclusion. Populate all values before commit.

- [ ] **Step 6: Verify/commit**

```bash
chmod +x apps/macos/UltraController/Scripts/profile-idle.sh apps/macos/UltraController/Scripts/profile-reconnect.sh
python3 apps/macos/UltraController/Scripts/summarize-process-samples.py --self-test
make macos-test
! grep -E 'TBD|TODO|REPLACE_ME|PENDING' docs/release/performance-report.md
git add apps/macos/UltraController/Scripts apps/macos/UltraController/App/Diagnostics/PerformanceScenario.swift apps/macos/UltraController/App/Application/AppEnvironment.swift apps/macos/UltraController/Tests/Diagnostics/PerformanceScenarioTests.swift docs/release/performance-report.md
git commit -m "perf: profile Ultra Controller release behavior"
```

### Task 4: Add deterministic archive, bundle verification, packaging, and store-structure checks

**Files:**
- Modify: `apps/macos/UltraController/Config/Shared.xcconfig`
- Modify: `apps/macos/UltraController/project.yml`
- Create: `apps/macos/UltraController/Config/ExportOptions/DeveloperID.plist`
- Create: `.../AppStore.plist`
- Create: `apps/macos/UltraController/Scripts/archive.sh`
- Create: `.../verify-release.sh`
- Create: `.../package.sh`
- Create: `.../validate-app-store-structure.sh`
- Create: `apps/macos/UltraController/Tests/Scripts/verify_release_script_test.sh`

**Interfaces:**
- Consumes: clean Release source and externally supplied team/signing context.
- Produces: archive/export, ZIP/DMG/checksums, JSON verification report.

- [ ] **Step 1: Set explicit version/build/extension settings**

Ensure `MARKETING_VERSION = 0.1.0`, `CURRENT_PROJECT_VERSION = 1`; set `APPLICATION_EXTENSION_API_ONLY = YES` only on controls extension.

- [ ] **Step 2: Create export plists**

Developer ID uses method `developer-id`, automatic signing, strip Swift symbols. App Store uses method `app-store-connect`, automatic signing, upload symbols. If Xcode 27 emits different final method tokens, use the exact Organizer-generated token and record it in release checklist.

- [ ] **Step 3: Implement archive script**

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
APP_DIR="$ROOT/apps/macos/UltraController"
BUILD_DIR="$ROOT/build/ultra-controller"
TEAM_ID="${DEVELOPMENT_TEAM:?set DEVELOPMENT_TEAM}"
rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"
cd "$APP_DIR"
xcodegen generate --spec project.yml
xcodebuild clean archive -project UltraController.xcodeproj -scheme UltraController \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath "$BUILD_DIR/UltraController.xcarchive" \
  DEVELOPMENT_TEAM="$TEAM_ID" ARCHS=arm64 ONLY_ACTIVE_ARCH=NO
xcodebuild -exportArchive -archivePath "$BUILD_DIR/UltraController.xcarchive" \
  -exportPath "$BUILD_DIR/export" \
  -exportOptionsPlist Config/ExportOptions/DeveloperID.plist
```

- [ ] **Step 4: Implement mandatory `verify-release.sh APP REPORT`**

Checks/JSON statuses:

1. only arm64
2. strict deep codesign
3. expected app/extension bundle IDs
4. app sandbox+Bluetooth+App Group
5. extension sandbox+App Group and no Bluetooth
6. privacy/notices/support resources
7. exactly one expected `.appex`
8. no `bozo`, `bozod`, `cargo`, `node`, `xcodegen`, probe, tests
9. native/system/Swift dynamic libraries only
10. Gatekeeper status (`pending-notarization` before public notarization; pass afterward)

Exit nonzero for mandatory failure.

- [ ] **Step 5: Add verifier regression test**

`--filesystem-only` fake app with `bozod` must fail and report `forbiddenRuntimeFiles`; removing file passes filesystem checks.

- [ ] **Step 6: Implement packaging**

Use `ditto` ZIP, `hdiutil` UDZO DMG from a temporary staging folder containing only app, and SHA-256 file. No installer/helper.

- [ ] **Step 7: Implement store-structure validation**

Check sandbox, app group, embedded extension, no network/updater/helper/external executable/private framework. This claims structural readiness only, not App Review approval. When credentials exist, export an App Store archive without upload.

- [ ] **Step 8: Run scripts/commit**

```bash
bash apps/macos/UltraController/Tests/Scripts/verify_release_script_test.sh
shellcheck apps/macos/UltraController/Scripts/*.sh
git add apps/macos/UltraController/Config apps/macos/UltraController/project.yml apps/macos/UltraController/Scripts apps/macos/UltraController/Tests/Scripts
git commit -m "build: add signed release verification pipeline"
```

`ShellCheck` is development-only; record version if installed.

### Task 5: Add optional Developer ID notarization without repository credentials

**Files:**
- Create: `apps/macos/UltraController/Scripts/notarize.sh`
- Create: `docs/release/notarization.md`
- Modify: `apps/macos/UltraController/Scripts/verify-release.sh`

**Interfaces:**
- Consumes: signed ZIP/DMG, `NOTARY_PROFILE` keychain profile.
- Produces: accepted submission, stapled app/DMG, Gatekeeper pass.

- [ ] **Step 1: Document local credential setup**

```bash
xcrun notarytool store-credentials "UltraControllerNotary" \
  --apple-id "$APPLE_ID" --team-id "$DEVELOPMENT_TEAM" \
  --password "$APP_SPECIFIC_PASSWORD"
```

State values/keychain material are never committed.

- [ ] **Step 2: Implement script**

```bash
#!/usr/bin/env bash
set -euo pipefail
APP_PATH="${1:?usage: notarize.sh app zip dmg}"
ZIP_PATH="${2:?missing zip}"
DMG_PATH="${3:?missing dmg}"
PROFILE="${NOTARY_PROFILE:?set NOTARY_PROFILE}"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP_PATH"; xcrun stapler validate "$APP_PATH"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG_PATH"; xcrun stapler validate "$DMG_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"
```

Capture submission ID and fetch `notarytool log` on rejection; do not staple/release rejected output.

- [ ] **Step 3: Execute only when public distribution is selected**

For personal-only: release checklist states `Not run — no public artifact`, and does not claim notarization. For GitHub: archive, package, notarize, rerun verifier.

- [ ] **Step 4: Commit script/doc**

```bash
git add apps/macos/UltraController/Scripts/notarize.sh docs/release/notarization.md
git commit -m "build: add optional Developer ID notarization"
```

### Task 6: Execute complete physical, lifecycle, accessibility, privacy, and clean-install checklist

**Files:**
- Create: `docs/release/v0.1.0-checklist.md`
- Create: `docs/release/v0.1.0-release-notes.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: Release build, Gate A/B evidence, performance report.
- Produces: signed release decision and accurate release notes.

- [ ] **Step 1: Create evidence table structure**

Checklist sections: Build identity; Automated tests; Physical QC Ultra; macOS lifecycle; Accessibility/appearance; Privacy/security; Performance; Signing/distribution; Known limitations; Release decision. Every row has command/evidence, observed result, PASS/FAIL/NOT APPLICABLE with explanation.

- [ ] **Step 2: Run clean automated suite**

```bash
cargo test --workspace
make macos-generate
git diff --exit-code -- apps/macos/UltraController/UltraController.xcodeproj
make macos-test-core
make macos-test
xcodebuild -project apps/macos/UltraController/UltraController.xcodeproj \
  -scheme UltraController -configuration Release \
  -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build
```

Record exact test counts and zero failures.

- [ ] **Step 3: Run physical headset matrix**

Fresh permission/setup, saved retrieval, all modes, spatial, standby/restore, every Gate A field/restore, partial/rejection handling, Power Off/manual reconnect, out-of-range, Bluetooth off/on, sleep/wake, Bose app coexistence, ten reconnect cycles.

- [ ] **Step 4: Run all surfaces/system-control matrix**

Both launch modes, window close/reopen, app menu bar, Gate B system controls/states/fallback, launch at login, forget/re-onboard, one converged confirmed state.

- [ ] **Step 5: Run accessibility/appearance pass**

Keyboard and VoiceOver through onboarding/Overview/Modes Apply/conflict/failure/Settings/menu bar/Power confirmation; light/dark/increased contrast/reduced transparency/reduced motion/active-inactive windows/system controls.

- [ ] **Step 6: Verify privacy and clean install**

Default support export must not contain physical UUID/serial/raw payload/custom mode name. Bundle has no network entitlement/Rust/debug/tests/credentials. Install in clean macOS account or second supported Mac; verify Gatekeeper, Bluetooth permission, extension, onboarding/essential controls, remove/reinstall. Public artifact must pass without bypassing Gatekeeper.

- [ ] **Step 7: Finalize changelog/release notes**

Only after all mandatory PASS, replace `## [0.1.0] - Unreleased` with actual ISO date. Release notes list support/firmware/macOS, features, Gate A fields, Gate B policy, privacy, limitations, checksums if public, non-affiliation.

- [ ] **Step 8: Verify/commit release record**

```bash
! grep -E 'TBD|TODO|REPLACE_ME|PENDING' \
  docs/release/v0.1.0-checklist.md \
  docs/release/v0.1.0-release-notes.md \
  docs/release/performance-report.md
git add CHANGELOG.md docs/release
git commit -m "docs: complete Ultra Controller v0.1.0 release validation"
```

If mandatory failure remains, keep changelog Unreleased, document failure, and do not record PASS.

### Task 7: Run final v1 checkpoint

**Files:**
- Verify all app/extension/docs/scripts/evidence.

**Interfaces:**
- Produces: personal v1 app or optional notarized GitHub candidate.

- [ ] **Step 1: Verify clean generated tree**

```bash
make macos-generate
git diff --exit-code -- apps/macos/UltraController/UltraController.xcodeproj
git status --short
```

- [ ] **Step 2: Run complete automated verification**

```bash
cargo test --workspace
make macos-test-core
make macos-test
bash apps/macos/UltraController/Tests/Scripts/verify_release_script_test.sh
apps/macos/UltraController/Scripts/check-localized-strings.sh
```

- [ ] **Step 3: Archive and verify**

```bash
DEVELOPMENT_TEAM="$TEAM_ID" apps/macos/UltraController/Scripts/archive.sh
APP_PATH="build/ultra-controller/export/Ultra Controller.app"
apps/macos/UltraController/Scripts/verify-release.sh "$APP_PATH" build/ultra-controller/release-verification.json
apps/macos/UltraController/Scripts/validate-app-store-structure.sh "$APP_PATH"
```

Every mandatory JSON check passes. Personal build may mark notarization `notApplicablePersonalBuild`; all other signing/entitlement checks pass.

- [ ] **Step 4: Verify evidence is final**

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

- [ ] **Step 5: Verify architecture/forbidden contents**

```bash
lipo -archs "$APP_PATH/Contents/MacOS/Ultra Controller" | grep -qx arm64
! find "$APP_PATH" -type f \( -name bozo -o -name bozod -o -name node -o -name cargo \) -print -quit | grep .
! codesign -d --entitlements :- "$APP_PATH" 2>/dev/null | grep -q 'com.apple.security.network.client'
```

- [ ] **Step 6: Package/notarize only for selected distribution**

Personal: install signed app and stop. GitHub: package/notarize/staple/rerun verifier/attach ZIP+DMG+checksums+notes only after checklist PASS.

Plan 5 completes only with fresh command output and physical evidence; never infer release readiness from prior checkpoints.
