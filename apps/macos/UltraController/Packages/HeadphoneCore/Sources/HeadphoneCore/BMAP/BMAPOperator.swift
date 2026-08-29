public enum BMAPOperator: UInt8, CaseIterable, Codable, Sendable {
    case set = 0
    case get = 1
    case setGet = 2
    case status = 3
    case error = 4
    case start = 5
    case result = 6
    case processing = 7

    public var isCommand: Bool {
        switch self {
        case .set, .get, .setGet, .start:
            true
        case .status, .error, .result, .processing:
            false
        }
    }

    public var isResponse: Bool { !isCommand }
}
