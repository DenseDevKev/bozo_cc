public enum BMAPResponseError: Error, Equatable, Sendable {
    case unexpectedMessage(
        expectedFunctionBlock: BMAPFunctionBlock,
        expectedFunction: UInt8,
        actualFunctionBlock: BMAPFunctionBlock,
        actualFunction: UInt8
    )
    case unexpectedOperator(expected: BMAPOperator, actual: BMAPOperator)
    case device(code: UInt8, detail: UInt8?)
    case malformedPayload(expected: String, actual: Int)
    case invalidUTF8(field: String)
    case unsupportedValue(field: String, value: UInt8)
}

enum BMAPResponseValidator {
    static func validateStatus(
        _ packet: BMAPPacket,
        functionBlock: BMAPFunctionBlock,
        function: UInt8
    ) throws {
        guard packet.functionBlock == functionBlock, packet.function == function else {
            throw BMAPResponseError.unexpectedMessage(
                expectedFunctionBlock: functionBlock,
                expectedFunction: function,
                actualFunctionBlock: packet.functionBlock,
                actualFunction: packet.function
            )
        }

        if packet.operator == .error {
            throw BMAPResponseError.device(
                code: packet.payload.first ?? 0x00,
                detail: packet.payload.count > 1 ? packet.payload[1] : nil
            )
        }

        guard packet.operator == .status else {
            throw BMAPResponseError.unexpectedOperator(
                expected: .status,
                actual: packet.operator
            )
        }
    }

    static func parseBoolean(_ value: UInt8, field: String) throws -> Bool {
        switch value {
        case 0: false
        case 1: true
        default: throw BMAPResponseError.unsupportedValue(field: field, value: value)
        }
    }
}
