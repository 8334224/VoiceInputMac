import Foundation

enum ReRecognitionExperimentSampleLabel: String, Codable, Sendable {
    case hotword
    case englishAbbreviation = "english_abbreviation"
    case numberUnit = "number_unit"
    case longSentence = "long_sentence"
}

struct ReRecognitionExperimentTag: Codable, Sendable {
    let sampleLabel: ReRecognitionExperimentSampleLabel?
    let sessionTag: String?
}

struct ReRecognitionExperimentExport: Codable, Sendable {
    struct SuspicionFlagExport: Codable, Sendable {
        let code: String
        let detail: String
        let severity: Int
    }

    struct TranscriptSegmentExport: Codable, Sendable {
        let id: String
        let text: String
        let startTime: TimeInterval
        let endTime: TimeInterval
        let isFinal: Bool
        let source: String
        let suspicionFlags: [SuspicionFlagExport]
    }

    struct TranscriptExport: Codable, Sendable {
        let rawText: String
        let displayText: String
        let isFinal: Bool
        let source: String
        let segments: [TranscriptSegmentExport]
    }

    struct HintEffectivenessExport: Codable, Sendable {
        let groupsWithHints: Int
        let recommendedBecameBestCount: Int
        let recommendedReadyForReviewCount: Int
        let hintMissedCount: Int
    }

    struct OrderEffectivenessStatsExport: Codable, Sendable {
        let planCount: Int
        let recommendedBecameBestCount: Int
        let recommendedBecameBestRatio: Double
        let recommendedReadyForReviewCount: Int
        let recommendedReadyForReviewRatio: Double
        let firstTriedBecameBestCount: Int
        let firstTriedBecameBestRatio: Double
        let bestFromNonFirstBackendCount: Int
        let bestFromNonFirstBackendRatio: Double
    }

    struct OrderStrategySourceExport: Codable, Sendable {
        let source: String
        let stats: OrderEffectivenessStatsExport
    }

    struct OrderModeExport: Codable, Sendable {
        let mode: String
        let stats: OrderEffectivenessStatsExport
    }

    struct OrderEffectivenessExport: Codable, Sendable {
        let overall: OrderEffectivenessStatsExport
        let byStrategySource: [OrderStrategySourceExport]
        let byMode: [OrderModeExport]
    }

    struct BackendHintExport: Codable, Sendable {
        let triggerFlag: String
        let preferredBackend: String
        let source: String
        let score: Int
        let reasons: [String]
        let confidence: String
        let sampleCount: Int
        let meetsSampleThreshold: Bool
        let weighting: String
    }

    struct BackendHintsExport: Codable, Sendable {
        let session: [BackendHintExport]
        let historical: [BackendHintExport]
        let blended: [BackendHintExport]
    }

    struct BackendComparisonCandidateExport: Codable, Sendable {
        let backend: String
        let candidateText: String
        let score: Int
        let shouldPromoteCandidate: Bool
        let replacementMode: String
    }

    struct BackendComparisonExport: Codable, Sendable {
        let planID: String
        let segmentIDs: [String]
        let originalText: String
        let startTime: TimeInterval
        let endTime: TimeInterval
        let triggerFlags: [String]
        let candidates: [BackendComparisonCandidateExport]
        let bestCandidateBackend: String?
        let bestCandidateText: String?
        let hasTextDivergence: Bool
        let hasScoreDivergence: Bool
        let divergenceReasons: [String]
        let suitableForOrderComparison: Bool
    }

    struct BackendDivergenceExport: Codable, Sendable {
        let comparedPlanCount: Int
        let multiBackendPlanCount: Int
        let textDivergenceCount: Int
        let scoreDivergenceCount: Int
        let suitableForOrderComparisonCount: Int
        let suitableForOrderComparisonRatio: Double
    }

    struct BackendAttemptExport: Codable, Sendable {
        let planID: String
        let segmentIDs: [String]
        let backend: String
        let status: String
        let failureReason: String?
        let attemptedAt: Date
        let completedAt: Date?
    }

