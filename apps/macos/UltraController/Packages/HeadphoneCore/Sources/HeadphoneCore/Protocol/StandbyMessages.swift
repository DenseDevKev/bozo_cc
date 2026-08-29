public enum StandbyMessages {
    private static let function: UInt8 = 0x04

    public static func query() -> BMAPPacket {
        BMAPPacket(
            functionBlock: .settings,
            function: function,
            operator: .get
        )
    }

    public static func set(minutes: UInt8) -> BMAPPacket {
        BMAPPacket(
            functionBlock: .settings,
            function: function,
            operator: .setGet,
            payload: [minutes]
        )
    }

    public static func parse(_ packet: BMAPPacket) throws -> UInt8 {
        try BMAPResponseValidator.validateStatus(
            packet,
            functionBlock: .settings,
            function: function
        )

        guard let minutes = packet.payload.first else {
            throw BMAPResponseError.malformedPayload(
                expected: "at least one standby-minute byte",
                actual: 0
            )
        }
        return minutes
    }
}
