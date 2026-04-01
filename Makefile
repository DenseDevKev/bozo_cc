APP = target/debug/bundle/osx/bozo.app
BIN = $(APP)/Contents/MacOS/bozo
DAEMON_BIN = $(APP)/Contents/MacOS/bozod
RELEASE_APP = target/release/bundle/osx/bozo.app
RELEASE_BIN = $(RELEASE_APP)/Contents/MacOS/bozo
RELEASE_DAEMON_BIN = $(RELEASE_APP)/Contents/MacOS/bozod

BAR_APP = bozo-bar/.build/BozoBar.app
BAR_BIN = $(BAR_APP)/Contents/MacOS/BozoBar
BAR_DAEMON = $(BAR_APP)/Contents/MacOS/bozod

.PHONY: build release run scan debug test clean grant-bluetooth bar bar-release bar-run

# Rust TUI
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

# Swift menu bar app (needs clean env to avoid devenv SDK conflict)
SWIFT_ENV = env -i HOME=$(HOME) PATH="/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin" DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"

bar: bar-bundle

bar-bundle:
	$(SWIFT_ENV) /bin/bash -c "cd bozo-bar && swift build"
	cargo build -p bozod
	mkdir -p $(BAR_APP)/Contents/MacOS $(BAR_APP)/Contents/Resources
	cp bozo-bar/.build/debug/BozoBar $(BAR_BIN)
	cp bozo-bar/Info.plist $(BAR_APP)/Contents/
	cp target/debug/bozod $(BAR_DAEMON)

bar-release:
	$(SWIFT_ENV) /bin/bash -c "cd bozo-bar && swift build -c release"
	cargo build -p bozod --release
	mkdir -p $(BAR_APP)/Contents/MacOS $(BAR_APP)/Contents/Resources
	cp bozo-bar/.build/release/BozoBar $(BAR_BIN)
	cp bozo-bar/Info.plist $(BAR_APP)/Contents/
	cp target/release/bozod $(BAR_DAEMON)

bar-run: bar
	open $(BAR_APP)

grant-bluetooth: bar
	@echo "Launching BozoBar.app to trigger Bluetooth permission dialog..."
	@echo "Please click 'Allow' when prompted."
	open $(BAR_APP)

test:
	cargo test

clean:
	cargo clean
	cd bozo-bar && swift package clean
