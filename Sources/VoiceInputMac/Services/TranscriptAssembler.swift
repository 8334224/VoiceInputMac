import CoreMedia
import Foundation

actor TranscriptAssembler {
    struct Segment {
        let range: CMTimeRange
        let text: String
        let isFinal: Bool
    }

    private var segments: [Segment] = []

    func apply(range: CMTimeRange, text: String, isFinal: Bool) {
        segments.removeAll { existing in
            CMTimeRangeGetIntersection(existing.range, otherRange: range).duration.seconds > 0
        }
        segments.append(Segment(range: range, text: text, isFinal: isFinal))
        segments.sort { $0.range.start.seconds < $1.range.start.seconds }
    }

    func rendered(includeVolatile: Bool) -> String {
        segments
            .filter { includeVolatile || $0.isFinal }
            .map(\.text)
            .joined()
    }

    func clear() {
        segments.removeAll()
    }
}
