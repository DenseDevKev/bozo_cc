APP = target/debug/bundle/osx/bozo.app
BIN = $(APP)/Contents/MacOS/bozo
DAEMON_BIN = $(APP)/Contents/MacOS/bozod
RELEASE_APP = target/release/bundle/osx/bozo.app
RELEASE_BIN = $(RELEASE_APP)/Contents/MacOS/bozo
RELEASE_DAEMON_BIN = $(RELEASE_APP)/Contents/MacOS/bozod

ULTRA_DIR = apps/macos/UltraController
ULTRA_PROJECT = $(ULTRA_DIR)/UltraController.xcodeproj
ULTRA_DESTINATION ?= platform=macOS,arch=arm64
ULTRA_TEST_DEPLOYMENT_TARGET ?=
ULTRA_TEST_DEPLOYMENT_OVERRIDE = $(if $(ULTRA_TEST_DEPLOYMENT_TARGET),MACOSX_DEPLOYMENT_TARGET=$(ULTRA_TEST_DEPLOYMENT_TARGET),)

.PHONY: build release run scan debug test clean grant-bluetooth \
	macos-generate macos-build macos-test macos-test-core macos-probe-build macos-probe-verify-plist macos-probe

build:
	cargo build -p bozod -p bozo
	cd crates/bozo && cargo bundle
	cp target/debug/bozod $(DAEMON_BIN)

release:
	cargo build -p bozod -p bozo --release
	cd crates/bozo && cargo bundle --release
	cp target/release/bozod $(RELEASE_DAEMON_BIN)

run: build
	RUST_LOG=bozod=info $(BIN)

scan:
	cargo build -p bozod
	RUST_LOG=bozod=info target/debug/bozod --scan-only

debug: build
	RUST_LOG=bozod=debug $(BIN)

grant-bluetooth: build
	@echo "Launching bozo.app to trigger Bluetooth permission dialog..."
	@echo "Please click 'Allow' when prompted."
	open $(APP)

test:
	cargo test

macos-generate:
	cd $(ULTRA_DIR) && xcodegen generate --spec project.yml

macos-test-core:
	cd $(ULTRA_DIR)/Packages/HeadphoneCore && swift test

macos-build: macos-generate
	xcodebuild -project $(ULTRA_PROJECT) \
		-scheme UltraController \
		-configuration Debug \
		-destination '$(ULTRA_DESTINATION)' \
		CODE_SIGNING_ALLOWED=NO \
		build

macos-test: macos-generate
	xcodebuild -project $(ULTRA_PROJECT) \
		-scheme UltraController \
		-configuration Debug \
		-destination '$(ULTRA_DESTINATION)' \
		CODE_SIGNING_ALLOWED=NO \
		$(ULTRA_TEST_DEPLOYMENT_OVERRIDE) \
		test

macos-probe-build: macos-generate
	xcodebuild -project $(ULTRA_PROJECT) \
		-scheme UltraControllerProtocolProbe \
		-configuration Debug \
		-destination '$(ULTRA_DESTINATION)' \
		CODE_SIGNING_ALLOWED=NO \
		build

macos-probe-verify-plist: macos-probe-build
	@PLIST=$$(find $(HOME)/Library/Developer/Xcode/DerivedData -path '*UltraControllerProtocolProbe.app/Contents/Info.plist' -print -quit); \
	if [ -z "$$PLIST" ]; then echo "Probe Info.plist not found"; exit 1; fi; \
	VALUE=$$(/usr/libexec/PlistBuddy -c 'Print :NSBluetoothAlwaysUsageDescription' "$$PLIST" 2>/dev/null || true); \
	if [ -z "$$VALUE" ]; then echo "Built probe is missing NSBluetoothAlwaysUsageDescription"; exit 1; fi; \
	echo "Verified built probe Bluetooth usage description: $$VALUE"

macos-probe: macos-generate
	xcodebuild -project $(ULTRA_PROJECT) \
		-scheme UltraControllerProtocolProbe \
		-configuration Debug \
		-destination '$(ULTRA_DESTINATION)' \
		build
	open $(HOME)/Library/Developer/Xcode/DerivedData/UltraController-*/Build/Products/Debug/UltraControllerProtocolProbe.app

clean:
	cargo clean
	rm -rf $(ULTRA_DIR)/build
