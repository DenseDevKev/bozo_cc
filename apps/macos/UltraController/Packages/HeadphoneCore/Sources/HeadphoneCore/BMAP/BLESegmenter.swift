public enum BLESegmenter {
    public static let dataBytesPerSegment = 19
    public static let maximumSegmentCount = 16

    public static func segment(_ data: [UInt8]) throws -> [[UInt8]] {
        let chunks: [[UInt8]]

        if data.isEmpty {
            chunks = [[]]
        } else {
            chunks = stride(from: 0, to: data.count, by: dataBytesPerSegment).map { start in
                let end = min(start + dataBytesPerSegment, data.count)
                return Array(data[start..<end])
            }
        }

        guard chunks.count <= maximumSegmentCount else {
            throw BLEFramingError.tooManySegments(chunks.count)
        }

        let maximumIndex = UInt8(chunks.count - 1)
        return chunks.enumerated().map { index, chunk in
            [(maximumIndex << 4) | UInt8(index)] + chunk
        }
    }
}
