public struct HeadphoneIdentity: Sendable, Codable, Equatable {
    public let productName: String
    public let rawPayload: [UInt8]

    public init(productName: String, rawPayload: [UInt8]) {
        self.productName = productName
        self.rawPayload = rawPayload
    }
}
