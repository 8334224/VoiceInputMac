import Foundation

struct ReRecognitionPlan: Identifiable, Equatable, Sendable {
    let id: String
    let segmentIDs: [String]
    let originalText: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let triggerFlags: [SuspicionFlag]
    let priority: Int
    let reasons: [String]
}

struct ReRecognitionPlanner {
    struct Configuration: Sendable {
        let triggerCodes: Set<String>
        let mergeGapThreshold: TimeInterval
        let expansionBefore: TimeInterval
        let expansionAfter: TimeInterval
        let maxPlansPerSession: Int
        let minPriority: Int
        let maxWindowDuration: TimeInterval

        static let `default` = Configuration(
            triggerCodes: [
                "hotword_miss",
                "partial_final_jump",
                "heavy_local_correction",
                "english_abbreviation",
                "number_unit_format",
                "cn_function_word_confusion",
                "hotword_context_anomaly",
                "short_window_low_fluency",
                "cn_content_word_confusion",
                "cn_phrase_split_anomaly",
                "hotword_phrase_split_anomaly",
                "cn_suffix_split_anomaly"
            ],
            mergeGapThreshold: 0.35,
            expansionBefore: 0.30,
            expansionAfter: 0.35,
            maxPlansPerSession: 2,
            minPriority: 2,
            maxWindowDuration: 4.5
        )
    }

    private struct Candidate: Sendable {
        let segment: TranscriptSegment
        let triggerFlags: [SuspicionFlag]
        let priority: Int
    }

    private let configuration: Configuration

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    func makePlans(from segments: [TranscriptSegment], audioDuration: TimeInterval?) -> [ReRecognitionPlan] {
        let candidates = segments.compactMap(makeCandidate(from:))
        guard !candidates.isEmpty else { return [] }

        let mergedCandidates = mergeCandidates(candidates, audioDuration: audioDuration)
        return Array(
            mergedCandidates
                .filter { $0.priority >= configuration.minPriority }
                .sorted { lhs, rhs in
                    if lhs.priority == rhs.priority {
                        return lhs.startTime < rhs.startTime
                    }
                    return lhs.priority > rhs.priority
                }
                .prefix(configuration.maxPlansPerSession)
        )
    }

    private func makeCandidate(from segment: TranscriptSegment) -> Candidate? {
        let triggerFlags = segment.suspicionFlags.filter { configuration.triggerCodes.contains($0.code) }
        guard !triggerFlags.isEmpty else { return nil }

        let priority = triggerFlags.reduce(into: 0) { partialResult, flag in
            partialResult += max(1, flag.severity)
            if flag.code == "hotword_miss" || flag.code == "partial_final_jump" {
                partialResult += 1
            }
        }

        return Candidate(segment: segment, triggerFlags: triggerFlags, priority: priority)
    }

    private func mergeCandidates(_ candidates: [Candidate], audioDuration: TimeInterval?) -> [ReRecognitionPlan] {
        let sorted = candidates.sorted { $0.segment.startTime < $1.segment.startTime }
        var groups: [[Candidate]] = []

        for candidate in sorted {
            if let lastGroup = groups.indices.last,
               let lastCandidate = groups[lastGroup].last,
               candidate.segment.startTime - lastCandidate.segment.endTime <= configuration.mergeGapThreshold {
                groups[lastGroup].append(candidate)
            } else {
                groups.append([candidate])
            }
        }

        return groups.compactMap { group in
            guard let first = group.first, let last = group.last else { return nil }

            let rawStart = first.segment.startTime
            let rawEnd = last.segment.endTime
            let startTime = max(0, rawStart - configuration.expansionBefore)
            var endTime = rawEnd + configuration.expansionAfter

            if let audioDuration {
                endTime = min(endTime, audioDuration)
            }

            if endTime - startTime > configuration.maxWindowDuration {
                endTime = min(startTime + configuration.maxWindowDuration, audioDuration ?? (startTime + configuration.maxWindowDuration))
            }

            if endTime <= startTime {
                return nil
            }

            let allFlags = deduplicated(group.flatMap(\.triggerFlags))
            let priority = group.reduce(0) { $0 + $1.priority }
            let originalText = group
                .map(\.segment.text)
                .joined(separator: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let reasons = allFlags.map(\.detail)
            let id = group.map(\.segment.id).joined(separator: "|")

            return ReRecognitionPlan(
                id: id,
                segmentIDs: group.map(\.segment.id),
                originalText: originalText,
                startTime: startTime,
                endTime: endTime,
                triggerFlags: allFlags,
                priority: priority,
                reasons: reasons
            )
        }
    }

    private func deduplicated(_ flags: [SuspicionFlag]) -> [SuspicionFlag] {
        var seen: Set<String> = []
        return flags.filter { flag in
            let key = "\(flag.code)|\(flag.detail)|\(flag.severity)"
            return seen.insert(key).inserted
        }
    }
}