    let sessionID: String?
    let exportedAt: Date
    let currentOrderMode: String
    let experimentTag: ReRecognitionExperimentTag
    let transcript: TranscriptExport?
    let orderEffectiveness: OrderEffectivenessExport
    let backendHints: BackendHintsExport
    let hintEffectiveness: HintEffectivenessExport
    let backendComparisons: [BackendComparisonExport]
    let backendDivergence: BackendDivergenceExport
    let backendAttempts: [BackendAttemptExport]

    init(
        summary: ReRecognitionSessionSummary,
        experimentTag: ReRecognitionExperimentTag,
        transcript: RecognitionResultSnapshot?
    ) {
        sessionID = summary.sessionID?.uuidString
        exportedAt = Date()
        currentOrderMode = summary.currentOrderMode.rawValue
        self.experimentTag = experimentTag
        self.transcript = transcript.map(Self.makeTranscript)
        orderEffectiveness = OrderEffectivenessExport(
            overall: Self.makeOrderStats(summary.orderEffectiveness.overall),
            byStrategySource: summary.orderEffectiveness.byStrategySource.map {
                OrderStrategySourceExport(
                    source: $0.source.rawValue,
                    stats: Self.makeOrderStats($0.stats)
                )
            },
            byMode: summary.orderEffectiveness.byMode.map {
                OrderModeExport(
                    mode: $0.mode.rawValue,
                    stats: Self.makeOrderStats($0.stats)
                )
            }
        )
        backendHints = BackendHintsExport(
            session: summary.sessionBackendPreferenceHints.map(Self.makeBackendHint),
            historical: summary.historicalBackendPreferenceHints.map(Self.makeBackendHint),
            blended: summary.blendedBackendPreferenceHints.map(Self.makeBackendHint)
        )
        hintEffectiveness = HintEffectivenessExport(
            groupsWithHints: summary.hintEffectiveness.groupsWithHints,
            recommendedBecameBestCount: summary.hintEffectiveness.recommendedBecameBestCount,
            recommendedReadyForReviewCount: summary.hintEffectiveness.recommendedReadyForReviewCount,
            hintMissedCount: summary.hintEffectiveness.hintMissedCount
        )
        backendComparisons = summary.backendComparisons.map(Self.makeBackendComparison)
        backendDivergence = BackendDivergenceExport(
            comparedPlanCount: summary.backendDivergence.comparedPlanCount,
            multiBackendPlanCount: summary.backendDivergence.multiBackendPlanCount,
            textDivergenceCount: summary.backendDivergence.textDivergenceCount,
            scoreDivergenceCount: summary.backendDivergence.scoreDivergenceCount,
            suitableForOrderComparisonCount: summary.backendDivergence.suitableForOrderComparisonCount,
            suitableForOrderComparisonRatio: summary.backendDivergence.suitableForOrderComparisonRatio
        )
        backendAttempts = summary.backendAttempts.map {
            BackendAttemptExport(
                planID: $0.planID,
                segmentIDs: $0.segmentIDs,
                backend: $0.backend,
                status: $0.status,
                failureReason: $0.failureReason,
                attemptedAt: $0.attemptedAt,
                completedAt: $0.completedAt
            )
        }
    }

    private static func makeOrderStats(
        _ stats: ReRecognitionSessionSummary.OrderEffectivenessStats
    ) -> OrderEffectivenessStatsExport {
        OrderEffectivenessStatsExport(
            planCount: stats.planCount,
            recommendedBecameBestCount: stats.recommendedBecameBestCount,
            recommendedBecameBestRatio: stats.recommendedBecameBestRatio,
            recommendedReadyForReviewCount: stats.recommendedReadyForReviewCount,
            recommendedReadyForReviewRatio: stats.recommendedReadyForReviewRatio,
            firstTriedBecameBestCount: stats.firstTriedBecameBestCount,
            firstTriedBecameBestRatio: stats.firstTriedBecameBestRatio,
            bestFromNonFirstBackendCount: stats.bestFromNonFirstBackendCount,
            bestFromNonFirstBackendRatio: stats.bestFromNonFirstBackendRatio
        )
    }

