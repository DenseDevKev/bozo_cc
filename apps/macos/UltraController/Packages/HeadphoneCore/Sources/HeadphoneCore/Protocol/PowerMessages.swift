public enum PowerMessages {
    private static let function: UInt8 = 0x04

    public static func powerOff() -> BMAPPacket {
        power(value: 0x00)
    }

    public static func powerOn() -> BMAPPacket {
        power(value: 0x01)
    }

    private static func power(value: UInt8) -> BMAPPacket {
        BMAPPacket(
            functionBlock: .control,
            function: function,
            operator: .start,
            payload: [value]
        )
    }
}
