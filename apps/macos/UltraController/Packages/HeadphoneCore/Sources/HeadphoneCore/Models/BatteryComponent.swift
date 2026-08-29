public struct BatteryComponent: Sendable, Codable, Equatable, Identifiable {
    public let id: UInt8
    public let percentage: UInt8
    public let remainingMinutes: UInt16?

    public init(id: UInt8, percentage: UInt8, remainingMinutes: UInt16?) {
        self.id = id
        self.percentage = percentage
        self.remainingMinutes = remainingMinutes
    }
}
