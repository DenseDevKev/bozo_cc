public struct AudioMode: Sendable, Codable, Equatable, Identifiable {
    public let id: UInt8
    public let promptID: UInt8
    public let isUserConfigurable: Bool
    public let isUserConfigured: Bool
    public let isFavorite: Bool
    public let name: String
    public let mutableFieldMask: UInt8
    public let cncLevel: UInt8?
    public let autoCNCEnabled: Bool?
    public let spatialAudioMode: SpatialAudioMode?
    public let windBlockEnabled: Bool?
    public let ancEnabled: Bool?
    public let opaqueReservedBytes: [UInt8]
    public let rawPayload: [UInt8]

    public init(
        id: UInt8,
        promptID: UInt8,
        isUserConfigurable: Bool,
        isUserConfigured: Bool,
        isFavorite: Bool,
        name: String,
        mutableFieldMask: UInt8,
        cncLevel: UInt8?,
        autoCNCEnabled: Bool?,
        spatialAudioMode: SpatialAudioMode?,
        windBlockEnabled: Bool?,
        ancEnabled: Bool?,
        opaqueReservedBytes: [UInt8],
        rawPayload: [UInt8]
    ) {
        self.id = id
        self.promptID = promptID
        self.isUserConfigurable = isUserConfigurable
        self.isUserConfigured = isUserConfigured
        self.isFavorite = isFavorite
        self.name = name
        self.mutableFieldMask = mutableFieldMask
        self.cncLevel = cncLevel
        self.autoCNCEnabled = autoCNCEnabled
        self.spatialAudioMode = spatialAudioMode
        self.windBlockEnabled = windBlockEnabled
        self.ancEnabled = ancEnabled
        self.opaqueReservedBytes = opaqueReservedBytes
        self.rawPayload = rawPayload
    }
}
