import XCTest
@testable import HeadphoneCore

final class BMAPPacketTests: XCTestCase {
    func testBatteryQueryEncodingMatchesRust() throws {
        let packet = BMAPPacket(
            functionBlock: .status,
            function: 0x02,
            operator: .get,
            payload: []
        )

        XCTAssertEqual(try packet.encoded(), [0x02, 0x02, 0x01, 0x00])
    }

    func testPowerOffEncodingMatchesRust() throws {
        let packet = BMAPPacket(
            functionBlock: .control,
            function: 0x04,
            operator: .start,
            payload: [0x00]
        )

        XCTAssertEqual(try packet.encoded(), [0x07, 0x04, 0x05, 0x01, 0x00])
    }

    func testRoundTripPreservesDeviceAndPort() throws {
        let packet = BMAPPacket(
            functionBlock: .status,
            function: 0x02,
            deviceID: 2,
            port: 1,
            operator: .status,
            payload: [85, 0x01, 0x2C, 0x00]
        )

        XCTAssertEqual(try BMAPPacket.decode(packet.encoded()), packet)
    }

    func testDecodeRejectsTruncatedPayload() {
        XCTAssertThrowsError(
            try BMAPPacket.decode([0x01, 0x05, 0x02, 0x05, 0xAA, 0xBB])
        ) { error in
            XCTAssertEqual(
                error as? BMAPCodecError,
                .payloadLengthMismatch(expected: 5, actual: 2)
            )
        }
    }

    func testDecodeRejectsUnknownFunctionBlock() {
        XCTAssertThrowsError(
            try BMAPPacket.decode([0xFE, 0x00, 0x01, 0x00])
        ) { error in
            XCTAssertEqual(error as? BMAPCodecError, .unknownFunctionBlock(0xFE))
        }
    }

    func testDecodeRejectsUnknownOperator() {
        XCTAssertThrowsError(
            try BMAPPacket.decode([0x02, 0x02, 0x0F, 0x00])
        ) { error in
            XCTAssertEqual(error as? BMAPCodecError, .unknownOperator(0x0F))
        }
    }

    func testDecodeManyParsesConcatenatedPackets() throws {
        let packets = try BMAPPacket.decodeMany([
            0x02, 0x02, 0x01, 0x00,
            0x01, 0x05, 0x01, 0x00,
        ])

        XCTAssertEqual(packets.map(\.functionBlock), [.status, .settings])
    }

    func testDecodeManyRejectsTrailingPartialPacket() {
        XCTAssertThrowsError(
            try BMAPPacket.decodeMany([
                0x02, 0x02, 0x01, 0x00,
                0x01, 0x05,
            ])
        ) { error in
            XCTAssertEqual(error as? BMAPCodecError, .packetTooShort(actual: 2))
        }
    }

    func testEncodingRejectsPayloadLargerThanOneByteLength() {
        let packet = BMAPPacket(
            functionBlock: .settings,
            function: 0x02,
            operator: .set,
            payload: [UInt8](repeating: 0, count: 256)
        )

        XCTAssertThrowsError(try packet.encoded()) { error in
            XCTAssertEqual(error as? BMAPCodecError, .payloadTooLong(256))
        }
    }
}
