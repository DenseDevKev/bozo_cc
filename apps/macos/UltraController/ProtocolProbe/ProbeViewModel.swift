import Combine
import Foundation
import HeadphoneCore

final class ProbeViewModel: ObservableObject {
    struct State: Equatable {
        var status = "Initializing Bluetooth…"
        var rows: [ProbeRow] = []
        var candidates: [ProbeCandidate] = []
        var isConnected = false
        var identity: HeadphoneIdentity?
        var identityConfirmedForSafeWrites = false
        var battery: [BatteryComponent] = []
        var capabilities: AudioModeCapabilities?
        var modeIDs: [UInt8] = []
        var currentModeID: UInt8?
        var audioModes: [AudioMode] = []
        var standbyMinutes: UInt8?
        var spatialAudioMode: SpatialAudioMode?

        var canConfirmSafeWrites: Bool {
            guard let productName = identity?.productName else { return false }
            return productName.localizedCaseInsensitiveContains("QuietComfort Ultra") ||
                productName.localizedCaseInsensitiveContains("QC Ultra")
        }

        var canUseSafeWrites: Bool {
            isConnected && canConfirmSafeWrites && identityConfirmedForSafeWrites
        }

        mutating func reduce(_ event: ProbeEvent) {
            switch event {
            case .scanReset:
                candidates.removeAll()
                status = "Scanning…"
                append(title: "Scan", detail: "Started")

            case let .bluetooth(message):
                status = message
                append(title: "Bluetooth", detail: message)

            case let .scanStopped(message):
                status = message
                append(title: "Scan", detail: message)

            case let .discovered(name, idSuffix, rssi):
                let candidate = ProbeCandidate(name: name, idSuffix: idSuffix, rssi: rssi)
                if let existingIndex = candidates.firstIndex(where: { $0.idSuffix == idSuffix }) {
                    candidates[existingIndex] = candidate
                } else {
                    candidates.append(candidate)
                }
                append(
                    title: "Discovered",
                    detail: "\(name) • …\(idSuffix) • \(Self.formatRSSI(rssi))"
                )

            case let .connecting(name):
                status = "Connecting to \(name)…"
                append(title: "Connecting", detail: name)

            case let .connected(name):
                isConnected = true
                status = "Connected to \(name)"
                append(title: "Connected", detail: name)

            case let .disconnected(message):
                isConnected = false
                identityConfirmedForSafeWrites = false
                status = message
                append(title: "Disconnected", detail: message)

            case let .channelReady(channel):
                status = "BMAP channel ready"
                append(title: "Channel", detail: channel)

            case let .packet(direction, summary, hex):
                append(title: direction.rowTitle, detail: "\(summary) • \(hex)")

            case let .identity(value):
                identity = value
                identityConfirmedForSafeWrites = false
                status = value.productName
                append(title: "Identity", detail: value.productName)

            case let .safeWritesConfirmed(value):
                identityConfirmedForSafeWrites = value && canConfirmSafeWrites
                append(
                    title: "Safe Writes",
                    detail: identityConfirmedForSafeWrites ? "Explicitly enabled" : "Disabled"
                )

            case let .battery(value):
                battery = value
                append(title: "Battery", detail: Self.formatBattery(value))

            case let .capabilities(value):
                capabilities = value
                append(
                    title: "Capabilities",
                    detail: "\(value.boseModeCount) Bose • \(value.userModeCount) user"
                )

            case let .modes(value):
                modeIDs = value
                append(title: "Mode IDs", detail: value.map(String.init).joined(separator: ", "))

            case let .currentMode(value):
                currentModeID = value
                append(title: "Current Mode", detail: String(value))

            case let .modeConfiguration(value):
                if let existingIndex = audioModes.firstIndex(where: { $0.id == value.id }) {
                    audioModes[existingIndex] = value
                } else {
                    audioModes.append(value)
                    audioModes.sort { $0.id < $1.id }
                }
                append(title: "Mode \(value.id)", detail: value.name)

            case let .standby(value):
                standbyMinutes = value
                append(title: "Standby", detail: value == 0 ? "Never" : "\(value) min")

            case let .spatialAudio(value):
                spatialAudioMode = value
                append(title: "Spatial Audio", detail: Self.spatialTitle(value))

            case let .error(message):
                status = message
                append(title: "Error", detail: message)
            }
        }

        func sanitizedTranscript() -> String {
            (["Status: \(status)"] + rows.map { "\($0.title): \($0.detail)" })
                .joined(separator: "\n")
        }

        private mutating func append(title: String, detail: String) {
            rows.append(ProbeRow(title: title, detail: detail))
        }

        private static func formatRSSI(_ rssi: Int) -> String {
            if rssi < 0 {
                return "−\(abs(rssi)) dBm"
            }
            return "\(rssi) dBm"
        }

        private static func formatBattery(_ components: [BatteryComponent]) -> String {
            guard let primary = components.first else { return "No components" }
            if let remainingMinutes = primary.remainingMinutes {
                return "\(primary.percentage)% • \(remainingMinutes) min"
            }
            return "\(primary.percentage)%"
        }

        static func spatialTitle(_ mode: SpatialAudioMode) -> String {
            switch mode {
            case .off: "Off"
            case .still: "Still"
            case .motion: "Motion"
            }
        }
    }

    @Published private(set) var state = State()

    func handle(_ event: ProbeEvent) {
        state.reduce(event)
    }
}
