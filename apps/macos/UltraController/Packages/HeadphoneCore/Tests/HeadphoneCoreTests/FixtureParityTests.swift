import XCTest
@testable import HeadphoneCore

final class FixtureParityTests: XCTestCase {
    func testManifestFixturesMatchSwiftCodec() throws {
        let manifest = try FixtureLoader.decode(FixtureManifest.self, named: "manifest.json")
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertFalse(manifest.fixtures.isEmpty)

        for filename in manifest.fixtures {
            let fixture = try FixtureLoader.decode(PacketFixture.self, named: filename)
            let wire = try fixture.wireHex.fixtureHexBytes()
            let packet = try BMAPPacket.decode(wire)

            XCTAssertEqual(packet.functionBlock.rawValue, fixture.expected.functionBlock, fixture.name)
            XCTAssertEqual(packet.function, fixture.expected.function, fixture.name)
            XCTAssertEqual(packet.operator.rawValue, fixture.expected.operator, fixture.name)
            XCTAssertEqual(packet.payload, try fixture.expected.payloadHex.fixtureHexBytes(), fixture.name)
            XCTAssertEqual(try packet.encoded(), wire, fixture.name)
        }
    }

    func testHexDecoderRejectsOddLength() {
        XCTAssertThrowsError(try "ABC".fixtureHexBytes()) { error in
            XCTAssertEqual(error as? FixtureHexError, .oddLength(3))
        }
    }

    func testHexDecoderRejectsInvalidByte() {
        XCTAssertThrowsError(try "0G".fixtureHexBytes()) { error in
            XCTAssertEqual(error as? FixtureHexError, .invalidByte("0G"))
        }
    }
}
