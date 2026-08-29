import Foundation

public enum ProductMessages {
    private static let function: UInt8 = 0x02

    public static func queryName() -> BMAPPacket {
        BMAPPacket(
            functionBlock: .settings,
            function: function,
            operator: .get
        )
    }

    public static func parseName(_ packet: BMAPPacket) throws -> HeadphoneIdentity {
        try BMAPResponseValidator.validateStatus(
            packet,
            functionBlock: .settings,
            function: function
        )

        let bytes = packet.payload.filter { $0 != 0 }
        guard !bytes.isEmpty else {
            throw BMAPResponseError.malformedPayload(
                expected: "a non-empty UTF-8 product name",
                actual: packet.payload.count
            )
        }
        guard let name = String(bytes: bytes, encoding: .utf8) else {
            throw BMAPResponseError.invalidUTF8(field: "productName")
        }

        return HeadphoneIdentity(productName: name, rawPayload: packet.payload)
    }
}
