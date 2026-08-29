public enum BMAPCodecError: Error, Equatable, Sendable {
    case packetTooShort(actual: Int)
    case unknownFunctionBlock(UInt8)
    case unknownOperator(UInt8)
    case payloadTooLong(Int)
    case payloadLengthMismatch(expected: Int, actual: Int)
    case deviceIDOutOfRange(UInt8)
    case portOutOfRange(UInt8)
}

extension BMAPCodecError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .packetTooShort(actual):
            "BMAP packet needs at least four bytes; received \(actual)."
        case let .unknownFunctionBlock(value):
            "Unknown BMAP function block 0x\(String(value, radix: 16))."
        case let .unknownOperator(value):
            "Unknown BMAP operator 0x\(String(value, radix: 16))."
        case let .payloadTooLong(actual):
            "BMAP payload exceeds the one-byte length field: \(actual) bytes."
        case let .payloadLengthMismatch(expected, actual):
            "BMAP payload length mismatch: expected \(expected), received \(actual)."
        case let .deviceIDOutOfRange(value):
            "BMAP device ID must fit in two bits; received \(value)."
        case let .portOutOfRange(value):
            "BMAP port must fit in two bits; received \(value)."
        }
    }
}
