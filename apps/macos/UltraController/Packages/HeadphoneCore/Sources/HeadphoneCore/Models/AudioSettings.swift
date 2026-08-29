public struct AudioSettings: Equatable, Sendable, Codable {
    public let cncLevel: UInt8
    public let autoCNCEnabled: Bool
    public let spatialAudioMode: SpatialAudioMode
    public let windBlockEnabled: Bool
    public let ancEnabled: Bool

    public init(
        cncLevel: UInt8,
        autoCNCEnabled: Bool,
        spatialAudioMode: SpatialAudioMode,
        windBlockEnabled: Bool,
        ancEnabled: Bool
    ) {
        self.cncLevel = cncLevel
        self.autoCNCEnabled = autoCNCEnabled
        self.spatialAudioMode = spatialAudioMode
        self.windBlockEnabled = windBlockEnabled
        self.ancEnabled = ancEnabled
    }

    public func replacingSpatialAudioMode(_ mode: SpatialAudioMode) -> AudioSettings {
        AudioSettings(
            cncLevel: cncLevel,
            autoCNCEnabled: autoCNCEnabled,
            spatialAudioMode: mode,
            windBlockEnabled: windBlockEnabled,
            ancEnabled: ancEnabled
        )
    }
}
