public enum BLEFramingError: Error, Equatable, Sendable {
    case emptySegment
    case tooManySegments(Int)
    case inconsistentMaximumIndex(expected: Int, actual: Int)
    case indexOutOfRange(index: Int, maximum: Int)
    case conflictingDuplicate(index: Int)
}
