import XCTest
@testable import HeadphoneCore

final class BLEFramingTests: XCTestCase {
    func testSingleSegmentUsesZeroHeader() throws {
        let data: [UInt8] = [0x01, 0x05, 0x02, 0x02, 0x05, 0x01]
        XCTAssertEqual(try BLESegmenter.segment(data), [[0x00] + data])
    }

    func testEmptyPayloadStillProducesFramingByte() throws {
        XCTAssertEqual(try BLESegmenter.segment([]), [[0x00]])
    }

    func testTwentyFiveBytesUseTwoSegments() throws {
        let segments = try BLESegmenter.segment([UInt8](repeating: 0xBB, count: 25))
        XCTAssertEqual(segments.compactMap(\.first), [0x10, 0x11])
        XCTAssertEqual(segments.map(\.count), [20, 7])
    }

    func testSixteenSegmentsAreRepresentable() throws {
        let data = [UInt8](repeating: 0xCC, count: 19 * 16)
        let segments = try BLESegmenter.segment(data)
        XCTAssertEqual(segments.count, 16)
        XCTAssertEqual(segments.first?.first, 0xF0)
        XCTAssertEqual(segments.last?.first, 0xFF)
    }

    func testMoreThanSixteenSegmentsAreRejected() {
        let data = [UInt8](repeating: 0, count: 19 * 16 + 1)
        XCTAssertThrowsError(try BLESegmenter.segment(data)) { error in
            XCTAssertEqual(error as? BLEFramingError, .tooManySegments(17))
        }
    }

    func testOutOfOrderSegmentsReassemble() throws {
        let data = [UInt8](0..<30)
        let segments = try BLESegmenter.segment(data)
        var reassembler = BLEReassembler()

        XCTAssertNil(try reassembler.feed(segments[1]))
        XCTAssertEqual(try reassembler.feed(segments[0]), data)
    }

    func testExactDuplicateIsIdempotent() throws {
        let data = [UInt8](0..<30)
        let segments = try BLESegmenter.segment(data)
        var reassembler = BLEReassembler()

        XCTAssertNil(try reassembler.feed(segments[0]))
        XCTAssertNil(try reassembler.feed(segments[0]))
        XCTAssertEqual(try reassembler.feed(segments[1]), data)
    }

    func testConflictingDuplicateResetsStream() throws {
        var reassembler = BLEReassembler()
        _ = try reassembler.feed([0x10, 0xAA])

        XCTAssertThrowsError(try reassembler.feed([0x10, 0xBB])) { error in
            XCTAssertEqual(error as? BLEFramingError, .conflictingDuplicate(index: 0))
        }

        XCTAssertEqual(try reassembler.feed([0x00, 0x42]), [0x42])
    }

    func testInconsistentMaximumIndexResetsStream() throws {
        var reassembler = BLEReassembler()
        _ = try reassembler.feed([0x20, 0xAA])

        XCTAssertThrowsError(try reassembler.feed([0x11, 0xBB])) { error in
            XCTAssertEqual(
                error as? BLEFramingError,
                .inconsistentMaximumIndex(expected: 2, actual: 1)
            )
        }

        XCTAssertEqual(try reassembler.feed([0x00, 0x42]), [0x42])
    }

    func testEmptySegmentIsRejectedAndStateResets() throws {
        var reassembler = BLEReassembler()
        _ = try reassembler.feed([0x10, 0xAA])

        XCTAssertThrowsError(try reassembler.feed([])) { error in
            XCTAssertEqual(error as? BLEFramingError, .emptySegment)
        }

        XCTAssertEqual(try reassembler.feed([0x00, 0x42]), [0x42])
    }
}
