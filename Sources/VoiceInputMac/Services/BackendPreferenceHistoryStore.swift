import Foundation

struct HistoricalBackendPreferenceEvent: Codable, Sendable {
    let timestamp: Date
    let candidateDelta: Int
    let acceptedDelta: Int
    let readyForReviewDelta: Int
    let hintMissedDelta: Int
}

struct HistoricalBackendPreferenceStat: Codable, Sendable {
    let triggerFlag: String
    let backend: String
    var candidateCount: Int
    var acceptedCount: Int
    var readyForReviewCount: Int
    var hintMissedCount: Int
    var recentEvents: [HistoricalBackendPreferenceEvent]
    var lastUpdatedAt: Date?

    init(
        triggerFlag: String,
        backend: String,
        candidateCount: Int,
        acceptedCount: Int,
        readyForReviewCount: Int,
        hintMissedCount: Int,
        recentEvents: [HistoricalBackendPreferenceEvent] = [],
        lastUpdatedAt: Date? = nil
    ) {
        self.triggerFlag = triggerFlag
        self.backend = backend
        self.candidateCount = candidateCount
        self.acceptedCount = acceptedCount
        self.readyForReviewCount = readyForReviewCount
        self.hintMissedCount = hintMissedCount
        self.recentEvents = recentEvents
        self.lastUpdatedAt = lastUpdatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        triggerFlag = try container.decode(String.self, forKey: .triggerFlag)
        backend = try container.decode(String.self, forKey: .backend)
        candidateCount = try container.decode(Int.self, forKey: .candidateCount)
        acceptedCount = try container.decode(Int.self, forKey: .acceptedCount)
        readyForReviewCount = try container.decode(Int.self, forKey: .readyForReviewCount)
        hintMissedCount = try container.decode(Int.self, forKey: .hintMissedCount)
        recentEvents = try container.decodeIfPresent([HistoricalBackendPreferenceEvent].self, forKey: .recentEvents) ?? []
        lastUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .lastUpdatedAt)
    }
}

actor BackendPreferenceHistoryStore {
    private let defaultsKey = "voice_input_mac_backend_preference_history_v1"
    private let maxRecentEvents: Int
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var stats: [String: HistoricalBackendPreferenceStat] = [:]

    init(
        userDefaults: UserDefaults = .standard,
        maxRecentEvents: Int = 12
    ) {
        self.userDefaults = userDefaults
        self.maxRecentEvents = maxRecentEvents

        if let data = userDefaults.data(forKey: defaultsKey),
           let stored = try? decoder.decode([HistoricalBackendPreferenceStat].self, from: data) {
            self.stats = Dictionary(
                uniqueKeysWithValues: stored.map { (Self.key(triggerFlag: $0.triggerFlag, backend: $0.backend), $0) }
            )
        }
    }

    func snapshot() -> [HistoricalBackendPreferenceStat] {
        stats.values.sorted {
            if $0.triggerFlag == $1.triggerFlag {
                return $0.backend < $1.backend
            }
            return $0.triggerFlag < $1.triggerFlag
        }
    }

    func recordOutcome(
        triggerFlags: [String],
        records: [ReRecognitionCandidateRecord],
        bestBackend: String?,
        readyForReview: Bool,
        recommendedBackend: String?
    ) {
        let normalizedFlags = Array(Set(triggerFlags)).sorted()
        guard !normalizedFlags.isEmpty else { return }
        let timestamp = Date()
        var deltas: [String: HistoricalBackendPreferenceEvent] = [:]

        for record in records {
            for flag in normalizedFlags {
                let key = Self.key(triggerFlag: flag, backend: record.backend)
                let existing = deltas[key] ?? HistoricalBackendPreferenceEvent(
                    timestamp: timestamp,
                    candidateDelta: 0,
                    acceptedDelta: 0,
                    readyForReviewDelta: 0,
                    hintMissedDelta: 0
                )
                deltas[key] = HistoricalBackendPreferenceEvent(
                    timestamp: timestamp,
                    candidateDelta: existing.candidateDelta + 1,
                    acceptedDelta: existing.acceptedDelta + (record.shouldPromoteCandidate ? 1 : 0),
                    readyForReviewDelta: existing.readyForReviewDelta,
                    hintMissedDelta: existing.hintMissedDelta
                )
            }
        }

        if let bestBackend, readyForReview {
            for flag in normalizedFlags {
                let key = Self.key(triggerFlag: flag, backend: bestBackend)
                let existing = deltas[key] ?? HistoricalBackendPreferenceEvent(
                    timestamp: timestamp,
                    candidateDelta: 0,
                    acceptedDelta: 0,
                    readyForReviewDelta: 0,
                    hintMissedDelta: 0
                )
                deltas[key] = HistoricalBackendPreferenceEvent(
                    timestamp: timestamp,
                    candidateDelta: existing.candidateDelta,
                    acceptedDelta: existing.acceptedDelta,
                    readyForReviewDelta: existing.readyForReviewDelta + 1,
                    hintMissedDelta: existing.hintMissedDelta
                )
            }
        }

        if let recommendedBackend,
           recommendedBackend != bestBackend {
            for flag in normalizedFlags {
                let key = Self.key(triggerFlag: flag, backend: recommendedBackend)
                let existing = deltas[key] ?? HistoricalBackendPreferenceEvent(
                    timestamp: timestamp,
                    candidateDelta: 0,
                    acceptedDelta: 0,
                    readyForReviewDelta: 0,
                    hintMissedDelta: 0
                )
                deltas[key] = HistoricalBackendPreferenceEvent(
                    timestamp: timestamp,
                    candidateDelta: existing.candidateDelta,
                    acceptedDelta: existing.acceptedDelta,
                    readyForReviewDelta: existing.readyForReviewDelta,
                    hintMissedDelta: existing.hintMissedDelta + 1
                )
            }
        }

        for (key, event) in deltas {
            let parts = key.components(separatedBy: "|")
            guard parts.count == 2 else { continue }
            mutate(flag: parts[0], backend: parts[1], event: event)
        }

        persist()
    }

    private func mutate(
        flag: String,
        backend: String,
        event: HistoricalBackendPreferenceEvent
    ) {
        let key = Self.key(triggerFlag: flag, backend: backend)
        var stat = stats[key] ?? HistoricalBackendPreferenceStat(
            triggerFlag: flag,
            backend: backend,
            candidateCount: 0,
            acceptedCount: 0,
            readyForReviewCount: 0,
            hintMissedCount: 0
        )
        stat.candidateCount += event.candidateDelta
        stat.acceptedCount += event.acceptedDelta
        stat.readyForReviewCount += event.readyForReviewDelta
        stat.hintMissedCount += event.hintMissedDelta
        stat.lastUpdatedAt = event.timestamp
        stat.recentEvents.append(event)
        if stat.recentEvents.count > maxRecentEvents {
            stat.recentEvents.removeFirst(stat.recentEvents.count - maxRecentEvents)
        }
        stats[key] = stat
    }

    private func persist() {
        let payload = Array(stats.values)
        guard let data = try? encoder.encode(payload) else { return }
        userDefaults.set(data, forKey: defaultsKey)
    }

    private static func key(triggerFlag: String, backend: String) -> String {
        "\(triggerFlag)|\(backend)"
    }
}
