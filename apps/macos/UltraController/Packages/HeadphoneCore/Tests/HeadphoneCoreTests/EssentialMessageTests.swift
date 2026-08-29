import XCTest
@testable import HeadphoneCore

final class EssentialMessageTests: XCTestCase {
    func testEssentialRequestBytes() throws {
        XCTAssertEqual(try ProductMessages.queryName().encoded(), [0x01, 0x02, 0x01, 0x00])
        XCTAssertEqual(try BatteryMessages.query().encoded(), [0x02, 0x02, 0x01, 0x00])
        XCTAssertEqual(try StandbyMessages.query().encoded(), [0x01, 0x04, 0x01, 0x00])
        XCTAssertEqual(try StandbyMessages.set(minutes: 30).encoded(), [0x01, 0x04, 0x02, 0x01, 0x1E])
        XCTAssertEqual(try AudioModeMessages.queryAll().encoded(), [0x1F, 0x01, 0x01, 0x00])
        XCTAssertEqual(try AudioModeMessages.queryCapabilities().encoded(), [0x1F, 0x02, 0x01, 0x00])
        XCTAssertEqual(try AudioModeMessages.queryCurrent().encoded(), [0x1F, 0x03, 0x01, 0x00])
        XCTAssertEqual(try AudioModeMessages.queryConfiguration(index: 2).encoded(), [0x1F, 0x06, 0x01, 0x01, 0x02])
        XCTAssertEqual(try AudioModeMessages.setCurrent(index: 2).encoded(), [0x1F, 0x03, 0x05, 0x02, 0x02, 0x00])
        XCTAssertEqual(try SpatialAudioMessages.query().encoded(), [0x05, 0x0F, 0x01, 0x00])
        XCTAssertEqual(try SpatialAudioMessages.set(.motion).encoded(), [0x05, 0x0F, 0x02, 0x01, 0x02])
        XCTAssertEqual(try PowerMessages.powerOff().encoded(), [0x07, 0x04, 0x05, 0x01, 0x00])
    }

    func testProductNameParserTrimsNullFraming() throws {
        let packet = BMAPPacket(
            functionBlock: .settings,
            function: 0x02,
            operator: .status,
            payload: [0x00] + Array("Bose QuietComfort Ultra Headphones".utf8) + [0x00]
        )

        let identity = try ProductMessages.parseName(packet)
        XCTAssertEqual(identity.productName, "Bose QuietComfort Ultra Headphones")
        XCTAssertEqual(identity.rawPayload, packet.payload)
    }

    func testBatteryParser() throws {
        let packet = BMAPPacket(
            functionBlock: .status,
            function: 0x02,
            operator: .status,
            payload: [85, 0x01, 0x2C, 0]
        )

        XCTAssertEqual(try BatteryMessages.parse(packet), [
            BatteryComponent(id: 0, percentage: 85, remainingMinutes: 300),
        ])
    }

    func testUnknownBatteryRuntimeUsesNil() throws {
        let packet = BMAPPacket(
            functionBlock: .status,
            function: 0x02,
            operator: .status,
            payload: [85, 0xFF, 0xFF, 0]
        )

        XCTAssertEqual(try BatteryMessages.parse(packet).first?.remainingMinutes, nil)
    }

    func testIncompleteBatteryComponentIsRejected() {
        let packet = BMAPPacket(
            functionBlock: .status,
            function: 0x02,
            operator: .status,
            payload: [85, 0x01, 0x2C]
        )

        XCTAssertThrowsError(try BatteryMessages.parse(packet)) { error in
            XCTAssertEqual(
                error as? BMAPResponseError,
                .malformedPayload(expected: "one or more 4-byte battery components", actual: 3)
            )
        }
    }

    func testDeviceErrorIsSurfacedBeforeParsingPayload() {
        let packet = BMAPPacket(
            functionBlock: .audioModes,
            function: 0x02,
            operator: .error,
            payload: [0x0C]
        )

        XCTAssertThrowsError(try AudioModeMessages.parseCapabilities(packet)) { error in
            XCTAssertEqual(error as? BMAPResponseError, .device(code: 0x0C, detail: nil))
        }
    }
}
