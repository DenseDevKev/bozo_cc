import Foundation

// MARK: - Leaf types matching bozo-proto IPC

struct BatteryInfo: Codable {
    let percentage: UInt8
    let remainingMinutes: UInt16?
    let componentId: UInt8

    enum CodingKeys: String, CodingKey {
        case percentage
        case remainingMinutes = "remaining_minutes"
        case componentId = "component_id"
    }
}

struct CncState: Codable {
    let currentStep: UInt8
    let totalSteps: UInt8
    let enabled: Bool
    let userEnableDisable: Bool

    enum CodingKeys: String, CodingKey {
        case currentStep = "current_step"
        case totalSteps = "total_steps"
        case enabled
        case userEnableDisable = "user_enable_disable"
    }
}

struct AudioModeInfo: Codable, Identifiable {
    let modeIndex: UInt8
    let name: String
    var id: UInt8 { modeIndex }

    enum CodingKeys: String, CodingKey {
        case modeIndex = "mode_index"
        case name
    }
}

struct HeadphoneState: Codable {
    var connected: Bool = false
    var productName: String? = nil
    var battery: [BatteryInfo] = []
    var cnc: CncState? = nil
    var audioModeIndex: UInt8? = nil
    var audioModes: [AudioModeInfo] = []
    var standbyTimerMinutes: UInt8? = nil

    enum CodingKeys: String, CodingKey {
        case connected
        case productName = "product_name"
        case battery, cnc
        case audioModeIndex = "audio_mode_index"
        case audioModes = "audio_modes"
        case standbyTimerMinutes = "standby_timer_minutes"
    }
}

// MARK: - IpcRequest (adjacently tagged: "type" + optional "data")

enum IpcRequest {
    case getState
    case setAudioMode(modeIndex: UInt8)
    case setStandbyTimer(minutes: UInt8)
    case powerOff
    case reconnect
    case disconnect
}

extension IpcRequest: Encodable {
    private enum RootKeys: String, CodingKey { case type, data }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: RootKeys.self)
        switch self {
        case .getState:
            try c.encode("GetState", forKey: .type)
        case .setAudioMode(let idx):
            try c.encode("SetAudioMode", forKey: .type)
            try c.encode(["mode_index": idx], forKey: .data)
        case .setStandbyTimer(let min):
            try c.encode("SetStandbyTimer", forKey: .type)
            try c.encode(["minutes": min], forKey: .data)
        case .powerOff:
            try c.encode("PowerOff", forKey: .type)
        case .reconnect:
            try c.encode("Reconnect", forKey: .type)
        case .disconnect:
            try c.encode("Disconnect", forKey: .type)
        }
    }
}

// MARK: - IpcResponse (adjacently tagged: "type" + optional "data")

enum IpcResponse {
    case state(HeadphoneState)
    case stateUpdate(StateUpdate)
    case error(String)
    case ok
}

extension IpcResponse: Decodable {
    private enum RootKeys: String, CodingKey { case type, data }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: RootKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "State":
            self = .state(try c.decode(HeadphoneState.self, forKey: .data))
        case "StateUpdate":
            self = .stateUpdate(try c.decode(StateUpdate.self, forKey: .data))
        case "Error":
            let payload = try c.decode([String: String].self, forKey: .data)
            self = .error(payload["message"] ?? "unknown error")
        case "Ok":
            self = .ok
        default:
            self = .ok // ignore unknown types
        }
    }
}

// MARK: - StateUpdate (internally tagged: "field")

enum StateUpdate {
    case connection(Bool)
    case battery([BatteryInfo])
    case cnc(CncState)
    case audioMode(UInt8)
    case audioModeDiscovered(AudioModeInfo)
    case standbyTimer(UInt8)
    case productName(String)
}

extension StateUpdate: Decodable {
    private enum FieldKey: String, CodingKey { case field }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: FieldKey.self)
        let field = try c.decode(String.self, forKey: .field)

        // Re-decode the same container with field-specific keys
        switch field {
        case "Connection":
            let v = try ConnectionPayload(from: decoder)
            self = .connection(v.connected)
        case "Battery":
            let v = try BatteryPayload(from: decoder)
            self = .battery(v.info)
        case "Cnc":
            let v = try CncState(from: decoder)
            self = .cnc(v)
        case "AudioMode":
            let v = try AudioModePayload(from: decoder)
            self = .audioMode(v.modeIndex)
        case "AudioModeDiscovered":
            let v = try AudioModeInfo(from: decoder)
            self = .audioModeDiscovered(v)
        case "StandbyTimer":
            let v = try StandbyTimerPayload(from: decoder)
            self = .standbyTimer(v.minutes)
        case "ProductName":
            let v = try ProductNamePayload(from: decoder)
            self = .productName(v.name)
        default:
            self = .connection(false) // fallback
        }
    }

    // Helper structs for decoding internally-tagged payloads
    private struct ConnectionPayload: Decodable { let connected: Bool }
    private struct BatteryPayload: Decodable { let info: [BatteryInfo] }
    private struct AudioModePayload: Decodable {
        let modeIndex: UInt8
        enum CodingKeys: String, CodingKey { case modeIndex = "mode_index" }
    }
    private struct StandbyTimerPayload: Decodable { let minutes: UInt8 }
    private struct ProductNamePayload: Decodable { let name: String }
}
