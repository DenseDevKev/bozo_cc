public struct AudioModeCapabilities: Sendable, Codable, Equatable {
    public let boseModeCount: UInt8
    public let userModeCount: UInt8
    public let supportsCNC: Bool
    public let supportsAutoCNC: Bool
    public let supportsSpatialAudio: Bool
    public let supportsWindBlock: Bool
    public let supportsFavorites: Bool
    public let supportsANCToggle: Bool
    public let minimumFavoriteCount: UInt8?

    public init(
        boseModeCount: UInt8,
        userModeCount: UInt8,
        supportsCNC: Bool,
        supportsAutoCNC: Bool,
        supportsSpatialAudio: Bool,
        supportsWindBlock: Bool,
        supportsFavorites: Bool,
        supportsANCToggle: Bool,
        minimumFavoriteCount: UInt8?
    ) {
        self.boseModeCount = boseModeCount
        self.userModeCount = userModeCount
        self.supportsCNC = supportsCNC
        self.supportsAutoCNC = supportsAutoCNC
        self.supportsSpatialAudio = supportsSpatialAudio
        self.supportsWindBlock = supportsWindBlock
        self.supportsFavorites = supportsFavorites
        self.supportsANCToggle = supportsANCToggle
        self.minimumFavoriteCount = minimumFavoriteCount
    }
}
