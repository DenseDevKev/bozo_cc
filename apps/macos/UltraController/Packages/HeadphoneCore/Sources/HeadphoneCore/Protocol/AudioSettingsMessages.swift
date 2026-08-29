public enum AudioSettingsMessages {
    private static let function: UInt8 = 0x0A

    public static func query() -> BMAPPacket {
        BMAPPacket(
            functionBlock: .audioModes,
            function: function,
            operator: .get
        )
    }

    public static func set(_ settings: AudioSettings) -> BMAPPacket {
        BMAPPacket(
            functionBlock: .audioModes,
            function: function,
            operator: .setGet,
            payload: [
                settings.cncLevel,
                settings.autoCNCEnabled ? 1 : 0,
                settings.spatialAudioMode.rawValue,
                settings.windBlockEnabled ? 1 : 0,
                settings.ancEnabled ? 1 : 0,
            ]
        )
    }

    public static func parse(_ packet: BMAPPacket) throws -> AudioSettings {
        try BMAPResponseValidator.validateStatus(
            packet,
            functionBlock: .audioModes,
            function: function
        )

        guard packet.payload.count == 5 else {
            throw BMAPResponseError.malformedPayload(
                expected: "exactly five live audio-settings bytes",
                actual: packet.payload.count
            )
        }

        guard let spatialAudioMode = SpatialAudioMode(rawValue: packet.payload[2]) else {
            throw BMAPResponseError.unsupportedValue(
                field: "spatialAudioMode",
                value: packet.payload[2]
            )
        }

        return AudioSettings(
            cncLevel: packet.payload[0],
            autoCNCEnabled: try BMAPResponseValidator.parseBoolean(
                packet.payload[1],
                field: "autoCNCEnabled"
            ),
            spatialAudioMode: spatialAudioMode,
            windBlockEnabled: try BMAPResponseValidator.parseBoolean(
                packet.payload[3],
                field: "windBlockEnabled"
            ),
            ancEnabled: try BMAPResponseValidator.parseBoolean(
                packet.payload[4],
                field: "ancEnabled"
            )
        )
    }
}
