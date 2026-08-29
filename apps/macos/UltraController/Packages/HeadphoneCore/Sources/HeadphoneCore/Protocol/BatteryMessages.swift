public enum BatteryMessages {
    private static let function: UInt8 = 0x02

    public static func query() -> BMAPPacket {
        BMAPPacket(
            functionBlock: .status,
            function: function,
            operator: .get
        )
    }

    public static func parse(_ packet: BMAPPacket) throws -> [BatteryComponent] {
        try BMAPResponseValidator.validateStatus(
            packet,
            functionBlock: .status,
            function: function
        )

        guard !packet.payload.isEmpty, packet.payload.count.isMultiple(of: 4) else {
            throw BMAPResponseError.malformedPayload(
                expected: "one or more 4-byte battery components",
                actual: packet.payload.count
            )
        }

        var components: [BatteryComponent] = []
        components.reserveCapacity(packet.payload.count / 4)

        for offset in stride(from: 0, to: packet.payload.count, by: 4) {
            let percentage = packet.payload[offset]
            guard percentage <= 100 else {
                throw BMAPResponseError.unsupportedValue(
                    field: "batteryPercentage",
                    value: percentage
                )
            }

            let rawMinutes =
                (UInt16(packet.payload[offset + 1]) << 8) |
                UInt16(packet.payload[offset + 2])

            components.append(BatteryComponent(
                id: packet.payload[offset + 3],
                percentage: percentage,
                remainingMinutes: rawMinutes == 0xFFFF ? nil : rawMinutes
            ))
        }

        return components
    }
}
