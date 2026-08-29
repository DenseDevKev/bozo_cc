import HeadphoneCore

struct ProbeCandidate: Equatable, Sendable, Identifiable {
    let name: String
    let idSuffix: String
    let rssi: Int

    var id: String { idSuffix }
}

struct ProbeRow: Equatable, Sendable, Identifiable {
    let title: String
    let detail: String

    var id: String { "\(title)\u{001F}\(detail)" }
}

enum ProbePacketDirection: String, Sendable {
    case sent
    case received

    var rowTitle: String {
        switch self {
        case .sent: "Sent"
        case .received: "Received"
        }
    }
}

enum ProbeEvent: Sendable {
    case scanReset
    case bluetooth(String)
    case scanStopped(String)
    case discovered(name: String, idSuffix: String, rssi: Int)
    case connecting(String)
    case connected(String)
    case disconnected(String)
    case channelReady(String)
    case packet(direction: ProbePacketDirection, summary: String, hex: String)
    case identity(HeadphoneIdentity)
    case safeWritesConfirmed(Bool)
    case battery([BatteryComponent])
    case capabilities(AudioModeCapabilities)
    case modes([UInt8])
    case currentMode(UInt8)
    case modeConfiguration(AudioMode)
    case standby(UInt8)
    case spatialAudio(SpatialAudioMode)
    case error(String)
}
