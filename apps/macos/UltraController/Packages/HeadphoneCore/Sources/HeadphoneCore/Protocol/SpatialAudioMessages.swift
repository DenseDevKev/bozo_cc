public enum SpatialAudioMessages {
    private static let function: UInt8 = 0x0F

    public static func query() -> BMAPPacket {
        BMAPPacket(
            functionBlock: .audioManagement,
            function: function,
            operator: .get
        )
    }

    public static func set(_ mode: SpatialAudioMode) -> BMAPPacket {
        BMAPPacket(
            functionBlock: .audioManagement,
            function: function,
            operator: .setGet,
            payload: [mode.rawValue]
        )
    }

    public static func parse(_ packet: BMAPPacket) throws -> SpatialAudioMode {
        try BMAPResponseValidator.validateStatus(
            packet,
            functionBlock: .audioManagement,
            function: function
        )

        guard packet.payload.count == 1, let rawValue = packet.payload.first else {
            throw BMAPResponseError.malformedPayload(
                expected: "exactly one spatial-audio byte",
                actual: packet.payload.count
            )
        }
        guard let mode = SpatialAudioMode(rawValue: rawValue) else {
            throw BMAPResponseError.unsupportedValue(
                field: "spatialAudioMode",
                value: rawValue
            )
        }
        return mode
    }
}
