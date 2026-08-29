import XCTest
@testable import HeadphoneCore

final class ProtocolParserTests: XCTestCase {
    func testAudioModeCapabilitiesParser() throws {
        let packet = BMAPPacket(
            functionBlock: .audioModes,
            function: 0x02,
            operator: .status,
            payload: [2, 3, 0, 0, 0, 0b0011_1111, 1]
        )

        let value = try AudioModeMessages.parseCapabilities(packet)
        XCTAssertEqual(value.boseModeCount, 2)
        XCTAssertEqual(value.userModeCount, 3)
        XCTAssertTrue(value.supportsCNC)
        XCTAssertTrue(value.supportsAutoCNC)
        XCTAssertTrue(value.supportsSpatialAudio)
        XCTAssertTrue(value.supportsWindBlock)
        XCTAssertTrue(value.supportsFavorites)
        XCTAssertTrue(value.supportsANCToggle)
        XCTAssertEqual(value.minimumFavoriteCount, 1)
    }

    func testCurrentModeParser() throws {
        let current = BMAPPacket(
            functionBlock: .audioModes,
            function: 0x03,
            operator: .status,
            payload: [4]
        )

        XCTAssertEqual(try AudioModeMessages.parseCurrent(current), 4)
    }

    func testAudioModeSnapshotUsesStartOperator() throws {
        XCTAssertEqual(
            try AudioModeMessages.querySnapshot().encoded(),
            [0x1F, 0x01, 0x05, 0x00]
        )
    }

    func testModeConfigPreservesOpaqueBytes() throws {
        var payload = [UInt8](repeating: 0, count: 48)
        payload[0] = 2
        payload[2] = 12
        payload[3] = 1
        payload[4] = 1
        payload[5] = 1
        Array("Music".utf8).enumerated().forEach { payload[6 + $0.offset] = $0.element }
        payload[38] = 0xA1
        payload[39] = 0xB2
        payload[40] = 0xC3
        payload[41] = 0b0001_1111
        payload[42] = 7
        payload[43] = 1
        payload[44] = 2
        payload[45] = 0xD4
        payload[46] = 1
        payload[47] = 1

        let packet = BMAPPacket(
            functionBlock: .audioModes,
            function: 0x06,
            operator: .status,
            payload: payload
        )
        let mode = try AudioModeMessages.parseConfiguration(packet)

        XCTAssertEqual(mode.id, 2)
        XCTAssertEqual(mode.promptID, 12)
        XCTAssertEqual(mode.name, "Music")
        XCTAssertTrue(mode.isUserConfigurable)
        XCTAssertTrue(mode.isUserConfigured)
        XCTAssertTrue(mode.isFavorite)
        XCTAssertEqual(mode.cncLevel, 7)
        XCTAssertEqual(mode.autoCNCEnabled, true)
        XCTAssertEqual(mode.spatialAudioMode, .motion)
        XCTAssertEqual(mode.windBlockEnabled, true)
        XCTAssertEqual(mode.ancEnabled, true)
        XCTAssertEqual(mode.opaqueReservedBytes, [0xA1, 0xB2, 0xC3, 0xD4])
        XCTAssertEqual(mode.rawPayload, payload)
    }

    func testModeConfigRejectsNonBooleanField() {
        var payload = [UInt8](repeating: 0, count: 48)
        payload[0] = 2
        payload[3] = 1
        payload[41] = 0b0000_0010
        payload[43] = 2
        let packet = BMAPPacket(
            functionBlock: .audioModes,
            function: 0x06,
            operator: .status,
            payload: payload
        )

        XCTAssertThrowsError(try AudioModeMessages.parseConfiguration(packet)) { error in
            XCTAssertEqual(
                error as? BMAPResponseError,
                .unsupportedValue(field: "autoCNCEnabled", value: 2)
            )
        }
    }

    func testAudioSettingsQueryUsesAudioModesSettingsConfigAddress() throws {
        XCTAssertEqual(
            try AudioSettingsMessages.query().encoded(),
            [0x1F, 0x0A, 0x01, 0x00]
        )
    }

    func testAudioSettingsParserReadsFiveByteLiveState() throws {
        let packet = BMAPPacket(
            functionBlock: .audioModes,
            function: 0x0A,
            operator: .status,
            payload: [7, 0, 2, 1, 1]
        )

        let settings = try AudioSettingsMessages.parse(packet)
        XCTAssertEqual(settings.cncLevel, 7)
        XCTAssertFalse(settings.autoCNCEnabled)
        XCTAssertEqual(settings.spatialAudioMode, .motion)
        XCTAssertTrue(settings.windBlockEnabled)
        XCTAssertTrue(settings.ancEnabled)
    }

    func testAudioSettingsSetGetPreservesNonSpatialFields() throws {
        let current = AudioSettings(
            cncLevel: 7,
            autoCNCEnabled: false,
            spatialAudioMode: .off,
            windBlockEnabled: true,
            ancEnabled: true
        )
        let updated = current.replacingSpatialAudioMode(.still)

        XCTAssertEqual(
            try AudioSettingsMessages.set(updated).encoded(),
            [0x1F, 0x0A, 0x02, 0x05, 7, 0, 1, 1, 1]
        )
    }

    func testAudioSettingsRejectsUnknownSpatialValue() {
        let packet = BMAPPacket(
            functionBlock: .audioModes,
            function: 0x0A,
            operator: .status,
            payload: [7, 0, 3, 1, 1]
        )

        XCTAssertThrowsError(try AudioSettingsMessages.parse(packet)) { error in
            XCTAssertEqual(
                error as? BMAPResponseError,
                .unsupportedValue(field: "spatialAudioMode", value: 3)
            )
        }
    }

    func testParserRejectsWrongResponseOperator() {
        let packet = BMAPPacket(
            functionBlock: .settings,
            function: 0x04,
            operator: .result,
            payload: [30]
        )

        XCTAssertThrowsError(try StandbyMessages.parse(packet)) { error in
            XCTAssertEqual(
                error as? BMAPResponseError,
                .unexpectedOperator(expected: .status, actual: .result)
            )
        }
    }
}
