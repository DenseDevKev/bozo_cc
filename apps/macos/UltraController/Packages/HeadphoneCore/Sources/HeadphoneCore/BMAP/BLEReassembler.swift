public struct BLEReassembler: Sendable {
    private var expectedMaximumIndex: Int?
    private var segments: [Int: [UInt8]] = [:]

    public init() {}

    public mutating func feed(_ segment: [UInt8]) throws -> [UInt8]? {
        guard let header = segment.first else {
            reset()
            throw BLEFramingError.emptySegment
        }

        if header == 0x00 {
            let data = Array(segment.dropFirst())
            reset()
            return data
        }

        let maximumIndex = Int((header >> 4) & 0x0F)
        let currentIndex = Int(header & 0x0F)

        guard currentIndex <= maximumIndex else {
            reset()
            throw BLEFramingError.indexOutOfRange(
                index: currentIndex,
                maximum: maximumIndex
            )
        }

        if let expectedMaximumIndex, expectedMaximumIndex != maximumIndex {
            let expected = expectedMaximumIndex
            reset()
            throw BLEFramingError.inconsistentMaximumIndex(
                expected: expected,
                actual: maximumIndex
            )
        }

        expectedMaximumIndex = maximumIndex
        let data = Array(segment.dropFirst())

        if let existing = segments[currentIndex] {
            guard existing == data else {
                reset()
                throw BLEFramingError.conflictingDuplicate(index: currentIndex)
            }
        } else {
            segments[currentIndex] = data
        }

        guard segments.count == maximumIndex + 1 else {
            return nil
        }

        var reassembled: [UInt8] = []
        for index in 0...maximumIndex {
            guard let bytes = segments[index] else {
                return nil
            }
            reassembled.append(contentsOf: bytes)
        }

        reset()
        return reassembled
    }

    private mutating func reset() {
        expectedMaximumIndex = nil
        segments.removeAll(keepingCapacity: true)
    }
}
