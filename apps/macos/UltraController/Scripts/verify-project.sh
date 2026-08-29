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
