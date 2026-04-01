APP = target/debug/bundle/osx/bozo.app
BIN = $(APP)/Contents/MacOS/bozo
DAEMON_BIN = $(APP)/Contents/MacOS/bozod
RELEASE_APP = target/release/bundle/osx/bozo.app
RELEASE_BIN = $(RELEASE_APP)/Contents/MacOS/bozo
RELEASE_DAEMON_BIN = $(RELEASE_APP)/Contents/MacOS/bozod

.PHONY: build release run scan debug test clean grant-bluetooth


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

clean:
	cargo clean