    private static func makeBackendHint(
        _ hint: ReRecognitionSessionSummary.BackendPreferenceHint
    ) -> BackendHintExport {
        BackendHintExport(
            triggerFlag: hint.triggerFlag,
            preferredBackend: hint.preferredBackend,
            source: hint.source.rawValue,
            score: hint.score,
            reasons: hint.reasons,
            confidence: hint.confidence.rawValue,
            sampleCount: hint.sampleCount,
            meetsSampleThreshold: hint.meetsSampleThreshold,
            weighting: hint.weighting
        )
    }

    private static func makeBackendComparison(
        _ summary: ReRecognitionSessionSummary.BackendComparisonSummary
    ) -> BackendComparisonExport {
        BackendComparisonExport(
            planID: summary.planID,
            segmentIDs: summary.segmentIDs,
            originalText: summary.originalText,
            startTime: summary.startTime,
            endTime: summary.endTime,
            triggerFlags: summary.triggerFlags,
            candidates: summary.candidates.map { candidate in
                BackendComparisonCandidateExport(
                    backend: candidate.backend,
                    candidateText: candidate.candidateText,
                    score: candidate.score,
                    shouldPromoteCandidate: candidate.shouldPromoteCandidate,
                    replacementMode: candidate.replacementMode
                )
            },
            bestCandidateBackend: summary.bestCandidateBackend,
            bestCandidateText: summary.bestCandidateText,
            hasTextDivergence: summary.hasTextDivergence,
            hasScoreDivergence: summary.hasScoreDivergence,
            divergenceReasons: summary.divergenceReasons,
            suitableForOrderComparison: summary.suitableForOrderComparison
        )
    }

    private static func makeTranscript(
        _ transcript: RecognitionResultSnapshot
    ) -> TranscriptExport {
        TranscriptExport(
            rawText: transcript.rawText,
            displayText: transcript.displayText,
            isFinal: transcript.isFinal,
            source: transcript.source,
            segments: transcript.segments.map(makeTranscriptSegment)
        )
    }

    private static func makeTranscriptSegment(
        _ segment: TranscriptSegment
    ) -> TranscriptSegmentExport {
        TranscriptSegmentExport(
            id: segment.id,
            text: segment.text,
            startTime: segment.startTime,
            endTime: segment.endTime,
            isFinal: segment.isFinal,
            source: segment.source,
            suspicionFlags: segment.suspicionFlags.map(makeSuspicionFlag)
        )
    }

    private static func makeSuspicionFlag(
        _ flag: SuspicionFlag
    ) -> SuspicionFlagExport {
        SuspicionFlagExport(
            code: flag.code,
            detail: flag.detail,
            severity: flag.severity
        )
    }
}

enum ReRecognitionExperimentExportStore {
    static let directoryName = "ReRecognitionExperiments"
    static let appSupportFolderName = "VoiceInputMac"

    static func directoryURL(fileManager: FileManager = .default) throws -> URL {
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = appSupportURL
            .appendingPathComponent(appSupportFolderName, isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    static func makeFilename(for export: ReRecognitionExperimentExport) -> String {
        let sessionTag = sanitizeFilenameComponent(export.experimentTag.sessionTag ?? "untagged")
        let mode = sanitizeFilenameComponent(export.currentOrderMode)
        let timestamp = makeTimestampString(from: export.exportedAt)
        return "\(sessionTag)__\(mode)__\(timestamp).json"
    }

    static func save(
        export: ReRecognitionExperimentExport,
        prettyPrinted: Bool = true,
        fileManager: FileManager = .default
    ) throws -> URL {
        let directoryURL = try directoryURL(fileManager: fileManager)
        let fileURL = directoryURL.appendingPathComponent(makeFilename(for: export), isDirectory: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(export)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private static func makeTimestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private static func sanitizeFilenameComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitizedScalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let collapsed = String(sanitizedScalars)
            .replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return collapsed.isEmpty ? "untagged" : collapsed
    }
}
