public struct BMAPPacket: Equatable, Codable, Sendable {
    private static let headerSize = 4

    public let functionBlock: BMAPFunctionBlock
    public let function: UInt8
    public let deviceID: UInt8
    public let port: UInt8
    public let `operator`: BMAPOperator
    public let payload: [UInt8]

    public init(
        functionBlock: BMAPFunctionBlock,
        function: UInt8,
        deviceID: UInt8 = 0,
        port: UInt8 = 0,
        `operator`: BMAPOperator,
        payload: [UInt8] = []
    ) {
        self.functionBlock = functionBlock
        self.function = function
        self.deviceID = deviceID
        self.port = port
        self.operator = `operator`
        self.payload = payload
    }

    public func encoded() throws -> [UInt8] {
        guard payload.count <= Int(UInt8.max) else {
            throw BMAPCodecError.payloadTooLong(payload.count)
        }
        guard deviceID <= 3 else {
            throw BMAPCodecError.deviceIDOutOfRange(deviceID)
        }
        guard port <= 3 else {
            throw BMAPCodecError.portOutOfRange(port)
        }

        let routingAndOperator =
            (deviceID << 6) |
            (port << 4) |
            (`operator`.rawValue & 0x0F)

        var bytes: [UInt8] = []
        bytes.reserveCapacity(Self.headerSize + payload.count)
        bytes.append(functionBlock.rawValue)
        bytes.append(function)
        bytes.append(routingAndOperator)
        bytes.append(UInt8(payload.count))
        bytes.append(contentsOf: payload)
        return bytes
    }

    public static func decode(_ bytes: [UInt8]) throws -> BMAPPacket {
        guard bytes.count >= headerSize else {
            throw BMAPCodecError.packetTooShort(actual: bytes.count)
        }

        guard let functionBlock = BMAPFunctionBlock(rawValue: bytes[0]) else {
            throw BMAPCodecError.unknownFunctionBlock(bytes[0])
        }

        let routingAndOperator = bytes[2]
        let rawOperator = routingAndOperator & 0x0F
        guard let `operator` = BMAPOperator(rawValue: rawOperator) else {
            throw BMAPCodecError.unknownOperator(rawOperator)
        }

        let expectedPayloadLength = Int(bytes[3])
        let actualPayloadLength = bytes.count - headerSize
        guard actualPayloadLength == expectedPayloadLength else {
            throw BMAPCodecError.payloadLengthMismatch(
                expected: expectedPayloadLength,
                actual: actualPayloadLength
            )
        }

        return BMAPPacket(
            functionBlock: functionBlock,
            function: bytes[1],
            deviceID: routingAndOperator >> 6,
            port: (routingAndOperator >> 4) & 0x03,
            operator: `operator`,
            payload: Array(bytes[headerSize...])
        )
    }

    public static func decodeMany(_ bytes: [UInt8]) throws -> [BMAPPacket] {
        var packets: [BMAPPacket] = []
        var offset = 0

        while offset < bytes.count {
            let remaining = bytes.count - offset
            guard remaining >= headerSize else {
                throw BMAPCodecError.packetTooShort(actual: remaining)
            }

            let payloadLength = Int(bytes[offset + 3])
            let packetLength = headerSize + payloadLength
            guard remaining >= packetLength else {
                throw BMAPCodecError.payloadLengthMismatch(
                    expected: payloadLength,
                    actual: remaining - headerSize
                )
            }

            let packetBytes = Array(bytes[offset..<(offset + packetLength)])
            packets.append(try decode(packetBytes))
            offset += packetLength
        }

        return packets
    }
}
